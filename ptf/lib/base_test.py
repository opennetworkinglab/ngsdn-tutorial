# Copyright 2013-present Barefoot Networks, Inc.
# Copyright 2018-present Open Networking Foundation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

#
# Antonin Bas (antonin@barefootnetworks.com)
# Carmelo Cascone (carmelo@opennetworking.org)
#

import logging
# https://stackoverflow.com/questions/24812604/hide-scapy-warning-message-ipv6
logging.getLogger("scapy.runtime").setLevel(logging.ERROR)

import itertools
import Queue
import sys
import threading
import time
from StringIO import StringIO
from functools import wraps, partial
from unittest import SkipTest

import google.protobuf.text_format
import grpc
import ptf
import scapy.packet
import scapy.utils
from google.protobuf import text_format
from google.rpc import status_pb2, code_pb2
from ipaddress import ip_address
from p4.config.v1 import p4info_pb2
from p4.v1 import p4runtime_pb2, p4runtime_pb2_grpc
from ptf import config
from ptf import testutils as testutils
from ptf.base_tests import BaseTest
from ptf.dataplane import match_exp_pkt
from ptf.packet import IPv6
from scapy.layers.inet6 import *
from scapy.layers.l2 import Ether
from scapy.pton_ntop import inet_pton, inet_ntop
from scapy.utils6 import in6_getnsma, in6_getnsmac

from helper import P4InfoHelper

DEFAULT_PRIORITY = 10

IPV6_MCAST_MAC_1 = "33:33:00:00:00:01"

SWITCH1_MAC = "00:00:00:00:aa:01"
SWITCH2_MAC = "00:00:00:00:aa:02"
SWITCH3_MAC = "00:00:00:00:aa:03"
HOST1_MAC = "00:00:00:00:00:01"
HOST2_MAC = "00:00:00:00:00:02"

MAC_BROADCAST = "FF:FF:FF:FF:FF:FF"
MAC_FULL_MASK = "FF:FF:FF:FF:FF:FF"
MAC_MULTICAST = "33:33:00:00:00:00"
MAC_MULTICAST_MASK = "FF:FF:00:00:00:00"

SWITCH1_IPV6 = "2001:0:1::1"
SWITCH2_IPV6 = "2001:0:2::1"
SWITCH3_IPV6 = "2001:0:3::1"
SWITCH4_IPV6 = "2001:0:4::1"
HOST1_IPV6 = "2001:0000:85a3::8a2e:370:1111"
HOST2_IPV6 = "2001:0000:85a3::8a2e:370:2222"
IPV6_MASK_ALL = "FFFF:FFFF:FFFF:FFFF:FFFF:FFFF:FFFF:FFFF"

ARP_ETH_TYPE = 0x0806
IPV6_ETH_TYPE = 0x86DD

ICMPV6_IP_PROTO = 58
NS_ICMPV6_TYPE = 135
NA_ICMPV6_TYPE = 136

# FIXME: this should be removed, use generic packet in test
PACKET_IN_INGRESS_PORT_META_ID = 1


def print_inline(text):
    sys.stdout.write(text)
    sys.stdout.flush()


# See https://gist.github.com/carymrobbins/8940382
# functools.partialmethod is introduced in Python 3.4
class partialmethod(partial):
    def __get__(self, instance, owner):
        if instance is None:
            return self
        return partial(self.func, instance,
                       *(self.args or ()), **(self.keywords or {}))


# Convert integer (with length) to binary byte string
# Equivalent to Python 3.2 int.to_bytes
# See
# https://stackoverflow.com/questions/16022556/has-python-3-to-bytes-been-back-ported-to-python-2-7
def stringify(n, length):
    h = '%x' % n
    s = ('0' * (len(h) % 2) + h).zfill(length * 2).decode('hex')
    return s


def ipv4_to_binary(addr):
    bytes_ = [int(b, 10) for b in addr.split('.')]
    return "".join(chr(b) for b in bytes_)


def ipv6_to_binary(addr):
    ip = ip_address(addr.decode("utf-8"))
    return ip.packed


def mac_to_binary(addr):
    bytes_ = [int(b, 16) for b in addr.split(':')]
    return "".join(chr(b) for b in bytes_)


def format_pkt_match(received_pkt, expected_pkt):
    # Taken from PTF dataplane class
    stdout_save = sys.stdout
    try:
        # The scapy packet dissection methods print directly to stdout,
        # so we have to redirect stdout to a string.
        sys.stdout = StringIO()

        print "========== EXPECTED =========="
        if isinstance(expected_pkt, scapy.packet.Packet):
            scapy.packet.ls(expected_pkt)
            print '--'
        scapy.utils.hexdump(expected_pkt)
        print "========== RECEIVED =========="
        if isinstance(received_pkt, scapy.packet.Packet):
            scapy.packet.ls(received_pkt)
            print '--'
        scapy.utils.hexdump(received_pkt)
        print "=============================="

        return sys.stdout.getvalue()
    finally:
        sys.stdout.close()
        sys.stdout = stdout_save  # Restore the original stdout.


def format_pb_msg_match(received_msg, expected_msg):
    result = StringIO()
    result.write("========== EXPECTED PROTO ==========\n")
    result.write(text_format.MessageToString(expected_msg))
    result.write("========== RECEIVED PROTO ==========\n")
    result.write(text_format.MessageToString(received_msg))
    result.write("==============================\n")
    val = result.getvalue()
    result.close()
    return val


def pkt_mac_swap(pkt):
    orig_dst = pkt[Ether].dst
    pkt[Ether].dst = pkt[Ether].src
    pkt[Ether].src = orig_dst
    return pkt


def pkt_route(pkt, mac_dst):
    pkt[Ether].src = pkt[Ether].dst
    pkt[Ether].dst = mac_dst
    return pkt


def pkt_decrement_ttl(pkt):
    if IP in pkt:
        pkt[IP].ttl -= 1
    elif IPv6 in pkt:
        pkt[IPv6].hlim -= 1
    return pkt


def genNdpNsPkt(target_ip, src_mac=HOST1_MAC, src_ip=HOST1_IPV6):
    nsma = in6_getnsma(inet_pton(socket.AF_INET6, target_ip))
    d = inet_ntop(socket.AF_INET6, nsma)
    dm = in6_getnsmac(nsma)
    p = Ether(dst=dm) / IPv6(dst=d, src=src_ip, hlim=255)
    p /= ICMPv6ND_NS(tgt=target_ip)
    p /= ICMPv6NDOptSrcLLAddr(lladdr=src_mac)
    return p


def genNdpNaPkt(target_ip, target_mac,
                src_mac=SWITCH1_MAC, dst_mac=IPV6_MCAST_MAC_1,
                src_ip=SWITCH1_IPV6, dst_ip=HOST1_IPV6):
    p = Ether(src=src_mac, dst=dst_mac)
    p /= IPv6(dst=dst_ip, src=src_ip, hlim=255)
    p /= ICMPv6ND_NA(tgt=target_ip)
    p /= ICMPv6NDOptDstLLAddr(lladdr=target_mac)
    return p


class P4RuntimeErrorFormatException(Exception):
    """Used to indicate that the gRPC error Status object returned by the server has
    an incorrect format.
    """

    def __init__(self, message):
        super(P4RuntimeErrorFormatException, self).__init__(message)


# Used to iterate over the p4.Error messages in a gRPC error Status object
class P4RuntimeErrorIterator:
    def __init__(self, grpc_error):
        assert (grpc_error.code() == grpc.StatusCode.UNKNOWN)
        self.grpc_error = grpc_error

        error = None
        # The gRPC Python package does not have a convenient way to access the
        # binary details for the error: they are treated as trailing metadata.
        for meta in itertools.chain(self.grpc_error.initial_metadata(),
                                    self.grpc_error.trailing_metadata()):
            if meta[0] == "grpc-status-details-bin":
                error = status_pb2.Status()
                error.ParseFromString(meta[1])
                break
        if error is None:
            raise P4RuntimeErrorFormatException("No binary details field")

        if len(error.details) == 0:
            raise P4RuntimeErrorFormatException(
                "Binary details field has empty Any details repeated field")
        self.errors = error.details
        self.idx = 0

    def __iter__(self):
        return self

    def next(self):
        while self.idx < len(self.errors):
            p4_error = p4runtime_pb2.Error()
            one_error_any = self.errors[self.idx]
            if not one_error_any.Unpack(p4_error):
                raise P4RuntimeErrorFormatException(
                    "Cannot convert Any message to p4.Error")
            if p4_error.canonical_code == code_pb2.OK:
                continue
            v = self.idx, p4_error
            self.idx += 1
            return v
        raise StopIteration


# P4Runtime uses a 3-level message in case of an error during the processing of
# a write batch. This means that if we do not wrap the grpc.RpcError inside a
# custom exception, we can end-up with a non-helpful exception message in case
# of failure as only the first level will be printed. In this custom exception
# class, we extract the nested error message (one for each operation included in
# the batch) in order to print error code + user-facing message.  See P4 Runtime
# documentation for more details on error-reporting.
class P4RuntimeWriteException(Exception):
    def __init__(self, grpc_error):
        assert (grpc_error.code() == grpc.StatusCode.UNKNOWN)
        super(P4RuntimeWriteException, self).__init__()
        self.errors = []
        try:
            error_iterator = P4RuntimeErrorIterator(grpc_error)
            for error_tuple in error_iterator:
                self.errors.append(error_tuple)
        except P4RuntimeErrorFormatException:
            raise  # just propagate exception for now

    def __str__(self):
        message = "Error(s) during Write:\n"
        for idx, p4_error in self.errors:
            code_name = code_pb2._CODE.values_by_number[
                p4_error.canonical_code].name
            message += "\t* At index {}: {}, '{}'\n".format(
                idx, code_name, p4_error.message)
        return message


# This code is common to all tests. setUp() is invoked at the beginning of the
# test and tearDown is called at the end, no matter whether the test passed /
# failed / errored.
# noinspection PyUnresolvedReferences
class P4RuntimeTest(BaseTest):
    def setUp(self):
        BaseTest.setUp(self)

        # Setting up PTF dataplane
        self.dataplane = ptf.dataplane_instance
        self.dataplane.flush()

        self._swports = []
        for device, port, ifname in config["interfaces"]:
            self._swports.append(port)

        self.port1 = self.swports(0)
        self.port2 = self.swports(1)
        self.port3 = self.swports(2)

        grpc_addr = testutils.test_param_get("grpcaddr")
        if grpc_addr is None:
            grpc_addr = 'localhost:50051'

        self.device_id = int(testutils.test_param_get("device_id"))
        if self.device_id is None:
            self.fail("Device ID is not set")

        self.cpu_port = int(testutils.test_param_get("cpu_port"))
        if self.cpu_port is None:
            self.fail("CPU port is not set")

        pltfm = testutils.test_param_get("pltfm")
        if pltfm is not None and pltfm == 'hw' and getattr(self, "_skip_on_hw",
                                                           False):
            raise SkipTest("Skipping test in HW")

        self.channel = grpc.insecure_channel(grpc_addr)
        self.stub = p4runtime_pb2_grpc.P4RuntimeStub(self.channel)

        proto_txt_path = testutils.test_param_get("p4info")
        # print "Importing p4info proto from", proto_txt_path
        self.p4info = p4info_pb2.P4Info()
        with open(proto_txt_path, "rb") as fin:
            google.protobuf.text_format.Merge(fin.read(), self.p4info)

        self.helper = P4InfoHelper(proto_txt_path)

        # used to store write requests sent to the P4Runtime server, useful for
        # autocleanup of tests (see definition of autocleanup decorator below)
        self.reqs = []

        self.election_id = 1
        self.set_up_stream()

    def set_up_stream(self):
        self.stream_out_q = Queue.Queue()
        self.stream_in_q = Queue.Queue()

        def stream_req_iterator():
            while True:
                p = self.stream_out_q.get()
                if p is None:
                    break
                yield p

        def stream_recv(stream):
            for p in stream:
                self.stream_in_q.put(p)

        self.stream = self.stub.StreamChannel(stream_req_iterator())
        self.stream_recv_thread = threading.Thread(
            target=stream_recv, args=(self.stream,))
        self.stream_recv_thread.start()

        self.handshake()

    def handshake(self):
        req = p4runtime_pb2.StreamMessageRequest()
        arbitration = req.arbitration
        arbitration.device_id = self.device_id
        election_id = arbitration.election_id
        election_id.high = 0
        election_id.low = self.election_id
        self.stream_out_q.put(req)

        rep = self.get_stream_packet("arbitration", timeout=2)
        if rep is None:
            self.fail("Failed to establish handshake")

    def tearDown(self):
        self.tear_down_stream()
        BaseTest.tearDown(self)

    def tear_down_stream(self):
        self.stream_out_q.put(None)
        self.stream_recv_thread.join()

    def get_packet_in(self, timeout=2):
        msg = self.get_stream_packet("packet", timeout)
        if msg is None:
            self.fail("PacketIn message not received")
        else:
            return msg.packet

    def verify_packet_in(self, exp_packet_in_msg, timeout=2):
        rx_packet_in_msg = self.get_packet_in(timeout=timeout)

        # Check payload first, then metadata
        rx_pkt = Ether(rx_packet_in_msg.payload)
        exp_pkt = exp_packet_in_msg.payload
        if not match_exp_pkt(exp_pkt, rx_pkt):
            self.fail("Received PacketIn.payload is not the expected one\n"
                      + format_pkt_match(rx_pkt, exp_pkt))

        rx_meta_dict = {m.metadata_id: m.value
                        for m in rx_packet_in_msg.metadata}
        exp_meta_dict = {m.metadata_id: m.value
                         for m in exp_packet_in_msg.metadata}
        shared_meta = {mid: rx_meta_dict[mid] for mid in rx_meta_dict
                       if mid in exp_meta_dict
                       and rx_meta_dict[mid] == exp_meta_dict[mid]}

        if len(rx_meta_dict) is not len(exp_meta_dict) \
                or len(shared_meta) is not len(exp_meta_dict):
            self.fail("Received PacketIn.metadata is not the expected one\n"
                      + format_pb_msg_match(rx_packet_in_msg,
                                            exp_packet_in_msg))

    def get_stream_packet(self, type_, timeout=1):
        start = time.time()
        try:
            while True:
                remaining = timeout - (time.time() - start)
                if remaining < 0:
                    break
                msg = self.stream_in_q.get(timeout=remaining)
                if not msg.HasField(type_):
                    continue
                return msg
        except:  # timeout expired
            pass
        return None

    def send_packet_out(self, packet):
        packet_out_req = p4runtime_pb2.StreamMessageRequest()
        packet_out_req.packet.CopyFrom(packet)
        self.stream_out_q.put(packet_out_req)

    def swports(self, idx):
        if idx >= len(self._swports):
            self.fail("Index {} is out-of-bound of port map".format(idx))
        return self._swports[idx]

    def _write(self, req):
        try:
            return self.stub.Write(req)
        except grpc.RpcError as e:
            if e.code() != grpc.StatusCode.UNKNOWN:
                raise e
            raise P4RuntimeWriteException(e)

    def write_request(self, req, store=True):
        rep = self._write(req)
        if store:
            self.reqs.append(req)
        return rep

    def insert(self, entity):
        if isinstance(entity, list) or isinstance(entity, tuple):
            for e in entity:
                self.insert(e)
            return
        req = self.get_new_write_request()
        update = req.updates.add()
        update.type = p4runtime_pb2.Update.INSERT
        if isinstance(entity, p4runtime_pb2.TableEntry):
            msg_entity = update.entity.table_entry
        elif isinstance(entity, p4runtime_pb2.ActionProfileGroup):
            msg_entity = update.entity.action_profile_group
        elif isinstance(entity, p4runtime_pb2.ActionProfileMember):
            msg_entity = update.entity.action_profile_member
        else:
            self.fail("Entity %s not supported" % entity.__name__)
        msg_entity.CopyFrom(entity)
        self.write_request(req)

    def get_new_write_request(self):
        req = p4runtime_pb2.WriteRequest()
        req.device_id = self.device_id
        election_id = req.election_id
        election_id.high = 0
        election_id.low = self.election_id
        return req

    def insert_pre_multicast_group(self, group_id, ports):
        req = self.get_new_write_request()
        update = req.updates.add()
        update.type = p4runtime_pb2.Update.INSERT
        pre_entry = update.entity.packet_replication_engine_entry
        mg_entry = pre_entry.multicast_group_entry
        mg_entry.multicast_group_id = group_id
        for port in ports:
            replica = mg_entry.replicas.add()
            replica.egress_port = port
            replica.instance = 0
        return req, self.write_request(req)

    def insert_pre_clone_session(self, session_id, ports, cos=0,
                                 packet_length_bytes=0):
        req = self.get_new_write_request()
        update = req.updates.add()
        update.type = p4runtime_pb2.Update.INSERT
        pre_entry = update.entity.packet_replication_engine_entry
        clone_entry = pre_entry.clone_session_entry
        clone_entry.session_id = session_id
        clone_entry.class_of_service = cos
        clone_entry.packet_length_bytes = packet_length_bytes
        for port in ports:
            replica = clone_entry.replicas.add()
            replica.egress_port = port
            replica.instance = 1
        return req, self.write_request(req)

    # iterates over all requests in reverse order; if they are INSERT updates,
    # replay them as DELETE updates; this is a convenient way to clean-up a lot
    # of switch state
    def undo_write_requests(self, reqs):
        updates = []
        for req in reversed(reqs):
            for update in reversed(req.updates):
                if update.type == p4runtime_pb2.Update.INSERT:
                    updates.append(update)
        new_req = self.get_new_write_request()
        for update in updates:
            update.type = p4runtime_pb2.Update.DELETE
            new_req.updates.add().CopyFrom(update)
        self._write(new_req)


# this decorator can be used on the runTest method of P4Runtime PTF tests
# when it is used, the undo_write_requests will be called at the end of the test
# (irrespective of whether the test was a failure, a success, or an exception
# was raised). When this is used, all write requests must be performed through
# one of the send_request_* convenience functions, or by calling write_request;
# do not use stub.Write directly!
# most of the time, it is a great idea to use this decorator, as it makes the
# tests less verbose. In some circumstances, it is difficult to use it, in
# particular when the test itself issues DELETE request to remove some
# objects. In this case you will want to do the cleanup yourself (in the
# tearDown function for example); you can still use undo_write_request which
# should make things easier.
# because the PTF test writer needs to choose whether or not to use autocleanup,
# it seems more appropriate to define a decorator for this rather than do it
# unconditionally in the P4RuntimeTest tearDown method.
def autocleanup(f):
    @wraps(f)
    def handle(*args, **kwargs):
        test = args[0]
        assert (isinstance(test, P4RuntimeTest))
        try:
            return f(*args, **kwargs)
        finally:
            test.undo_write_requests(test.reqs)

    return handle


def skip_on_hw(cls):
    cls._skip_on_hw = True
    return cls
