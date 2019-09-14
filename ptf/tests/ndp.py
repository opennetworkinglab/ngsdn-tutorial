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
# NDP GENERATION TESTS
#
# To run all tests:
#     make ndp
#
# To run a specific test case:
#     make ndp.<TEST CLASS NAME>
#
# For example:
#     make ndp.NdpReplyGenTest
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


@group("ndp")
class NdpReplyGenTest(P4RuntimeTest):
    """Tests automatic generation of NDP Neighbor Advertisement for IPV6
    addresses associated to the switch interface.
    """

    @autocleanup
    def runTest(self):
        switch_ip = SWITCH1_IPV6
        target_mac = SWITCH1_MAC

        # Insert entry to transform NDP NA packets for the given target IPv6
        # address (match), to NDP NA packets with the given target MAC address
        # (action)

        # *** TODO EXERCISE 4
        # Fill in the name of the NDP reply table you created in the P4 program.
        # Hint: look at the P4Info file to get the fully-qualified name of the
        # table.
        # ---- START SOLUTION ----
        self.insert(self.helper.build_table_entry(
            table_name="<PUT HERE NAME OF NDP REPLY TABLE FROM P4INFO>",
            match_fields={
                # Exact match.
                "hdr.ndp.target_ipv6_addr": switch_ip
            },
            action_name="IngressPipeImpl.ndp_ns_to_na",
            action_params={
                "target_mac": target_mac
            }
        ))
        # ---- END SOLUTION ----

        # NDP Neighbor Solicitation packet
        pkt = genNdpNsPkt(target_ip=switch_ip)

        # Expected NDP Neighbor Advertisement packet
        exp_pkt = genNdpNaPkt(target_ip=switch_ip,
                              target_mac=target_mac,
                              src_mac=target_mac,
                              src_ip=switch_ip,
                              dst_ip=pkt[IPv6].src)

        # Send NDP NS, expect NDP NA from the same port.
        testutils.send_packet(self, self.port1, str(pkt))
        testutils.verify_packet(self, exp_pkt, self.port1)
