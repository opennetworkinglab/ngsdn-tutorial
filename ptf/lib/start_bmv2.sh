#!/usr/bin/env bash

set -xe

CPU_PORT=255
GRPC_PORT=28000

# Create veths
for idx in 0 1 2 3 4 5 6 7; do
    intf0="veth$(($idx*2))"
    intf1="veth$(($idx*2+1))"
    if ! ip link show $intf0 &> /dev/null; then
        ip link add name $intf0 type veth peer name $intf1
        ip link set dev $intf0 up
        ip link set dev $intf1 up

        # Set the MTU of these interfaces to be larger than default of
        # 1500 bytes, so that P4 behavioral-model testing can be done
        # on jumbo frames.
        ip link set $intf0 mtu 9500
        ip link set $intf1 mtu 9500

        # Disable IPv6 on the interfaces, so that the Linux kernel
        # will not automatically send IPv6 MDNS, Router Solicitation,
        # and Multicast Listener Report packets on the interface,
        # which can make P4 program debugging more confusing.
        #
        # Testing indicates that we can still send IPv6 packets across
        # such interfaces, both from scapy to simple_switch, and from
        # simple_switch out to scapy sniffing.
        #
        # https://superuser.com/questions/356286/how-can-i-switch-off-ipv6-nd-ra-transmissions-in-linux
        sysctl net.ipv6.conf.${intf0}.disable_ipv6=1
        sysctl net.ipv6.conf.${intf1}.disable_ipv6=1
    fi
done

# Interface argumnents for stratum_bmv2
INTFS=
for idx in 0 1 2 3 4 5 6 7; do
    p4Port=$(( ${idx} ))
    vethIdx=$(( 2*${idx} + 1 ))
    INTFS="${INTFS} -i${p4Port}@veth${vethIdx}"
done

# shellcheck disable=SC2086
simple_switch_grpc \
    --device-id 1 \
    ${INTFS} \
    --log-console \
    -Ltrace \
    --no-p4 \
    -- \
    --cpu-port ${CPU_PORT} \
    --grpc-server-addr 0.0.0.0:${GRPC_PORT} \
    > bmv2.log 2>&1
