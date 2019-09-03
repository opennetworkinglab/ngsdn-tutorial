#!/usr/bin/env python2

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
import Queue
import argparse
import json
import logging
import os
import re
import subprocess
import sys
import threading
import time
from collections import OrderedDict

import google.protobuf.text_format
import grpc
from p4.v1 import p4runtime_pb2, p4runtime_pb2_grpc

PTF_ROOT = os.path.dirname(os.path.realpath(__file__))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("PTF runner")


def error(msg, *args, **kwargs):
    logger.error(msg, *args, **kwargs)


def warn(msg, *args, **kwargs):
    logger.warn(msg, *args, **kwargs)


def info(msg, *args, **kwargs):
    logger.info(msg, *args, **kwargs)


def debug(msg, *args, **kwargs):
    logger.debug(msg, *args, **kwargs)


def check_ifaces(ifaces):
    """
    Checks that required interfaces exist.
    """
    ifconfig_out = subprocess.check_output(['ifconfig'])
    iface_list = re.findall(r'^([a-zA-Z0-9]+)', ifconfig_out, re.S | re.M)
    present_ifaces = set(iface_list)
    ifaces = set(ifaces)
    return ifaces <= present_ifaces


def build_bmv2_config(bmv2_json_path):
    """
    Builds the device config for BMv2
    """
    with open(bmv2_json_path) as f:
        return f.read()


def update_config(p4info_path, bmv2_json_path, grpc_addr, device_id):
    """
    Performs a SetForwardingPipelineConfig on the device
    """
    channel = grpc.insecure_channel(grpc_addr)
    stub = p4runtime_pb2_grpc.P4RuntimeStub(channel)

    debug("Sending P4 config")

    # Send master arbitration via stream channel
    # This should go in library, to be re-used also by base_test.py.
    stream_out_q = Queue.Queue()
    stream_in_q = Queue.Queue()

    def stream_req_iterator():
        while True:
            p = stream_out_q.get()
            if p is None:
                break
            yield p

    def stream_recv(stream):
        for p in stream:
            stream_in_q.put(p)

    def get_stream_packet(type_, timeout=1):
        start = time.time()
        try:
            while True:
                remaining = timeout - (time.time() - start)
                if remaining < 0:
                    break
                msg = stream_in_q.get(timeout=remaining)
                if not msg.HasField(type_):
                    continue
                return msg
        except:  # timeout expired
            pass
        return None

    stream = stub.StreamChannel(stream_req_iterator())
    stream_recv_thread = threading.Thread(target=stream_recv, args=(stream,))
    stream_recv_thread.start()

    req = p4runtime_pb2.StreamMessageRequest()
    arbitration = req.arbitration
    arbitration.device_id = device_id
    election_id = arbitration.election_id
    election_id.high = 0
    election_id.low = 1
    stream_out_q.put(req)

    rep = get_stream_packet("arbitration", timeout=5)
    if rep is None:
        error("Failed to establish handshake")
        return False

    try:
        # Set pipeline config.
        request = p4runtime_pb2.SetForwardingPipelineConfigRequest()
        request.device_id = device_id
        election_id = request.election_id
        election_id.high = 0
        election_id.low = 1
        config = request.config
        with open(p4info_path, 'r') as p4info_f:
            google.protobuf.text_format.Merge(p4info_f.read(), config.p4info)
        config.p4_device_config = build_bmv2_config(bmv2_json_path)
        request.action = p4runtime_pb2.SetForwardingPipelineConfigRequest.VERIFY_AND_COMMIT
        try:
            stub.SetForwardingPipelineConfig(request)
        except Exception as e:
            error("Error during SetForwardingPipelineConfig")
            error(str(e))
            return False
        return True
    finally:
        stream_out_q.put(None)
        stream_recv_thread.join()


def run_test(p4info_path, grpc_addr, device_id, cpu_port, ptfdir, port_map_path,
             extra_args=()):
    """
    Runs PTF tests included in provided directory.
    Device must be running and configfured with appropriate P4 program.
    """
    # TODO: check schema?
    # "ptf_port" is ignored for now, we assume that ports are provided by
    # increasing values of ptf_port, in the range [0, NUM_IFACES[.
    port_map = OrderedDict()
    with open(port_map_path, 'r') as port_map_f:
        port_list = json.load(port_map_f)
        for entry in port_list:
            p4_port = entry["p4_port"]
            iface_name = entry["iface_name"]
            port_map[p4_port] = iface_name

    if not check_ifaces(port_map.values()):
        error("Some interfaces are missing")
        return False

    ifaces = []
    # FIXME
    # find base_test.py
    pypath = os.path.dirname(os.path.abspath(__file__))
    if 'PYTHONPATH' in os.environ:
        os.environ['PYTHONPATH'] += ":" + pypath
    else:
        os.environ['PYTHONPATH'] = pypath
    for iface_idx, iface_name in port_map.items():
        ifaces.extend(['-i', '{}@{}'.format(iface_idx, iface_name)])
    cmd = ['ptf']
    cmd.extend(['--test-dir', ptfdir])
    cmd.extend(ifaces)
    test_params = 'p4info=\'{}\''.format(p4info_path)
    test_params += ';grpcaddr=\'{}\''.format(grpc_addr)
    test_params += ';device_id=\'{}\''.format(device_id)
    test_params += ';cpu_port=\'{}\''.format(cpu_port)
    cmd.append('--test-params={}'.format(test_params))
    cmd.extend(extra_args)
    debug("Executing PTF command: {}".format(' '.join(cmd)))

    try:
        # we want the ptf output to be sent to stdout
        p = subprocess.Popen(cmd)
        p.wait()
    except:
        error("Error when running PTF tests")
        return False
    return p.returncode == 0


def check_ptf():
    try:
        with open(os.devnull, 'w') as devnull:
            subprocess.check_call(['ptf', '--version'],
                                  stdout=devnull, stderr=devnull)
        return True
    except subprocess.CalledProcessError:
        return True
    except OSError:  # PTF not found
        return False


# noinspection PyTypeChecker
def main():
    parser = argparse.ArgumentParser(
        description="Compile the provided P4 program and run PTF tests on it")
    parser.add_argument('--p4info',
                        help='Location of p4info proto in text format',
                        type=str, action="store", required=True)
    parser.add_argument('--bmv2-json',
                        help='Location BMv2 JSON output from p4c (if target is bmv2)',
                        type=str, action="store", required=False)
    parser.add_argument('--grpc-addr',
                        help='Address to use to connect to P4 Runtime server',
                        type=str, default='localhost:50051')
    parser.add_argument('--device-id',
                        help='Device id for device under test',
                        type=int, default=1)
    parser.add_argument('--cpu-port',
                        help='CPU port ID of device under test',
                        type=int, required=True)
    parser.add_argument('--ptf-dir',
                        help='Directory containing PTF tests',
                        type=str, required=True)
    parser.add_argument('--port-map',
                        help='Path to JSON port mapping',
                        type=str, required=True)
    args, unknown_args = parser.parse_known_args()

    if not check_ptf():
        error("Cannot find PTF executable")
        sys.exit(1)

    if not os.path.exists(args.p4info):
        error("P4Info file {} not found".format(args.p4info))
        sys.exit(1)
    if not os.path.exists(args.bmv2_json):
        error("BMv2 json file {} not found".format(args.bmv2_json))
        sys.exit(1)
    if not os.path.exists(args.port_map):
        print "Port map path '{}' does not exist".format(args.port_map)
        sys.exit(1)

    try:

        success = update_config(p4info_path=args.p4info,
                                bmv2_json_path=args.bmv2_json,
                                grpc_addr=args.grpc_addr,
                                device_id=args.device_id)
        if not success:
            sys.exit(2)

        success = run_test(p4info_path=args.p4info,
                           device_id=args.device_id,
                           grpc_addr=args.grpc_addr,
                           cpu_port=args.cpu_port,
                           ptfdir=args.ptf_dir,
                           port_map_path=args.port_map,
                           extra_args=unknown_args)

        if not success:
            sys.exit(3)

    except Exception:
        raise


if __name__ == '__main__':
    main()
