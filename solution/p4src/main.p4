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

// CPU_PORT specifies the P4 port number associated to controller packet-in and
// packet-out. All packets forwarded via this port will be delivered to the
// controller as P4Runtime PacketIn messages. Similarly, PacketOut messages from
// the controller will be seen by the P4 pipeline as coming from the CPU_PORT.
#define CPU_PORT 255

// CPU_CLONE_SESSION_ID specifies the mirroring session for packets to be cloned
// to the CPU port. Packets associated with this session ID will be cloned to
// the CPU_PORT as well as being transmitted via their egress port (set by the
// bridging/routing/acl table). For cloning to work, the P4Runtime controller
// needs first to insert a CloneSessionEntry that maps this session ID to the
// CPU_PORT.
#define CPU_CLONE_SESSION_ID 99

// Maximum number of hops supported when using SRv6.
// Required for Exercise 7.
#define SRV6_MAX_HOPS 4

typedef bit<9>   port_num_t;
typedef bit<48>  mac_addr_t;
typedef bit<16>  mcast_group_id_t;
typedef bit<32>  ipv4_addr_t;
typedef bit<128> ipv6_addr_t;
typedef bit<16>  l4_port_t;

const bit<16> ETHERTYPE_IPV4 = 0x0800;
const bit<16> ETHERTYPE_IPV6 = 0x86dd;

const bit<8> IP_PROTO_ICMP   = 1;
const bit<8> IP_PROTO_TCP    = 6;
const bit<8> IP_PROTO_UDP    = 17;
const bit<8> IP_PROTO_SRV6   = 43;
const bit<8> IP_PROTO_ICMPV6 = 58;

const mac_addr_t IPV6_MCAST_01 = 0x33_33_00_00_00_01;

const bit<8> ICMP6_TYPE_NS = 135;
const bit<8> ICMP6_TYPE_NA = 136;

const bit<8> NDP_OPT_TARGET_LL_ADDR = 2;

const bit<32> NDP_FLAG_ROUTER    = 0x80000000;
const bit<32> NDP_FLAG_SOLICITED = 0x40000000;
const bit<32> NDP_FLAG_OVERRIDE  = 0x20000000;


//------------------------------------------------------------------------------
// HEADER DEFINITIONS
//------------------------------------------------------------------------------

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
    bit<4>    version;
    bit<8>    traffic_class;
    bit<20>   flow_label;
    bit<16>   payload_len;
    bit<8>    next_hdr;
    bit<8>    hop_limit;
    bit<128>  src_addr;
    bit<128>  dst_addr;
}

header srv6h_t {
    bit<8>   next_hdr;
    bit<8>   hdr_ext_len;
    bit<8>   routing_type;
    bit<8>   segment_left;
    bit<8>   last_entry;
    bit<8>   flags;
    bit<16>  tag;
}

header srv6_list_t {
    bit<128>  segment_id;
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
    bit<32>      flags;
    ipv6_addr_t  target_ipv6_addr;
    // NDP option.
    bit<8>       type;
    bit<8>       length;
    bit<48>      target_mac_addr;
}

// Packet-in header. Prepended to packets sent to the CPU_PORT and used by the
// P4Runtime server (Stratum) to populate the PacketIn message metadata fields.
// Here we use it to carry the original ingress port where the packet was
// received.
@controller_header("packet_in")
header cpu_in_header_t {
    port_num_t  ingress_port;
    bit<7>      _pad;
}

// Packet-out header. Prepended to packets received from the CPU_PORT. Fields of
// this header are populated by the P4Runtime server based on the P4Runtime
// PacketOut metadata fields. Here we use it to inform the P4 pipeline on which
// port this packet-out should be transmitted.
@controller_header("packet_out")
header cpu_out_header_t {
    port_num_t  egress_port;
    bit<7>      _pad;
}

struct parsed_headers_t {
    cpu_out_header_t cpu_out;
    cpu_in_header_t cpu_in;
    ethernet_t ethernet;
    ipv4_t ipv4;
    ipv6_t ipv6;
    srv6h_t srv6h;
    srv6_list_t[SRV6_MAX_HOPS] srv6_list;
    tcp_t tcp;
    udp_t udp;
    icmp_t icmp;
    icmpv6_t icmpv6;
    ndp_t ndp;
}

struct local_metadata_t {
    l4_port_t   l4_src_port;
    l4_port_t   l4_dst_port;
    bool        is_multicast;
    ipv6_addr_t next_srv6_sid;
    bit<8>      ip_proto;
    bit<8>      icmp_type;
}


//------------------------------------------------------------------------------
// INGRESS PIPELINE
//------------------------------------------------------------------------------

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
        packet.extract(hdr.cpu_out);
        transition parse_ethernet;
    }

    state parse_ethernet {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.ether_type){
            ETHERTYPE_IPV4: parse_ipv4;
            ETHERTYPE_IPV6: parse_ipv6;
            default: accept;
        }
    }

    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        local_metadata.ip_proto = hdr.ipv4.protocol;
        transition select(hdr.ipv4.protocol) {
            IP_PROTO_TCP: parse_tcp;
            IP_PROTO_UDP: parse_udp;
            IP_PROTO_ICMP: parse_icmp;
            default: accept;
        }
    }

    state parse_ipv6 {
        packet.extract(hdr.ipv6);
        local_metadata.ip_proto = hdr.ipv6.next_hdr;
        transition select(hdr.ipv6.next_hdr) {
            IP_PROTO_TCP: parse_tcp;
            IP_PROTO_UDP: parse_udp;
            IP_PROTO_ICMPV6: parse_icmpv6;
            IP_PROTO_SRV6: parse_srv6;
            default: accept;
        }
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
        transition accept;
    }

    state parse_srv6 {
        packet.extract(hdr.srv6h);
        transition parse_srv6_list;
    }

    state parse_srv6_list {
        packet.extract(hdr.srv6_list.next);
        bool next_segment = (bit<32>)hdr.srv6h.segment_left - 1 == (bit<32>)hdr.srv6_list.lastIndex;
        transition select(next_segment) {
            true: mark_current_srv6;
            default: check_last_srv6;
        }
    }

    state mark_current_srv6 {
        local_metadata.next_srv6_sid = hdr.srv6_list.last.segment_id;
        transition check_last_srv6;
    }

    state check_last_srv6 {
        // working with bit<8> and int<32> which cannot be cast directly; using
        // bit<32> as common intermediate type for comparision
        bool last_segment = (bit<32>)hdr.srv6h.last_entry == (bit<32>)hdr.srv6_list.lastIndex;
        transition select(last_segment) {
           true: parse_srv6_next_hdr;
           false: parse_srv6_list;
        }
    }

    state parse_srv6_next_hdr {
        transition select(hdr.srv6h.next_hdr) {
            IP_PROTO_TCP: parse_tcp;
            IP_PROTO_UDP: parse_udp;
            IP_PROTO_ICMPV6: parse_icmpv6;
            default: accept;
        }
    }
}


control VerifyChecksumImpl(inout parsed_headers_t hdr,
                           inout local_metadata_t meta)
{
    // Not used here. We assume all packets have valid checksum, if not, we let
    // the end hosts detect errors.
    apply { /* EMPTY */ }
}


control IngressPipeImpl (inout parsed_headers_t    hdr,
                         inout local_metadata_t    local_metadata,
                         inout standard_metadata_t standard_metadata) {

    // Drop action shared by many tables.
    action drop() {
        mark_to_drop(standard_metadata);
    }

    // *** L2 BRIDGING
    //
    // Here we define tables to forward packets based on their Ethernet
    // destination address. There are two types of L2 entries that we
    // need to support:
    //
    // 1. Unicast entries: which will be filled in by the control plane when the
    //    location (port) of new hosts is learned.
    // 2. Broadcast/multicast entries: used replicate NDP Neighbor Solicitation
    //    (NS) messages to all host-facing ports;
    //
    // For (2), unlike ARP messages in IPv4 which are broadcasted to Ethernet
    // destination address FF:FF:FF:FF:FF:FF, NDP messages are sent to special
    // Ethernet addresses specified by RFC2464. These addresses are prefixed
    // with 33:33 and the last four octets are the last four octets of the IPv6
    // destination multicast address. The most straightforward way of matching
    // on such IPv6 broadcast/multicast packets, without digging in the details
    // of RFC2464, is to use a ternary match on 33:33:**:**:**:**, where * means
    // "don't care".
    //
    // For this reason, our solution defines two tables. One that matches in an
    // exact fashion (easier to scale on switch ASIC memory) and one that uses
    // ternary matching (which requires more expensive TCAM memories, usually
    // much smaller).

    /*
     * TODO EXERCISE 2
     * Create L2 table(s). Our solution uses two tables: one for unicast and one for broadcast/multicast.
     * We have already provided both the unicast (set_output_port) and multicast (set_multicast_group)
     * actions for you to use.
     * If you choose to use two tables, what should the default actions be for each table?
     * You should add a direct counter to the table if you would like to see flow stats in ONOS.
     * Matches the destination Ethernet address and set output port or do nothing.
     */

    // --- l2_exact_table (for unicast entries) --------------------------------

    action set_egress_port(port_num_t port_num) {
        standard_metadata.egress_spec = port_num;
    }

    table l2_exact_table {
        key = {
            hdr.ethernet.dst_addr: exact;
        }
        actions = {
            set_egress_port;
            @defaultonly drop;
        }
        const default_action = drop;
        // The @name annotation is used here to provide a name to this table
        // counter, as it will be needed by the compiler to generate the
        // corresponding P4Info entity.
        @name("l2_exact_table_counter")
        counters = direct_counter(CounterType.packets_and_bytes);
    }

    // --- l2_ternary_table (for broadcast/multicast entries) ------------------

    action set_multicast_group(mcast_group_id_t gid) {
        // gid will be used by the Packet Replication Engine (PRE) in the
        // Traffic Manager--located right after the ingress pipeline, to
        // replicate a packet to multiple egress ports, specified by the control
        // plane by means of P4Runtime MulticastGroupEntry messages.
        standard_metadata.mcast_grp = gid;
        local_metadata.is_multicast = true;
    }

    table l2_ternary_table {
        key = {
            hdr.ethernet.dst_addr: ternary;
        }
        actions = {
            set_multicast_group;
            @defaultonly drop;
        }
        const default_action = drop;
        @name("l2_ternary_table_counter")
        counters = direct_counter(CounterType.packets_and_bytes);
    }

    // *** L3 ROUTING
    //
    // Here we define tables to route packets based on their IPv6 destination
    // address. We assume the following:
    //
    // * Not all packets need to be routed, but only those that have destination
    //   MAC address the "router MAC" addres, which we call "my_station" MAC.
    //   Such address is defined at runtime by the control plane.
    // * If a packet matches a routing entry, it should be forwarded to a
    //   given next hop and the packet's Ethernet addresses should be modified
    //   accordingly (source set to my_station MAC and destination to the next
    //   hop one);
    // * When routing packets to a different leaf across the spines, leaf
    //   switches should be able to use ECMP to distribute traffic via multiple
    //   links.

    // --- my_station_table ----------------------------------------------------

    // Matches on all possible my_station MAC addresses associated with this
    // switch. This table defines only one action that does nothing to the
    // packet. Later in the apply block, we define logic such that packets are
    // routed if and only if this table is "hit", i.e. a matching entry is found
    // for the given packet.

    table my_station_table {
        key = {
            hdr.ethernet.dst_addr: exact;
        }
        actions = { NoAction; }
        @name("my_station_table_counter")
        counters = direct_counter(CounterType.packets_and_bytes);
    }

    // --- routing_v6_table ----------------------------------------------------

    // To implement ECMP, we use Action Selectors, a v1model-specific construct.
    // A P4Runtime controller, can use action selectors to associate a group of
    // actions to one table entry. The speficic action in the group will be
    // selected by perfoming a hash function over a pre-determined set of header
    // fields. Here we instantiate an action selector named "ecmp_selector" that
    // uses crc16 as the hash function, can hold up to 1024 entries (distinct
    // action specifications), and produces a selector key of size 16 bits.

    action_selector(HashAlgorithm.crc16, 32w1024, 32w16) ecmp_selector;

    action set_next_hop(mac_addr_t dmac) {
        hdr.ethernet.src_addr = hdr.ethernet.dst_addr;
        hdr.ethernet.dst_addr = dmac;
        // Decrement TTL
        hdr.ipv6.hop_limit = hdr.ipv6.hop_limit - 1;
    }

    // Look for the "implementation" property in the table definition.
    table routing_v6_table {
      key = {
          hdr.ipv6.dst_addr:          lpm;
          // The following fields are not used for matching, but as input to the
          // ecmp_selector hash function.
          hdr.ipv6.dst_addr:          selector;
          hdr.ipv6.src_addr:          selector;
          hdr.ipv6.flow_label:        selector;
          // The rest of the 5-tuple is optional per RFC6438
          hdr.ipv6.next_hdr:          selector;
          local_metadata.l4_src_port: selector;
          local_metadata.l4_dst_port: selector;
      }
      actions = {
          set_next_hop;
      }
      implementation = ecmp_selector;
      @name("routing_v6_table_counter")
      counters = direct_counter(CounterType.packets_and_bytes);
    }

    // *** SRV6
    /*
     * SRv6 my sid table.
     * Process the packet if the destination IP is the segemnt Id(sid) of this device.
     * This table will decrement the "segment left" field from the Srv6 header and set destination
     * IP address to next segment.
     */
    action srv6_end() {
        hdr.srv6h.segment_left = hdr.srv6h.segment_left - 1;
        hdr.ipv6.dst_addr = local_metadata.next_srv6_sid;
    }

    direct_counter(CounterType.packets_and_bytes) srv6_my_sid_table_counter;
    table srv6_my_sid {
      key = {
          hdr.ipv6.dst_addr: lpm;
      }
      actions = {
          srv6_end;
      }
      counters = srv6_my_sid_table_counter;
    }

    /*
     * SRv6 transit table.
     * Inserts the SRv6 header to the IPv6 header of the packet based on the destination IP address.
     */
    action insert_srv6h_header(bit<8> num_segments) {
        hdr.srv6h.setValid();
        hdr.srv6h.next_hdr = hdr.ipv6.next_hdr;
        hdr.srv6h.hdr_ext_len =  num_segments * 2;
        hdr.srv6h.routing_type = 4;
        hdr.srv6h.segment_left = num_segments - 1;
        hdr.srv6h.last_entry = num_segments - 1;
        hdr.srv6h.flags = 0;
        hdr.srv6h.tag = 0;
        hdr.ipv6.next_hdr = IP_PROTO_SRV6;
    }

    /*
       Single segment header doesn't make sense given PSP
       i.e. we will pop the SRv6 header when segments_left reaches 0
     */

    action srv6_t_insert_2(ipv6_addr_t s1, ipv6_addr_t s2) {
        hdr.ipv6.dst_addr = s1;
        hdr.ipv6.payload_len = hdr.ipv6.payload_len + 40;
        insert_srv6h_header(2);
        hdr.srv6_list[0].setValid();
        hdr.srv6_list[0].segment_id = s2;
        hdr.srv6_list[1].setValid();
        hdr.srv6_list[1].segment_id = s1;
    }

    action srv6_t_insert_3(ipv6_addr_t s1, ipv6_addr_t s2, ipv6_addr_t s3) {
        hdr.ipv6.dst_addr = s1;
        hdr.ipv6.payload_len = hdr.ipv6.payload_len + 56;
        insert_srv6h_header(3);
        hdr.srv6_list[0].setValid();
        hdr.srv6_list[0].segment_id = s3;
        hdr.srv6_list[1].setValid();
        hdr.srv6_list[1].segment_id = s2;
        hdr.srv6_list[2].setValid();
        hdr.srv6_list[2].segment_id = s1;
    }

    direct_counter(CounterType.packets_and_bytes) srv6_transit_table_counter;
    table srv6_transit {
      key = {
          hdr.ipv6.dst_addr: lpm;
          // TODO: what other fields do we want to match?
      }
      actions = {
          srv6_t_insert_2;
          srv6_t_insert_3;
          // Extra credit: set a metadata field, then push label stack in egress
      }
      counters = srv6_transit_table_counter;
    }

    action srv6_pop() {
      hdr.ipv6.next_hdr = hdr.srv6h.next_hdr;
      // SRv6 header is 8 bytes
      // SRv6 list entry is 16 bytes each
      // (((bit<16>)hdr.srv6h.last_entry + 1) * 16) + 8;
      bit<16> srv6h_size = (((bit<16>)hdr.srv6h.last_entry + 1) << 4) + 8;
      hdr.ipv6.payload_len = hdr.ipv6.payload_len - srv6h_size;

      hdr.srv6h.setInvalid();
      // Need to set MAX_HOPS headers invalid
      hdr.srv6_list[0].setInvalid();
      hdr.srv6_list[1].setInvalid();
      hdr.srv6_list[2].setInvalid();
    }

    // *** ACL
    //
    // Provides ways to override a previous forwarding decision, for example
    // requiring that a packet is cloned/sent to the CPU, or dropped.
    //
    // We use this table to clone all NDP packets to the control plane, so to
    // enable host discovery. When the location of a new host is discovered, the
    // controller is expected to update the L2 and L3 tables with the
    // correspionding brinding and routing entries.

    // --- acl_table -----------------------------------------------------------

    action send_to_cpu() {
        standard_metadata.egress_spec = CPU_PORT;
    }

    action clone_to_cpu() {
        // Cloning is achieved by using a v1model-specific primitive. Here we
        // set the type of clone operation (ingress-to-egress pipeline), the
        // clone session ID (the CPU one), and the metadata fields we want to
        // preserve for the cloned packet replica.
        clone3(CloneType.I2E, CPU_CLONE_SESSION_ID, { standard_metadata.ingress_port });
    }

    table acl_table {
        key = {
            standard_metadata.ingress_port: ternary;
            hdr.ethernet.dst_addr:          ternary;
            hdr.ethernet.src_addr:          ternary;
            hdr.ethernet.ether_type:        ternary;
            local_metadata.ip_proto:        ternary;
            local_metadata.icmp_type:       ternary;
            local_metadata.l4_src_port:     ternary;
            local_metadata.l4_dst_port:     ternary;
        }
        actions = {
            send_to_cpu;
            clone_to_cpu;
            drop;
        }
        @name("acl_table_counter")
        counters = direct_counter(CounterType.packets_and_bytes);
    }

    // *** NDP HANDLING
    //
    // NDP Handling will be the focus of exercise 4. If you are still working on
    // a previous exercise, it's OK if you ignore this part for now.

    // Action that transforms an NDP NS packet into an NDP NA one for the given
    // target MAC address. The action also sets the egress port to the ingress
    // one where the NDP NS packet was received.

    action ndp_ns_to_na(mac_addr_t target_mac) {
        hdr.ethernet.src_addr = target_mac;
        hdr.ethernet.dst_addr = IPV6_MCAST_01;
        ipv6_addr_t host_ipv6_tmp = hdr.ipv6.src_addr;
        hdr.ipv6.src_addr = hdr.ndp.target_ipv6_addr;
        hdr.ipv6.dst_addr = host_ipv6_tmp;
        hdr.ipv6.next_hdr = IP_PROTO_ICMPV6;
        hdr.icmpv6.type = ICMP6_TYPE_NA;
        hdr.ndp.flags = NDP_FLAG_ROUTER | NDP_FLAG_OVERRIDE;
        hdr.ndp.type = NDP_OPT_TARGET_LL_ADDR;
        hdr.ndp.length = 1;
        hdr.ndp.target_mac_addr = target_mac;
        standard_metadata.egress_spec = standard_metadata.ingress_port;
    }

    // *** TODO EXERCISE 4
    // Create a table to handle NDP NS packets for the switch IPv6 interface
    // addresses. This table should:
    //   * match on hdr.ndp.target_ipv6_addr (exact match)
    //   * provide action "ndp_ns_to_na" defined before
    //   * default_action should be "NoAction"
    //
    // You can name your table whatever you like, and you will need to fill
    // the name in elsewhere in this exercise.
    //
    // This table should have structure similar to l2_exact_table defined
    // before. Feel free to copy paste that table definition here as a starter.
    // ---- START SOLUTION ----

    table ndp_reply_table {
        key = {
            hdr.ndp.target_ipv6_addr: exact;
        }
        actions = {
            ndp_ns_to_na;
        }
        @name("ndp_reply_table_counter")
        counters = direct_counter(CounterType.packets_and_bytes);
    }

    // ---- END SOLUTION ----

    apply {

        // If this is a packet-out from the controller...
        if (hdr.cpu_out.isValid()) {
            // Set the egress port to that found in the packet-out metadata...
            standard_metadata.egress_spec = hdr.cpu_out.egress_port;
            // Remove the packet-out header...
            hdr.cpu_out.setInvalid();
            // Exit the pipeline here, no need to go through other tables.
            exit;
        }

        bool do_l3_l2 = true;

        // *** TODO EXERCISE 4
        // Fill in the name of the NDP reply table created before
        // ---- START SOLUTION ----
        // If this is an NDP NS packet, attempt to generate a reply using the
        // ndp_reply_table. If a matching entry is found, unset the "do_l3_l2"
        // flag to skip the L3 and L2 tables, as the "ndp_ns_to_na" action
        // already set an egress port.

        if (hdr.icmpv6.isValid() && hdr.icmpv6.type == ICMP6_TYPE_NS) {
            if (ndp_reply_table.apply().hit) {
                do_l3_l2 = false;
            }
        }

        // ---- END SOLUTION ----

        if (do_l3_l2) {

            // Apply the L3 routing table to IPv6 packets, only if the
            // destination MAC is found in the my_station_table.
            if (hdr.ipv6.isValid() && my_station_table.apply().hit) {
                if (srv6_my_sid.apply().hit) {
                    // PSP logic -- enabled for all packets
                    if (hdr.srv6h.isValid() && hdr.srv6h.segment_left == 0) {
                        srv6_pop();
                    }
                } else {
                    srv6_transit.apply();
                }
                routing_v6_table.apply();
                // Checl TTL, drop packet if necessary to avoid loops.
                if(hdr.ipv6.hop_limit == 0) { drop(); }
            }

            // L2 bridging. Apply the exact table first (for unicast entries)..
            if (!l2_exact_table.apply().hit) {
                // If an entry is NOT found, apply the ternary one in case this
                // is a multicast/broadcast NDP NS packet for another host
                // attached to this switch.
                l2_ternary_table.apply();
            }
        }

        // Lastly, apply the ACL table.
        acl_table.apply();
    }
}


control EgressPipeImpl (inout parsed_headers_t hdr,
                        inout local_metadata_t local_metadata,
                        inout standard_metadata_t standard_metadata) {
    apply {
        // If this is a packet-in to the controller, e.g., if in ingress we
        // matched on the ACL table with action send/clone_to_cpu...
        if (standard_metadata.egress_port == CPU_PORT) {
            // Add packet_in header and set relevant fields, such as the
            // switch ingress port where the packet was received.
            hdr.cpu_in.setValid();
            hdr.cpu_in.ingress_port = standard_metadata.ingress_port;
            // Exit the pipeline here.
            exit;
        }

        // If this is a multicast packet (flag set by l2_ternary_table), make
        // sure we are not replicating the packet on the same port where it was
        // received. This is useful to avoid broadcasting NDP requests on the
        // ingress port.
        if (local_metadata.is_multicast == true &&
              standard_metadata.ingress_port == standard_metadata.egress_port) {
            mark_to_drop(standard_metadata);
        }
    }
}


control ComputeChecksumImpl(inout parsed_headers_t hdr,
                            inout local_metadata_t local_metadata)
{
    apply {
        // The following is used to update the ICMPv6 checksum of NDP
        // NA packets generated by the ndp reply table in the ingress pipeline.
        // This function is executed only if the NDP header is present.
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
                hdr.ndp.target_ipv6_addr,
                hdr.ndp.type,
                hdr.ndp.length,
                hdr.ndp.target_mac_addr
            },
            hdr.icmpv6.checksum,
            HashAlgorithm.csum16
        );
    }
}


control DeparserImpl(packet_out packet, in parsed_headers_t hdr) {
    apply {
        packet.emit(hdr.cpu_in);
        packet.emit(hdr.ethernet);
        packet.emit(hdr.ipv4);
        packet.emit(hdr.ipv6);
        packet.emit(hdr.srv6h);
        packet.emit(hdr.srv6_list);
        packet.emit(hdr.tcp);
        packet.emit(hdr.udp);
        packet.emit(hdr.icmp);
        packet.emit(hdr.icmpv6);
        packet.emit(hdr.ndp);
    }
}


V1Switch(
    ParserImpl(),
    VerifyChecksumImpl(),
    IngressPipeImpl(),
    EgressPipeImpl(),
    ComputeChecksumImpl(),
    DeparserImpl()
) main;
