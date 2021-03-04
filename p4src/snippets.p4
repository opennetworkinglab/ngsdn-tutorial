//------------------------------------------------------------------------------
// SNIPPETS FOR EXERCISE 5 (IPV6 ROUTING)
//------------------------------------------------------------------------------

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

// ECMP action selector definition:
action_selector(HashAlgorithm.crc16, 32w1024, 32w16) ecmp_selector;

// Example indirect table that uses the ecmp_selector. "Selector" match fields
// are used as input to the action selector hash function.
// table table_with_action_selector {
//   key = {
//       hdr_field_1: lpm / exact / ternary;
//       hdr_field_2: selector;
//       hdr_field_3: selector;
//       ...
//   }
//   actions = { ... }
//   implementation = ecmp_selector;
//   ...
// }

//------------------------------------------------------------------------------
// SNIPPETS FOR EXERCISE 6 (SRV6)
//------------------------------------------------------------------------------

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

table srv6_transit {
  key = {
      // TODO: Add match fields for SRv6 transit rules; we'll start with the
      //  destination IP address.
  }
  actions = {
      // Note: Single segment header doesn't make sense given PSP
      // i.e. we will pop the SRv6 header when segments_left reaches 0
      srv6_t_insert_2;
      srv6_t_insert_3;
      // Extra credit: set a metadata field, then push label stack in egress
  }
  @name("srv6_transit_table_counter")
  counters = direct_counter(CounterType.packets_and_bytes);
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
