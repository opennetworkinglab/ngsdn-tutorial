/*
 * Copyright 2019-present Open Networking Foundation
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include <core.p4>
#include <v1model.p4>

#define CPU_PORT 255
#define CPU_CLONE_SESSION_ID 99

typedef bit<9>   port_num_t;
typedef bit<48>  mac_addr_t;
typedef bit<16>  group_id_t;
typedef bit<32>  ipv4_addr_t;
typedef bit<128> ipv6_addr_t;
typedef bit<16>  l4_port_t;

const bit<16> ETHERTYPE_IPV4 = 0x0800;
const bit<16> ETHERTYPE_IPV6 = 0x86dd;
const bit<16> ETHERTYPE_ARP  = 0x0806;

const bit<8> PROTO_ICMP = 1;
const bit<8> PROTO_TCP = 6;
const bit<8> PROTO_UDP = 17;
const bit<8> PROTO_SRV6 = 43;
const bit<8> PROTO_ICMPV6 = 58;

const bit<8> ICMP6_TYPE_NS = 135;
const bit<8> ICMP6_TYPE_NA = 136;
const bit<8> NDP_OPT_TARGET_LL_ADDR = 2;
const mac_addr_t IPV6_MCAST_01 = 0x33_33_00_00_00_01;
const bit<32> NDP_FLAG_ROUTER = 0x80000000;
const bit<32> NDP_FLAG_SOLICITED = 0x40000000;
const bit<32> NDP_FLAG_OVERRIDE = 0x20000000;

@controller_header("packet_in")
header packet_in_t {
    port_num_t  ingress_port;
    bit<7>      _pad;
}

@controller_header("packet_out")
header packet_out_t {
    port_num_t  egress_port;
    bit<7>      _pad;
}

header ethernet_t {
    mac_addr_t  dst_addr;
    mac_addr_t  src_addr;
    bit<16>     ether_type;
}

header ipv4_t {
    bit<4>   version;
    bit<4>   ihl;
    bit<6>   dscp;
    bit<2>   ecn;
    bit<16>  total_len;
    bit<16>  identification;
    bit<3>   flags;
    bit<13>  frag_offset;
    bit<8>   ttl;
    bit<8>   protocol;
    bit<16>  hdr_checksum;
    bit<32>  src_addr;
    bit<32>  dst_addr;
}

header ipv6_t {
    bit<4>   version;
    bit<8>   traffic_class;
    bit<20>  flow_label;
    bit<16>  payload_len;
    bit<8>   next_hdr;
    bit<8>   hop_limit;
    bit<128> src_addr;
    bit<128> dst_addr;
}

header arp_t {
    bit<16>  hw_type;
    bit<16>  proto_type;
    bit<8>   hw_addr_len;
    bit<8>   proto_addr_len;
    bit<16>  opcode;
}

header tcp_t {
    bit<16>  src_port;
    bit<16>  dst_port;
    bit<32>  seq_no;
    bit<32>  ack_no;
    bit<4>   data_offset;
    bit<3>   res;
    bit<3>   ecn;
    bit<6>   ctrl;
    bit<16>  window;
    bit<16>  checksum;
    bit<16>  urgent_ptr;
}

header udp_t {
    bit<16> src_port;
    bit<16> dst_port;
    bit<16> len;
    bit<16> checksum;
}

header icmp_t {
    bit<8>   type;
    bit<8>   icmp_code;
    bit<16>  checksum;
    bit<16>  identifier;
    bit<16>  sequence_number;
    bit<64>  timestamp;
}

header icmpv6_t {
    bit<8>   type;
    bit<8>   code;
    bit<16>  checksum;
}

header ndp_t {
    bit<32>   flags;
    bit<128>  target_addr;
}

header ndp_option_t {
    bit<8>   type;
    bit<8>   length;
    bit<48>  value;
}

// Custom metadata definition
struct local_metadata_t {
    bool       is_multicast;
    bool       skip_l2;
    bit<8>     ip_proto;
    bit<8>     icmp_type;
    l4_port_t  l4_src_port;
    l4_port_t  l4_dst_port;
}

struct parsed_headers_t {
    ethernet_t    ethernet;
    ipv4_t        ipv4;
    ipv6_t        ipv6;
    arp_t         arp;
    tcp_t         tcp;
    udp_t         udp;
    icmp_t        icmp;
    icmpv6_t      icmpv6;
    ndp_t         ndp;
    ndp_option_t  ndp_option;
    packet_out_t  packet_out;
    packet_in_t   packet_in;
}

parser ParserImpl (packet_in packet,
                   out parsed_headers_t hdr,
                   inout local_metadata_t local_metadata,
                   inout standard_metadata_t standard_metadata)
{
    state start {
        transition select(standard_metadata.ingress_port) {
            CPU_PORT: parse_packet_out;
            default: parse_ethernet;
        }
    }

    state parse_packet_out {
        packet.extract(hdr.packet_out);
        transition parse_ethernet;
    }

    state parse_ethernet {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.ether_type){
            ETHERTYPE_ARP:  parse_arp;
            ETHERTYPE_IPV4: parse_ipv4;
            ETHERTYPE_IPV6: parse_ipv6;
            default: accept;
        }
    }

    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        local_metadata.ip_proto = hdr.ipv4.protocol;
        transition select(hdr.ipv4.protocol) {
            PROTO_TCP:  parse_tcp;
            PROTO_UDP:  parse_udp;
            PROTO_ICMP: parse_icmp;
            default: accept;
        }
    }

    state parse_ipv6 {
        packet.extract(hdr.ipv6);
        local_metadata.ip_proto = hdr.ipv6.next_hdr;
        transition select(hdr.ipv6.next_hdr) {
            PROTO_TCP:    parse_tcp;
            PROTO_UDP:    parse_udp;
            PROTO_ICMPV6: parse_icmpv6;
            default: accept;
        }
    }

    state parse_arp {
        packet.extract(hdr.arp);
        transition accept;
    }

    state parse_tcp {
        packet.extract(hdr.tcp);
        local_metadata.l4_src_port = hdr.tcp.src_port;
        local_metadata.l4_dst_port = hdr.tcp.dst_port;
        transition accept;
    }

    state parse_udp {
        packet.extract(hdr.udp);
        local_metadata.l4_src_port = hdr.udp.src_port;
        local_metadata.l4_dst_port = hdr.udp.dst_port;
        transition accept;
    }

    state parse_icmp {
        packet.extract(hdr.icmp);
        local_metadata.icmp_type = hdr.icmp.type;
        transition accept;
    }

    state parse_icmpv6 {
        packet.extract(hdr.icmpv6);
        local_metadata.icmp_type = hdr.icmpv6.type;
        transition select(hdr.icmpv6.type) {
            ICMP6_TYPE_NS: parse_ndp;
            ICMP6_TYPE_NA: parse_ndp;
            default: accept;
        }
    }

    state parse_ndp {
        packet.extract(hdr.ndp);
        transition parse_ndp_option;
    }

    state parse_ndp_option {
        packet.extract(hdr.ndp_option);
        transition accept;
    }
}

control DeparserImpl(packet_out packet, in parsed_headers_t hdr) {
    apply {
        packet.emit(hdr.packet_in);
        packet.emit(hdr.ethernet);
        packet.emit(hdr.arp);
        packet.emit(hdr.ipv4);
        packet.emit(hdr.ipv6);
        packet.emit(hdr.tcp);
        packet.emit(hdr.udp);
        packet.emit(hdr.icmp);
        packet.emit(hdr.icmpv6);
        packet.emit(hdr.ndp);
        packet.emit(hdr.ndp_option);
    }
}

control IngressPipeImpl (inout parsed_headers_t hdr,
                         inout local_metadata_t local_metadata,
                         inout standard_metadata_t standard_metadata) {

    action drop() {
        mark_to_drop(standard_metadata);
    }

    /*
     * NDP reply table and actions.
     * Handles NDP router solicitation message and send router advertisement to the sender.
     */
    action ndp_ns_to_na(mac_addr_t target_mac) {
        hdr.ethernet.src_addr = target_mac;
        hdr.ethernet.dst_addr = IPV6_MCAST_01;
        ipv6_addr_t host_ipv6_tmp = hdr.ipv6.src_addr;
        hdr.ipv6.src_addr = hdr.ndp.target_addr;
        hdr.ipv6.dst_addr = host_ipv6_tmp;
        hdr.icmpv6.type = ICMP6_TYPE_NA;
        hdr.ndp.flags = NDP_FLAG_ROUTER | NDP_FLAG_OVERRIDE;
        hdr.ndp_option.setValid();
        hdr.ndp_option.type = NDP_OPT_TARGET_LL_ADDR;
        hdr.ndp_option.length = 1;
        hdr.ndp_option.value = target_mac;
        hdr.ipv6.next_hdr = PROTO_ICMPV6;
        standard_metadata.egress_spec = standard_metadata.ingress_port;
        local_metadata.skip_l2 = true;
    }

    direct_counter(CounterType.packets_and_bytes) ndp_reply_table_counter;
    table ndp_reply_table {
        key = {
            hdr.ndp.target_addr: exact;
        }
        actions = {
            ndp_ns_to_na;
        }
        counters = ndp_reply_table_counter;
    }

    /*
     * L2 exact table.
     * Matches the destination Ethernet address and set output port or do nothing.
     */

    action set_output_port(port_num_t port_num) {
        standard_metadata.egress_spec = port_num;
    }

    direct_counter(CounterType.packets_and_bytes) l2_exact_table_counter;
    table l2_exact_table {
        key = {
            hdr.ethernet.dst_addr: exact;
        }
        actions = {
            set_output_port;
            @defaultonly NoAction;
        }
        const default_action = NoAction;
        counters = l2_exact_table_counter;
    }

    /*
     * L2 ternary table.
     * Handles broadcast address (FF:FF:FF:FF:FF:FF) and multicast address (33:33:*:*:*:*) and set multicast
     * group id for the packet.
     */
    action set_multicast_group(group_id_t gid) {
        standard_metadata.mcast_grp = gid;
        local_metadata.is_multicast = true;
    }

    direct_counter(CounterType.packets_and_bytes) l2_ternary_table_counter;
    table l2_ternary_table {
        key = {
            hdr.ethernet.dst_addr: ternary;
        }
        actions = {
            set_multicast_group;
            drop;
        }
        const default_action = drop;
        counters = l2_ternary_table_counter;
    }

    /*
     * L2 my station table.
     * Hit when Ethernet destination address is the device address.
     * This table won't do anything to the packet, but the pipeline will use the result (table.hit)
     * to decide how to process the packet.
     */
    direct_counter(CounterType.packets_and_bytes) l2_my_station_table_counter;
    table l2_my_station {
        key = {
            hdr.ethernet.dst_addr: exact;
        }
        actions = {
            NoAction;
        }
        counters = l2_my_station_table_counter;
    }

    /*
     * L3 table.
     * Handles IPv6 routing. Pickup a next hop address according to hash of packet header fields (5-tuple).
     */
    action set_l2_next_hop(mac_addr_t dmac) {
        hdr.ethernet.src_addr = hdr.ethernet.dst_addr;
        hdr.ethernet.dst_addr = dmac;
        hdr.ipv6.hop_limit = hdr.ipv6.hop_limit - 1;
    }

    action_selector(HashAlgorithm.crc16, 32w64, 32w16) ecmp_selector;
    direct_counter(CounterType.packets_and_bytes) l3_table_counter;
    table l3_table {
      key = {
          hdr.ipv6.dst_addr:          lpm;
          // The following fields are not used for matching, but as input to the
          // ecmp_selector hash function.
          hdr.ipv6.dst_addr:          selector;
          hdr.ipv6.src_addr:          selector;
          hdr.ipv6.flow_label:        selector;
          // the rest of the 5-tuple is optional per RFC6438
          local_metadata.ip_proto:    selector;
          local_metadata.l4_src_port: selector;
          local_metadata.l4_dst_port: selector;
      }
      actions = {
          set_l2_next_hop;
      }
      implementation = ecmp_selector;
      counters = l3_table_counter;
    }

    /*
     * ACL table.
     * Clone the packet to the CPU (PacketIn) or drop the packet.
     */
    action clone_to_cpu() {
        clone3(CloneType.I2E, CPU_CLONE_SESSION_ID, standard_metadata);
    }

    direct_counter(CounterType.packets_and_bytes) acl_counter;
    table acl {
        key = {
            standard_metadata.ingress_port: ternary;
            hdr.ethernet.dst_addr: ternary;
            hdr.ethernet.src_addr: ternary;
            hdr.ethernet.ether_type: ternary;
            local_metadata.ip_proto: ternary;
            local_metadata.icmp_type: ternary;
            local_metadata.l4_src_port: ternary;
            local_metadata.l4_dst_port: ternary;
        }
        actions = {
            clone_to_cpu;
            drop;
        }
        counters = acl_counter;
    }

    apply {
        if (hdr.packet_out.isValid()) {
            standard_metadata.egress_spec = hdr.packet_out.egress_port;
            hdr.packet_out.setInvalid();
            exit;
        }

        if (hdr.icmpv6.isValid() && hdr.icmpv6.type == ICMP6_TYPE_NS) {
            ndp_reply_table.apply();
        }

        if (l2_my_station.apply().hit && hdr.ipv6.isValid()) {
            l3_table.apply();
            if(hdr.ipv6.hop_limit == 0) {
                drop();
            }
        }

        if (!local_metadata.skip_l2 && standard_metadata.drop != 1w1) {
            if (!l2_exact_table.apply().hit) {
                l2_ternary_table.apply();
            }
        }

        acl.apply();
    }
}

control EgressPipeImpl (inout parsed_headers_t hdr,
                        inout local_metadata_t local_metadata,
                        inout standard_metadata_t standard_metadata) {
    apply {
        // TODO EXERCISE 1
        // Implement logic such that if the packet is to be forwarded to the CPU
        // port, i.e. we requested a packet-in in the ingress pipeline
        // (standard_metadata.egress_port == CPU_PORT):
        // 1. Set packet_in header as valid
        // 2. Set the packet_in.ingress_port field to the original packet's
        //    ingress port (standard_metadata.ingress_port).
        // ---- START SOLUTION ----
        if (standard_metadata.egress_port == CPU_PORT) {
            hdr.packet_in.setValid();
            hdr.packet_in.ingress_port = standard_metadata.ingress_port;
        }
        // ---- END SOLUTION ----

        // Perform ingress port pruning for multicast packets. E.g., do not
        // broadcast ARP requests onthe ingress port.
        if (local_metadata.is_multicast == true &&
              standard_metadata.ingress_port == standard_metadata.egress_port) {
            mark_to_drop(standard_metadata);
        }
    }
}

control ComputeChecksumImpl(inout parsed_headers_t hdr,
                            inout local_metadata_t meta)
{
    apply {
        update_checksum(hdr.ndp.isValid(),
            {
                hdr.ipv6.src_addr,
                hdr.ipv6.dst_addr,
                hdr.ipv6.payload_len,
                8w0,
                hdr.ipv6.next_hdr,
                hdr.icmpv6.type,
                hdr.icmpv6.code,
                hdr.ndp.flags,
                hdr.ndp.target_addr,
                hdr.ndp_option.type,
                hdr.ndp_option.length,
                hdr.ndp_option.value
            },
            hdr.icmpv6.checksum,
            HashAlgorithm.csum16
        );
    }
}

control VerifyChecksumImpl(inout parsed_headers_t hdr,
                           inout local_metadata_t meta)
{
    apply {}
}

V1Switch(
    ParserImpl(),
    VerifyChecksumImpl(),
    IngressPipeImpl(),
    EgressPipeImpl(),
    ComputeChecksumImpl(),
    DeparserImpl()
) main;
