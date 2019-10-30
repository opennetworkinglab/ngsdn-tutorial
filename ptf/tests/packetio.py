# Copyright 2019-present Open Networking Foundation
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

# ------------------------------------------------------------------------------
# CONTROLLER PACKET-IN/OUT TESTS
#
# To run all tests in this file:
#     make p4-test TEST=packetio
#
# To run a specific test case:
#     make p4-test TEST=packetio.<TEST CLASS NAME>
#
# For example:
#     make p4-test TEST=packetio.PacketOutTest
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Modify everywhere you see TODO
#
# When providing your solution, make sure to use the same names for P4Runtime
# entities as specified in your P4Info file.
#
# Test cases are based on the P4 program design suggested in the exercises
# README. Make sure to modify the test cases accordingly if you decide to
# implement the pipeline differently.
# ------------------------------------------------------------------------------

from ptf.testutils import group

from base_test import *

CPU_CLONE_SESSION_ID = 99


@group("packetio")
class PacketOutTest(P4RuntimeTest):
    """Tests controller packet-out capability by sending PacketOut messages and
    expecting a corresponding packet on the output port set in the PacketOut
    metadata.
    """

    def runTest(self):
        for pkt_type in ["tcp", "udp", "icmp", "arp", "tcpv6", "udpv6",
                         "icmpv6"]:
            print_inline("%s ... " % pkt_type)
            pkt = getattr(testutils, "simple_%s_packet" % pkt_type)()
            self.testPacket(pkt)

    def testPacket(self, pkt):
        for outport in [self.port1, self.port2]:
            # Build PacketOut message.
            # TODO EXERCISE 4
            # Modify metadata names to match the content of your P4Info file
            # ---- START SOLUTION ----
            packet_out_msg = self.helper.build_packet_out(
                payload=str(pkt),
                metadata={
                    "egress_port": outport,
                    "_pad": 0
                })
            # ---- END SOLUTION ----

            # Send message and expect packet on the given data plane port.
            self.send_packet_out(packet_out_msg)

            testutils.verify_packet(self, pkt, outport)

        # Make sure packet was forwarded only on the specified ports
        testutils.verify_no_other_packets(self)


@group("packetio")
class PacketInTest(P4RuntimeTest):
    """Tests controller packet-in capability my matching on the packet EtherType
    and cloning to the CPU port.
    """

    def runTest(self):
        for pkt_type in ["tcp", "udp", "icmp", "arp", "tcpv6", "udpv6",
                         "icmpv6"]:
            print_inline("%s ... " % pkt_type)
            pkt = getattr(testutils, "simple_%s_packet" % pkt_type)()
            self.testPacket(pkt)

    @autocleanup
    def testPacket(self, pkt):

        # Insert clone to CPU session
        self.insert_pre_clone_session(
            session_id=CPU_CLONE_SESSION_ID,
            ports=[self.cpu_port])

        # Insert ACL entry to match on the given eth_type and clone to CPU.
        eth_type = pkt[Ether].type
        # TODO EXERCISE 4
        # Modify names to match content of P4Info file (look for the fully
        # qualified name of the ACL table, EtherType match field, and
        # clone_to_cpu action.
        # ---- START SOLUTION ----
        self.insert(self.helper.build_table_entry(
            table_name="IngressPipeImpl.acl_table",
            match_fields={
                # Ternary match.
                "hdr.ethernet.ether_type": (eth_type, 0xffff)
            },
            action_name="IngressPipeImpl.clone_to_cpu",
            priority=DEFAULT_PRIORITY
        ))
        # ---- END SOLUTION ----

        for inport in [self.port1, self.port2, self.port3]:
            # TODO EXERCISE 4
            # Modify metadata names to match the content of your P4Info file
            # ---- START SOLUTION ----
            # Expected P4Runtime PacketIn message.
            exp_packet_in_msg = self.helper.build_packet_in(
                payload=str(pkt),
                metadata={
                    "ingress_port": inport,
                    "_pad": 0
                })
            # ---- END SOLUTION ----

            # Send packet to given switch ingress port and expect P4Runtime
            # PacketIn message.
            testutils.send_packet(self, inport, str(pkt))
            self.verify_packet_in(exp_packet_in_msg)
