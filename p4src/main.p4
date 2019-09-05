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

// Always start by including the P4 core library and the architecture
// definition, v1model in this case.
// https://github.com/p4lang/p4c/blob/master/p4include/core.p4
// https://github.com/p4lang/p4c/blob/master/p4include/v1model.p4
#include <core.p4>
#include <v1model.p4>


//------------------------------------------------------------------------------
// PRE-PROCESSOR constants
// Can be defined at compile time with the -D flag.
//------------------------------------------------------------------------------

// CPU_PORT specifies the P4 port number associated to packet-in and packet-out.
// All packets forwarded via this port will be delivered to the controller as
// PacketIn messages. Similarly, PacketOut messages from the controller will be
// seen by the P4 pipeline as coming from the CPU_PORT.
#define CPU_PORT 255

// CPU_CLONE_SESSION_ID specifies the mirroring session for packets to be cloned
// to the CPU port. Packets associated with this session ID will be cloned to
// the CPU_PORT as well as being transmitted via their original egress port
// (e.g. set by the bridging/routing/acl table). For cloning to work, the
// P4Runtime controller needs first to insert a CloneSessionEntry that maps this
// session ID to the CPU_PORT. See
// https://s3-us-west-2.amazonaws.com/p4runtime/docs/v1.0.0/P4Runtime-Spec.html#sec-clonesessionentry
#define CPU_CLONE_SESSION_ID 99



//------------------------------------------------------------------------------
// TYPEDEF DECLARATIONS
// To favor readability.
//------------------------------------------------------------------------------

typedef bit<9>   port_num_t;
typedef bit<48>  mac_addr_t;
typedef bit<16>  mcast_group_id_t;
typedef bit<32>  ipv4_addr_t;
typedef bit<128> ipv6_addr_t;
typedef bit<16>  l4_port_t;



//------------------------------------------------------------------------------
// CONSTANT VALUES
//------------------------------------------------------------------------------

const bit<16> ETHERTYPE_IPV6 = 0x86dd;

const bit<8> PROTO_TCP = 6;
const bit<8> PROTO_UDP = 17;
const bit<8> PROTO_ICMPV6 = 58;

const mac_addr_t IPV6_MCAST_01 = 0x33_33_00_00_00_01;

const bit<8> ICMP6_TYPE_NS = 135;
const bit<8> ICMP6_TYPE_NA = 136;
const bit<8> NDP_OPT_TARGET_LL_ADDR = 2;
const bit<32> NDP_FLAG_ROUTER = 0x80000000;
const bit<32> NDP_FLAG_SOLICITED = 0x40000000;
const bit<32> NDP_FLAG_OVERRIDE = 0x20000000;



//------------------------------------------------------------------------------
// HEADER DEFINITIONS
//------------------------------------------------------------------------------

header ethernet_t {
    mac_addr_t  dst_addr;
    mac_addr_t  src_addr;
    bit<16>     ether_type;
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

// Packet-in header. Prepended to packets sent to the CPU_PORT and used by the
// P4Runtime server (Stratum) to populate the PacketIn metadata fields. Here we
// use it to carry the original ingress port where the packet was received.
@controller_header("packet_in")
header packet_in_t {
    port_num_t  ingress_port;
    bit<7>      _pad;
}

// Packet-out header. Prepended to packets received from the CPU_PORT. Fields of
// this header are populated by the P4Runtime server based on the PacketOut
// metadata fields. Here we use it to inform the P4 program on which port this
// packet-out should be transmitted.
@controller_header("packet_out")
header packet_out_t {
    port_num_t  egress_port;
    bit<7>      _pad;
}

// We collect all headers under the same data structure, associated with each
// packet. The goal of the parser is to populate the fields of this struct.
struct parsed_headers_t {
    packet_out_t  packet_out;
    packet_in_t   packet_in;
    ethernet_t    ethernet;
    ipv6_t        ipv6;
    tcp_t         tcp;
    udp_t         udp;
    icmpv6_t      icmpv6;
    ndp_t         ndp;
    ndp_option_t  ndp_option;
}



//------------------------------------------------------------------------------
// USER-DEFINED METADATA
// User-defined data structures associated with each packet.
//------------------------------------------------------------------------------

struct local_metadata_t {
    bool       skip_l2;
    l4_port_t  l4_src_port;
    l4_port_t  l4_dst_port;
    bool       is_multicast;
}

// The v1model architecture also defines an intrinsic metadata structure, which
// fields will be automatically populated by the target before feeding the
// packet to the parser. For convenience, we provide here its definition:
/*
struct standard_metadata_t {
    bit<9>  ingress_port;
    bit<9>  egress_spec; // Set by the ingress pipeline
    bit<9>  egress_port; // Read-only, available in the egress pipeline
    bit<32> instance_type;
    bit<32> packet_length;
    bit<48> ingress_global_timestamp;
    bit<48> egress_global_timestamp;
    bit<16> mcast_grp; // ID for the mcast replication table
    bit<1>  checksum_error; // 1 indicates that verify_checksum() method failed

    // Etc... See v1model.p4 for the complete definition.
}
*/



//------------------------------------------------------------------------------
// PARSER IMPLEMENTATION
//
// Described as a state machine with one "start" state and two final states,
// "accept" (indicating successful parsing) and "reject" (indicating a parsing
// failure, not used here). Each intermediate state can specify the next state
// by using a select statement over the header fields extracted, or other
// values.
//------------------------------------------------------------------------------

parser ParserImpl (packet_in packet,
                   out parsed_headers_t hdr,
                   inout local_metadata_t local_metadata,
                   inout standard_metadata_t standard_metadata)
{

    // We assume the first header will always be the Ethernet one, unless the
    // the packet is a packet-out coming from the CPU_PORT.
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
            ETHERTYPE_IPV6: parse_ipv6;
            default: accept;
        }
    }

    state parse_ipv6 {
        packet.extract(hdr.ipv6);
        transition select(hdr.ipv6.next_hdr) {
            PROTO_TCP:    parse_tcp;
            PROTO_UDP:    parse_udp;
            PROTO_ICMPV6: parse_icmpv6;
            default: accept;
        }
    }

    state parse_tcp {
        packet.extract(hdr.tcp);
        // For convenience, we copy the port numbers on generic metadata fields
        // that are independent of the protocol type (TCP or UDP). This makes it
        // easier to specify the ECMP hash inputs, or when definin match fields
        // for the ACL table.
        local_metadata.l4_src_port = hdr.tcp.src_port;
        local_metadata.l4_dst_port = hdr.tcp.dst_port;
        transition accept;
    }

    state parse_udp {
        packet.extract(hdr.udp);
        // Same here...
        local_metadata.l4_src_port = hdr.udp.src_port;
        local_metadata.l4_dst_port = hdr.udp.dst_port;
        transition accept;
    }

    state parse_icmpv6 {
        packet.extract(hdr.icmpv6);
        transition select(hdr.icmpv6.type) {
            ICMP6_TYPE_NS: parse_ndp;
            ICMP6_TYPE_NA: parse_ndp;
            default: accept;
        }
    }

    state parse_ndp {
        packet.extract(hdr.ndp);
        // FIXME: do we always need to extract options?
        transition parse_ndp_option;
    }

    state parse_ndp_option {
        packet.extract(hdr.ndp_option);
        transition accept;
    }
}

//------------------------------------------------------------------------------
// INGRESS PIPELINE IMPLEMENTATION
//
// All packets will be processed by this pipeline right after the parser block.
// Provides logic for:
// - L2 bridging
// - L3 routing
// - ACL
// - NDP handling
//
// This block operates on the parsed headers (hdr), the user-defined metadata
// (local_metadata), and the architecture-specific instrinsic metadata
// (standard_metadata).
//------------------------------------------------------------------------------

control IngressPipeImpl (inout parsed_headers_t hdr,
                         inout local_metadata_t local_metadata,
                         inout standard_metadata_t standard_metadata) {

    // Drop action definition, shared by many tables. Hence we define it here.
    action drop() {
        // Sets an architecture-specific metadata field to signal that the
        // packet should be dropped at the end of this pipeline.
        mark_to_drop(standard_metadata);
    }

    // *** L2 BRIDGING
    //
    // Here we define tables to forward packets based on their Ethernet
    // destination address. There are two types of L2 entries that we
    // need to support:
    //
    // 1. Broadcast/multicast entries: used replicate NDP Neighbor Solicitation
    //    (NS) messages to all host-facing ports;
    // 2. Unicast entries: which will be filled in by the control plane when the
    //    location (port) of new hosts is learned.
    //
    // For (1), unlike ARP messages in IPv4 which are broadcasted to Ethernet
    // destination address FF:FF:FF:FF:FF:FF, NDP messages are sent to special
    // Ethernet addresses specified by RFC2464. These destination addresses are
    // prefixed with 33:33 and the last four octets are the last four octets of
    // the IPv6 destination multicast address. The most straightforward way of
    // matching on such IPv6 broadcast/multicast packets, without digging in the
    // details of RFC2464, is to use a ternary match on 33:33:**:**:**:**, where
    // * means "don't care".
    //
    // For this reason, we define two tables. One that matches in an exact
    // fashion (easier to scale on switch ASICs) and one that uses ternary
    // matching (which requires more expensive TCAM memories, usually smaller).

    // --- l2_exact_table (for unicast entries) --------------------------------

    action set_output_port(port_num_t port_num) {
        standard_metadata.egress_spec = port_num;
    }

    table l2_exact_table {
        key = {
            hdr.ethernet.dst_addr: exact;
        }
        actions = {
            set_output_port;
            @defaultonly drop;
        }
        const default_action = drop;
        @name("l2_exact_table_counter")
        counters = direct_counter(CounterType.packets_and_bytes);
    }

    // --- l2_ternary_table (for broadcast/multicast entries) ------------------

    action set_multicast_group(mcast_group_id_t gid) {
        // gid will be used by the Packet Replication Engine (PRE)--located
        // right after the ingress pipeline, to replicate the packet to multiple
        // egress ports, specified by the control plane by means of P4Runtime
        // MulticastGroupEntry messages.
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
    //   MAC address the "router MAC" addres, which we call this the
    //   "my_station" MAC. Such address is defined at runtime by the control
    //   plane.
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
    // packet. Later in the control block, we define logic such that if an entry
    // in this table is hit, we will route the packet. Otherwise the routing
    // table will be skipped.

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
    // selected by perfoming a hash function over a pre-detemrined set of header
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

    table routing_v6_table {
      key = {
          hdr.ipv6.dst_addr:          lpm;
          // The following fields are not used for matching, but as input to the
          // ecmp_selector hash function.
          hdr.ipv6.dst_addr:          selector;
          hdr.ipv6.src_addr:          selector;
          hdr.ipv6.flow_label:        selector;
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

    // *** ACL
    //
    // Provides ways override on a previous forwarding decision, for example
    // requiring that a packet is cloned/sent to the CPU, or dropped.

    // --- acl_table -----------------------------------------------------------

    action send_to_cpu() {
        standard_metadata.egress_spec = CPU_PORT;
    }

    action clone_to_cpu() {
        // Cloning is achieved by using a v1model-specific primitive...
        // TODO: say a bit more, andy f has an excellent description of this in the bmv2 docs
        clone3(CloneType.I2E, CPU_CLONE_SESSION_ID, { standard_metadata.ingress_port });
    }

    table acl_table {
        key = {
            standard_metadata.ingress_port: ternary;
            hdr.ethernet.dst_addr:          ternary;
            hdr.ethernet.src_addr:          ternary;
            hdr.ethernet.ether_type:        ternary;
            hdr.ipv6.next_hdr:              ternary;
            hdr.icmpv6.type:                ternary;
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
    // The NDP protocol is the equivalent of ARP but for IPv6 networks. Here we
    // provide tables that allow the switch to reply to NDP Neighboor Solitation
    // (NS) requests entirelly in the data plane. That is, NDP Neighboor
    // Advertisement (NA) replies can be generated by the switch itself, without
    // forwarding the request to the target host. The control plane is
    // respoinsible for instructing the switch with a mapping between IPv6 and
    // MAC addreses. When an NDP NS packet is received, we use P4 to transform
    // the same packet in NDP NA one and we send it back from the ingress port.

    // --- acl_table -----------------------------------------------------------

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

    apply {
        if (hdr.packet_out.isValid()) {
            standard_metadata.egress_spec = hdr.packet_out.egress_port;
            hdr.packet_out.setInvalid();
            exit;
        }

        if (hdr.icmpv6.isValid() && hdr.icmpv6.type == ICMP6_TYPE_NS) {
            ndp_reply_table.apply();
        }

        if (my_station_table.apply().hit && hdr.ipv6.isValid()) {
            routing_v6_table.apply();
            if(hdr.ipv6.hop_limit == 0) {
                drop();
            }
        }

        if (!local_metadata.skip_l2 && standard_metadata.drop != 1w1) {
            if (!l2_exact_table.apply().hit) {
                l2_ternary_table.apply();
            }
        }

        acl_table.apply();
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

//------------------------------------------------------------------------------
// DEPARSER
// Specifies the order of headers on the wire. Only headers that are marked as
// "valid" will be emitted on the wire, otherwise, they are skipped.
//------------------------------------------------------------------------------

control DeparserImpl(packet_out packet, in parsed_headers_t hdr) {
    apply {
        packet.emit(hdr.packet_in);
        packet.emit(hdr.ethernet);
        packet.emit(hdr.ipv6);
        packet.emit(hdr.tcp);
        packet.emit(hdr.udp);
        packet.emit(hdr.icmpv6);
        packet.emit(hdr.ndp);
        packet.emit(hdr.ndp_option);
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
