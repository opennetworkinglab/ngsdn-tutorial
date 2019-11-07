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

# ------------------------------------------------------------------------------
# BRIDGING TESTS
#
# To run all tests in this file:
#     make p4-test TEST=bridging
#
# To run a specific test case:
#     make p4-test TEST=bridging.<TEST CLASS NAME>
#
# For example:
#     make p4-test TEST=bridging.BridgingTest
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

# From the P4 program.
CPU_CLONE_SESSION_ID = 99


@group("bridging")
class ArpNdpRequestWithCloneTest(P4RuntimeTest):
    """Tests ability to broadcast ARP requests and NDP Neighbor Solicitation
    (NS) messages as well as cloning to CPU (controller) for host
     discovery.
    """

    def runTest(self):
        #  Test With both ARP and NDP NS packets...
        print_inline("ARP request ... ")
        arp_pkt = testutils.simple_arp_packet()
        self.testPacket(arp_pkt)

        print_inline("NDP NS ... ")
        ndp_pkt = genNdpNsPkt(src_mac=HOST1_MAC, src_ip=HOST1_IPV6,
                              target_ip=HOST2_IPV6)
        self.testPacket(ndp_pkt)

    @autocleanup
    def testPacket(self, pkt):
        mcast_group_id = 10
        mcast_ports = [self.port1, self.port2, self.port3]

        # Add multicast group.
        self.insert_pre_multicast_group(
            group_id=mcast_group_id,
            ports=mcast_ports)

        # Match eth dst: FF:FF:FF:FF:FF:FF (MAC broadcast for ARP requests)
        # Modify names to match content of P4Info file (look for the fully
        # qualified name of tables, match fields, and actions.
        # ---- START SOLUTION ----
        self.insert(self.helper.build_table_entry(
            table_name="IngressPipeImpl.l2_ternary_table",
            match_fields={
                # Ternary match.
                "hdr.ethernet.dst_addr": (
                    "FF:FF:FF:FF:FF:FF",
                    "FF:FF:FF:FF:FF:FF")
            },
            action_name="IngressPipeImpl.set_multicast_group",
            action_params={
                "gid": mcast_group_id
            },
            priority=DEFAULT_PRIORITY
        ))
        # ---- END SOLUTION ----

        # Match eth dst: 33:33:**:**:**:** (IPv6 multicast for NDP requests)
        # Modify names to match content of P4Info file (look for the fully
        # qualified name of tables, match fields, and actions.
        # ---- START SOLUTION ----
        self.insert(self.helper.build_table_entry(
            table_name="IngressPipeImpl.l2_ternary_table",
            match_fields={
                # Ternary match (value, mask)
                "hdr.ethernet.dst_addr": (
                    "33:33:00:00:00:00",
                    "FF:FF:00:00:00:00")
            },
            action_name="IngressPipeImpl.set_multicast_group",
            action_params={
                "gid": mcast_group_id
            },
            priority=DEFAULT_PRIORITY
        ))
        # ---- END SOLUTION ----

        # Insert CPU clone session.
        self.insert_pre_clone_session(
            session_id=CPU_CLONE_SESSION_ID,
            ports=[self.cpu_port])

        # ACL entry to clone ARPs
        self.insert(self.helper.build_table_entry(
            table_name="IngressPipeImpl.acl_table",
            match_fields={
                # Ternary match.
                "hdr.ethernet.ether_type": (ARP_ETH_TYPE, 0xffff)
            },
            action_name="IngressPipeImpl.clone_to_cpu",
            priority=DEFAULT_PRIORITY
        ))

        # ACL entry to clone NDP Neighbor Solicitation
        self.insert(self.helper.build_table_entry(
            table_name="IngressPipeImpl.acl_table",
            match_fields={
                # Ternary match.
                "hdr.ethernet.ether_type": (IPV6_ETH_TYPE, 0xffff),
                "local_metadata.ip_proto": (ICMPV6_IP_PROTO, 0xff),
                "local_metadata.icmp_type": (NS_ICMPV6_TYPE, 0xff)
            },
            action_name="IngressPipeImpl.clone_to_cpu",
            priority=DEFAULT_PRIORITY
        ))

        for inport in mcast_ports:

            # Send packet...
            testutils.send_packet(self, inport, str(pkt))

            # Pkt should be received on CPU via PacketIn...
            # Expected P4Runtime PacketIn message.
            exp_packet_in_msg = self.helper.build_packet_in(
                payload=str(pkt),
                metadata={
                    "ingress_port": inport,
                    "_pad": 0
                })
            self.verify_packet_in(exp_packet_in_msg)

            # ...and on all ports except the ingress one.
            verify_ports = set(mcast_ports)
            verify_ports.discard(inport)
            for port in verify_ports:
                testutils.verify_packet(self, pkt, port)

        testutils.verify_no_other_packets(self)


@group("bridging")
class ArpNdpReplyWithCloneTest(P4RuntimeTest):
    """Tests ability to clone ARP replies and NDP Neighbor Advertisement
    (NA) messages as well as unicast forwarding to requesting host.
    """

    def runTest(self):
        #  Test With both ARP and NDP NS packets...
        print_inline("ARP reply ... ")
        # op=1 request, op=2 relpy
        arp_pkt = testutils.simple_arp_packet(
            eth_src=HOST1_MAC, eth_dst=HOST2_MAC, arp_op=2)
        self.testPacket(arp_pkt)

        print_inline("NDP NA ... ")
        ndp_pkt = genNdpNaPkt(target_ip=HOST1_IPV6, target_mac=HOST1_MAC)
        self.testPacket(ndp_pkt)

    @autocleanup
    def testPacket(self, pkt):

        # L2 unicast entry, match on pkt's eth dst address.
        # Modify names to match content of P4Info file (look for the fully
        # qualified name of tables, match fields, and actions.
        # ---- START SOLUTION ----
        self.insert(self.helper.build_table_entry(
            table_name="IngressPipeImpl.l2_exact_table",
            match_fields={
                # Exact match.
                "hdr.ethernet.dst_addr": pkt[Ether].dst
            },
            action_name="IngressPipeImpl.set_egress_port",
            action_params={
                "port_num": self.port2
            }
        ))
        # ---- END SOLUTION ----

        # CPU clone session.
        self.insert_pre_clone_session(
            session_id=CPU_CLONE_SESSION_ID,
            ports=[self.cpu_port])

        # ACL entry to clone ARPs
        self.insert(self.helper.build_table_entry(
            table_name="IngressPipeImpl.acl_table",
            match_fields={
                # Ternary match.
                "hdr.ethernet.ether_type": (ARP_ETH_TYPE, 0xffff)
            },
            action_name="IngressPipeImpl.clone_to_cpu",
            priority=DEFAULT_PRIORITY
        ))

        # ACL entry to clone NDP Neighbor Solicitation
        self.insert(self.helper.build_table_entry(
            table_name="IngressPipeImpl.acl_table",
            match_fields={
                # Ternary match.
                "hdr.ethernet.ether_type": (IPV6_ETH_TYPE, 0xffff),
                "local_metadata.ip_proto": (ICMPV6_IP_PROTO, 0xff),
                "local_metadata.icmp_type": (NA_ICMPV6_TYPE, 0xff)
            },
            action_name="IngressPipeImpl.clone_to_cpu",
            priority=DEFAULT_PRIORITY
        ))

        testutils.send_packet(self, self.port1, str(pkt))

        # Pkt should be received on CPU via PacketIn...
        # Expected P4Runtime PacketIn message.
        exp_packet_in_msg = self.helper.build_packet_in(
            payload=str(pkt),
            metadata={
                "ingress_port": self.port1,
                "_pad": 0
            })
        self.verify_packet_in(exp_packet_in_msg)

        # ..and on port2 as indicated by the L2 unicast rule.
        testutils.verify_packet(self, pkt, self.port2)


@group("bridging")
class BridgingTest(P4RuntimeTest):
    """Tests basic L2 unicast forwarding"""

    def runTest(self):
        # Test with different type of packets.
        for pkt_type in ["tcp", "udp", "icmp", "tcpv6", "udpv6", "icmpv6"]:
            print_inline("%s ... " % pkt_type)
            pkt = getattr(testutils, "simple_%s_packet" % pkt_type)(pktlen=120)
            self.testPacket(pkt)

    @autocleanup
    def testPacket(self, pkt):

        # Insert L2 unicast entry, match on pkt's eth dst address.
        # Modify names to match content of P4Info file (look for the fully
        # qualified name of tables, match fields, and actions.
        # ---- START SOLUTION ----
        self.insert(self.helper.build_table_entry(
            table_name="IngressPipeImpl.l2_exact_table",
            match_fields={
                # Exact match.
                "hdr.ethernet.dst_addr": pkt[Ether].dst
            },
            action_name="IngressPipeImpl.set_egress_port",
            action_params={
                "port_num": self.port2
            }
        ))
        # ---- END SOLUTION ----

        # Test bidirectional forwarding by swapping MAC addresses on the pkt
        pkt2 = pkt_mac_swap(pkt.copy())

        # Insert L2 unicast entry for pkt2.
        # Modify names to match content of P4Info file (look for the fully
        # qualified name of tables, match fields, and actions.
        # ---- START SOLUTION ----
        self.insert(self.helper.build_table_entry(
            table_name="IngressPipeImpl.l2_exact_table",
            match_fields={
                # Exact match.
                "hdr.ethernet.dst_addr": pkt2[Ether].dst
            },
            action_name="IngressPipeImpl.set_egress_port",
            action_params={
                "port_num": self.port1
            }
        ))
        # ---- END SOLUTION ----

        # Send and verify.
        testutils.send_packet(self, self.port1, str(pkt))
        testutils.send_packet(self, self.port2, str(pkt2))

        testutils.verify_each_packet_on_each_port(
            self, [pkt, pkt2], [self.port2, self.port1])
