# Exercise 4: Enabling topology discovery via P4Runtime packet I/O

In this exercise, you will use P4Runtime packet I/O to implement discovery
of dynamic network components like links between switches or the
presence of hosts. For this you have to integrate the ONOS built-in link
discovery service with your P4 program. ONOS performs link discovery by using
controller packet-in/out with LLDP messages. To make this work, you will need to apply simple
changes to the starter P4 code, validate the P4 changes using PTF-based data
plane unit tests, and finally, apply changes to the pipeconf Java implementation
to enable ONOS's built-in apps to use the packet-in/out support provided by your
P4 implementation.

## Controller packet I/O with P4Runtime

The P4 program under [p4src/main.p4](p4src/main.p4) provides support for
carrying arbitrary metadata in P4Runtime `PacketIn` and `PacketOut` messages.
Two special headers are defined and annotated with the standard P4 annotation
`@controller_header`:

```
@controller_header("packet_in")
header cpu_in_header_t {
    port_num_t ingress_port;
    bit<7> _pad;
}

@controller_header("packet_out")
header cpu_out_header_t {
    port_num_t egress_port;
    bit<7> _pad;
}
```

These headers are used to carry the original switch ingress port of a packet-in,
and specify the intended output port for a packet-out.

When the P4Runtime agent in Stratum receives a packet from the switch CPU port,
it expects to find the `cpu_in_header_t` header as the first one in the frame.
Indeed, it looks at the `controller_packet_metadata` part of the P4Info file to
determine the number of bits to strip at the beginning of the frame and to
populate the corresponding metadata field of the `PacketIn` message, including
the ingress port as in this case.

Similarly, when Stratum receives a P4Runtime `PacketOut` message, it uses the
values found in the `PacketOut`'s metadata fields to serialize and prepend a
`cpu_out_header_t` to the frame before feeding it to the pipeline parser.

## Exercise steps

### 1. Modify P4 program

The P4 starter code already provides support for the following capabilities:

* Parse the `cpu_out` header (if the ingress port is the CPU one)
* Emit the `cpu_in` header as the first one in the deparser
* Provide an ACL table with ternary match fields and an action to clone
  packets to the CPU port (used to generate a packet-ins)

Something is missing to provide complete packet-in/out support, and you have to
modify the P4 program to implement it:

1. Open `p4src/main.p4`;
2. Look for the implementation of the egress pipeline (`control EgressPipeImpl`);
3. Modify the code where requested (look for `TODO EXERCISE 4`);
4. Compile the modified P4 program using the `make p4-build` command. Make sure
   to address any compiler errors before continuing.

At this point, our P4 pipeline should be ready for testing.

### 2. Run PTF tests

Before starting ONOS, let's make sure the P4 changes work as expected by
running some PTF tests. But first, you need to apply a few simple changes to the
test case implementation.

Open file `ptf/tests/packetio.py` and modify wherever requested (look for `TODO
EXERCISE 4`). This test file provides two test cases: one for packet-in and
one for packet-out. In both test cases, you will have to modify the implementation to
use the same name for P4Runtime entities as specified in the P4Info file
obtained after compiling the P4 program (`p4src/build/p4info.txt`).

To run all the tests for this exercise:

    make p4-test TEST=packetio

This command will run all tests in the `packetio` group (i.e. the content of
`ptf/tests/packetio.py`). To run a specific test case you can use:

    make p4-test TEST=<PYTHON MODULE>.<TEST CLASS NAME>

For example:

    make p4-test TEST=packetio.PacketOutTest

If all `packetio` tests succeed, congratulations! You can move to the next step.

**How to debug failing tests?**

When running PTF tests, multiple files are produced that you can use to spot bugs:

* `ptf/stratum_bmv2.log`: BMv2 log with trace level (showing tables matched and
  other info for each packet)
* `ptf/p4rt_write.log`: Log of all P4Runtime Write requests
* `ptf/ptf.pcap`: PCAP file with all packets sent and received during tests
  (the tutorial VM comes with Wireshark for easier visualization)
* `ptf/ptf.log`: PTF log of all packet operations (sent and received)

### 3. Modify ONOS pipeline interpreter

The `PipelineInterpreter` is the ONOS driver behavior used to map the ONOS
representation of packet-in/out to one that is consistent with your P4
pipeline (along with other similar mappings).

Specifically, to use services like LLDP-based link discovery, ONOS built-in
apps need to be able to set the output port of a packet-out and access the
original ingress port of a packet-in.

In the following, you will be asked to apply a few simple changes to the
`PipelineInterpreter` implementation:

1. Open file:
   `app/src/main/java/org/onosproject/ngsdn/tutorial/pipeconf/InterpreterImpl.java`

2. Modify wherever requested (look for `TODO EXERCISE 4`), specifically:

    * Look for a method named `buildPacketOut`, modify the implementation to use the
      same name of the **egress port** metadata field for the `packet_out`
      header as specified in the P4Info file.

    * Look for method `mapInboundPacket`, modify the implementation to use the
      same name of the **ingress port** metadata field for the `packet_in`
      header as specified in the P4Info file.

3. Build ONOS app (including the pipeconf) with the command `make app-build`.

The P4 compiler outputs (`bmv2.json` and `p4info.txt`) are copied in the app
resource folder (`app/src/main/resources`) and will be included in the ONOS app
binary. The copy that gets included in the ONOS app will be the one that gets
deployed by ONOS to the device after the connection is initiated.

### 4. Restart ONOS

**Note:** ONOS should be already running, and in theory, there should be no need
to restart it. However, while ONOS supports reloading the pipeconf with a
modified one (e.g., with updated `bmv2.json` and `p4info.txt`), the version of
ONOS used in this tutorial (2.2.0, the most recent at the time of writing) does
not support reloading the pipeconf behavior classes, in which case the old
classes will still be used. For this reason, to reload a modified version of
`InterpreterImpl.java`, you need to kill ONOS first.

In a terminal window, type:

```
$ make restart
```

This command will restart all containers, removing any state from previous
executions, including ONOS.

Wait approx. 20 seconds for ONOS to completing booting, or check the ONOS log
(`make onos-log`) until no more messages are shown.

### 5. Load updated app and register pipeconf

On a terminal window, type:

```
$ make app-reload
```

This command will upload to ONOS and activate the app binary previously built (located at app/target/ngsdn-tutorial-1.0-SNAPSHOT.oar).

#### Understanding ONOS error logs (`make onos-log`)

There are mainly 2 types of errors that you might see when
reloading the app:

1. Write errors, such as removing a nonexistent entity or inserting one that
   already exists:

    ```
    WARN  [WriteResponseImpl] Unable to DELETE PRE entry on device...: NOT_FOUND Multicast group does not exist ...
    WARN  [WriteResponseImpl] Unable to INSERT table entry on device...: ALREADY_EXIST Match entry exists, use MODIFY if you wish to change action ...
    ```

    These are usually transient errors and **you should not worry about them**.
    They describe a temporary inconsistency of the ONOS-internal device state,
    which should be soon recovered by a periodic reconciliation mechanism.
    The ONOS core periodically polls the device state to make sure its
    internal representation is accurate, while writing any pending modifications
    to the device, solving these errors.

    Otherwise, if you see them appearing periodically (every 3-4 seconds), it
    means the reconciliation process is not working and something else is wrong.
    Try re-loading the app (`make app-reload`); if that doesn't resolve the
    warnings, check with the instructors.

2. Translation errors, signifying that ONOS is not able to translate the flow
   rules (or groups) generated by apps, to a representation that is compatible
   with your P4Info. For example:

    ```
    WARN  [P4RuntimeFlowRuleProgrammable] Unable to translate flow rule for pipeconf 'org.onosproject.ngsdn-tutorial':...
    ```

    **Read carefully the error message and make changes to the app as needed.**
    Chances are that you are using a table, match field, or action name that
    does not exist in your P4Info. Check your P4Info file, modify, and reload the
    app (`make app-build app-reload`).

### 6. Push netcfg to ONOS to trigger device and link discovery

On a terminal window, type:

```
$ make netcfg
```

Use the ONOS CLI to verify that all devices have been discovered:

```
onos> devices -s
id=device:leaf1, available=true, role=MASTER, type=SWITCH, driver=stratum-bmv2:org.onosproject.ngsdn-tutorial
id=device:leaf2, available=true, role=MASTER, type=SWITCH, driver=stratum-bmv2:org.onosproject.ngsdn-tutorial
id=device:spine1, available=true, role=MASTER, type=SWITCH, driver=stratum-bmv2:org.onosproject.ngsdn-tutorial
id=device:spine2, available=true, role=MASTER, type=SWITCH, driver=stratum-bmv2:org.onosproject.ngsdn-tutorial
```

Verify that all links have been discovered. You should see 8 links in total,
each one representing a direction of the 4 bidirectional links of our Mininet
topology:

```
onos> links
src=device:leaf1/1, dst=device:spine1/1, type=DIRECT, state=ACTIVE, expected=false
src=device:leaf1/2, dst=device:spine2/1, type=DIRECT, state=ACTIVE, expected=false
src=device:leaf2/1, dst=device:spine1/2, type=DIRECT, state=ACTIVE, expected=false
src=device:leaf2/2, dst=device:spine2/2, type=DIRECT, state=ACTIVE, expected=false
src=device:spine1/1, dst=device:leaf1/1, type=DIRECT, state=ACTIVE, expected=false
src=device:spine1/2, dst=device:leaf2/1, type=DIRECT, state=ACTIVE, expected=false
src=device:spine2/1, dst=device:leaf1/2, type=DIRECT, state=ACTIVE, expected=false
src=device:spine2/2, dst=device:leaf2/2, type=DIRECT, state=ACTIVE, expected=false
```

**If you don't see any link**, check the ONOS log (`make onos-log`) for any
error with packet-in/out handling. In case of errors, it's possible that you
have not modified `InterpreterImpl.java` correctly. In this case, go back to
exercise step 3.

Verify flow rules, you should see 2 new flow rules for each device. For example,
to show all flow rules installed so far on device `leaf1`:

```
onos> flows -s any device:leaf1
deviceId=device:leaf1, flowRuleCount=5
    ...
    ADDED, ..., table=IngressPipeImpl.acl, priority=40000, selector=[ETH_TYPE:lldp], treatment=[immediate=[IngressPipeImpl.clone_to_cpu()]]
    ADDED, ..., table=IngressPipeImpl.acl, priority=40000, selector=[ETH_TYPE:bddp], treatment=[immediate=[IngressPipeImpl.clone_to_cpu()]]
```

These flow rules are the result of the translation of flow objectives generated
by the `lldpprovider` app., and used to to intercept LLDP and BBDP packets
(`selector=[ETH_TYPE:lldp]` and `selector=[ETH_TYPE:bbdp]`), periodically
emitted on all devices' ports as P4Runtime packet-outs, allowing for automatic
link discovery.

### 7. Visualize links on the ONOS UI

Using the ONF Cloud Tutorial Portal, click on the "ONOS UI" button in the top
bar. If you are using the tutorial VM, open up a browser (e.g. Firefox) to
<http://127.0.0.1:8181/onos/ui>.

On the same page where the ONOS topology view is shown:
* Press `L` to show device labels;
* Press `A` multiple times until you see link stats, in either
  packets/seconds (pps) or bits/seconds.

Link stats are derived by ONOS by periodically obtaining the port counters for
each device. ONOS internally uses gNMI to read port information, including
counters.

In this case, you should see approx 1 packet/s, as that's the rate of
packet-outs generated by the `lldpprovider` app.

## Host discovery & L2 bridging

Now that the apps are loaded and we have some links, we can send traffic ...

TODOs:

 - copy solutions
 - copy L2 implementation explanations of tables
 - flows and group examination
 - run ping
 - look at UI

### Overview

The ONOS app assumes that hosts of a given subnet are all connected to the same
leaf, and two interfaces of two different leaves cannot be configured with the
same IPv6 subnet. In other words, L2 bridging is allowed only for hosts
connected to the same leaf.

The Mininet script [topo.py](mininet/topo.py) used in this tutorial defines 4
subnets:

* `2001:1:1::/64` with 3 hosts connected to `leaf1` (`h1a`, `h1b`, and `h1c`)
* `2001:1:2::/64` with 1 hosts connected to `leaf1` (`h2`)
* `2001:2:3::/64` with 1 hosts connected to `leaf2` (`h3`)
* `2001:2:4::/64` with 1 hosts connected to `leaf2` (`h4`)

The same IPv6 prefixes are defined in the [netcfg.json](netcfg.json) file and
are used to provide interface configuration to ONOS.

### Our P4 implementation of L2 bridging

The P4 code defines tables to forward packets based on the Ethernet address,
precisely, two distinct tables, to handle two different types of L2 entries:

1. Unicast entries: which will be filled in by the control plane when the
   location (port) of new hosts is learned.
2. Broadcast/multicast entries: used replicate NDP Neighbor Solicitation
   (NS) messages to all host-facing ports;

For (2), unlike ARP messages in IPv4, which are broadcasted to Ethernet
destination address FF:FF:FF:FF:FF:FF, NDP messages are sent to special Ethernet
addresses specified by RFC2464. These addresses are prefixed with 33:33 and the
last four octets are the last four octets of the IPv6 destination multicast
address. The most straightforward way of matching on such IPv6
broadcast/multicast packets, without digging in the details of RFC2464, is to
use a ternary match on `33:33:**:**:**:**`, where `*` means "don't care".

For this reason, our solution defines two tables. One that matches in an exact
fashion `l2_exact_table` (easier to scale on switch ASIC memory) and one that
uses ternary matching `l2_ternary_table` (which requires more expensive TCAM
memories, usually much smaller).

These tables are applied to packets in an order defined in the `apply` block
of the ingress pipeline (`IngressPipeImpl`):

```
if (!l2_exact_table.apply().hit) {
    l2_ternary_table.apply();
}
```

The ternary table has lower priority and it's applied only if a matching entry
is not found in the exact one.

**Note**: To keep things simple, we won't be using VLANs to segment our L2
domains. As such, when matching packets in the `l2_ternary_table`, these will be
broadcasted to ALL host-facing ports.

### ONOS L2BridgingComponent

The next step will be to modify the ONOS app to control the L2 bridging parts of
the P4 program modified before.

The source code that you will need to modify is located here:
`app/src/main/java/org/p4/p4d2/tutorial/L2BridgingComponent.java`

Modify the code wherever requested (look for `TODO EXERCISE 5`).

#### Complete methods implementation to insert L2 flow rules

This app component defines two event listener located at the bottom of the
`L2BridgingComponent` class, `InternalDeviceListener` for device events (e.g.
connection of a new switch) and `InternalHostListener` for host events (e.g. new
host discovered). These listeners in turn call methods like:

* `setUpDevice()`: responsible for creating a multicast group for all host-facing
  ports and inserting flow rules to broadcast/multicast packets such as ARP and
  NDP messages;

* `learnHost()`: responsible for inserting unicast L2 entries based on the
  discovered host location.

To support reloading the app implementation, these methods are also called at
component activation for all devices and hosts known by ONOS at the time of
activation (look for methods `activate()` and `setUpAllDevices()`).

To keep things simple, our broadcast domain will be restricted to a single
device, i.e. we allow packet replication only for ports of the same leaf switch.
As such, we can exclude ports going to the spines from the multicast group. To
determine whether a port is expected to be facing hosts or not, we look at the
interface configuration in [netcfg.json](netcfg.json) file (look for the `ports`
section of the JSON file).

The starter code already provides an implementation of the method
`insertMulticastGroup()`; you are required to complete the implementation of two
other methods: `insertMulticastFlowRules()` and `learnHost()`.

### Examine flow rules and groups

Check the ONOS flow rules, you should now see flow rules installed by your app.
For example, to show all flow rules installed so far on device `leaf1`:

```
onos> flows -s any device:leaf1
deviceId=device:leaf1, flowRuleCount=...
    ADDED, bytes=0, packets=0, table=IngressPipeImpl.l2_exact_table, priority=10, selector=[hdr.ethernet.dst_addr=0xbb00000001], treatment=[immediate=[IngressPipeImpl.set_egress_port(port_num=0x1)]]
    ...
    ADDED, bytes=0, packets=0, table=IngressPipeImpl.l2_ternary_table, priority=10, selector=[hdr.ethernet.dst_addr=0x333300000000&&&0xffff00000000], treatment=[immediate=[IngressPipeImpl.set_multicast_group(gid=0xff)]]
    ADDED, bytes=3596, packets=29, table=IngressPipeImpl.l2_ternary_table, priority=10, selector=[hdr.ethernet.dst_addr=0xffffffffffff&&&0xffffffffffff], treatment=[immediate=[IngressPipeImpl.set_multicast_group(gid=0xff)]]
    ...
```

To show also the groups installed so far, you can use the `groups` command. For
example to show groups on `leaf1`:
```
onos> groups any device:leaf1
deviceId=device:leaf1, groupCount=2
   id=0x63, state=ADDED, type=CLONE, bytes=0, packets=0, appId=org.onosproject.core, referenceCount=0
       id=0x63, bucket=1, bytes=0, packets=0, weight=-1, actions=[OUTPUT:CONTROLLER]
   id=0xff, state=ADDED, type=ALL, bytes=0, packets=0, appId=org.onosproject.ngsdn-tutorial, referenceCount=0
       id=0xff, bucket=1, bytes=0, packets=0, weight=-1, actions=[OUTPUT:3]
       id=0xff, bucket=2, bytes=0, packets=0, weight=-1, actions=[OUTPUT:4]
       id=0xff, bucket=3, bytes=0, packets=0, weight=-1, actions=[OUTPUT:5]
       id=0xff, bucket=4, bytes=0, packets=0, weight=-1, actions=[OUTPUT:6]
```

The `CLONE` group is the same introduced in Exercise 3, which maps to P4Runtime
`CloneSessionEntry` and it's used to clone packets to the controller via
packet-in.

The `ALL` group is a new one, created by our app (`appId=org.onosproject.ngsdn-tutorial`).
Groups of type `ALL` in ONOS map to P4Runtime `MulticastGroupEntry`, in this
case used to broadcast NDP NS packets to all host-facing ports. This group is
installed by `L2BridgingComponent.java`, and is used by an entry in the P4
`l2_ternary_table` (look for flow rule with
`treatment=[immediate=[IngressPipeImpl.set_multicast_group(gid=0xff)]`)

### Test L2 bridging on Mininet

To verify that L2 bridging works as intended, send a ping between hosts in the
same subnet:

```
mininet> h1a ping h1b
PING 2001:1:1::b(2001:1:1::b) 56 data bytes
64 bytes from 2001:1:1::b: icmp_seq=2 ttl=64 time=0.580 ms
64 bytes from 2001:1:1::b: icmp_seq=3 ttl=64 time=0.483 ms
64 bytes from 2001:1:1::b: icmp_seq=4 ttl=64 time=0.484 ms
...
```

Check the ONOS log, you should see messages related to the discovery of host
`h1b` who is now receiving NDP NS messages from `h1a` and replying with NDP NA
ones to them:

```
INFO  [L2BridgingComponent] HOST_ADDED event! host=00:00:00:00:00:1B/None, deviceId=device:leaf1, port=4
INFO  [L2BridgingComponent] Adding L2 unicast rule on device:leaf1 for host 00:00:00:00:00:1B/None (port 4)...
```

### Visualize hosts on the ONOS web UI

Using the ONF Cloud Tutorial Portal, click on the "ONOS UI" button in the top
bar. If you are using the tutorial VM, open up a browser (e.g. Firefox) to
<http://127.0.0.1:8181/onos/ui>.

To toggle showing hosts on the topology view, press `H` on your keyboard.

## Congratulations!

You have completed the fourth exercise!
