# Exercise 5: Bridging

In this exercise, you will be modifying the ONOS app to provide support for
Ethernet (L2) bridging. The P4 program already provides logic to forward packets
based on the Ethernet address. The ONOS app acts as the control plane, in this
case implementing MAC learning logic. You will be asked to modify the
app to interact with the existing switch tables.

## Overview

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

The starter P4 code already defines tables to forward packets based on the
Ethernet address, precisely, two distinct tables to handle two different types
of L2 entries:

1. Unicast entries: which will be filled in by the control plane when the
   location (port) of new hosts is learned.
2. Broadcast/multicast entries: used replicate NDP Neighbor Solicitation
   (NS) messages to all host-facing ports;

For (2), unlike ARP messages in IPv4, which are broadcasted to Ethernet
destination address FF:FF:FF:FF:FF:FF, NDP messages are sent to special
Ethernet addresses specified by RFC2464. These addresses are prefixed
with 33:33 and the last four octets are the last four octets of the IPv6
destination multicast address. The most straightforward way of matching
on such IPv6 broadcast/multicast packets, without digging in the details
of RFC2464, is to use a ternary match on `33:33:**:**:**:**`, where `*` means
"don't care".

For this reason, our solution defines two tables. One that matches in an exact
fashion `l2_exact_table` (easier to scale on switch ASIC memory) and one that
uses ternary matching `l2_ternary_table` (which requires more expensive TCAM
memories, usually much smaller).

These tables are applied to packets in an order defined in the `apply` block
area of the ingress pipeline (`IngressPipeImpl`):

```
if (!l2_exact_table.apply().hit) {
    l2_ternary_table.apply();
}
```

The ternary table has lower priority and is applied only if a matching entry is
not found in the exact one.

**Note**: To keep things simple, we won't be using VLANs to segment our L2
domains. As such, when matching packets in the `l2_ternary_table`, these will be
broadcasted to ALL host-facing ports. You can add support for VLANs as an extra
credit exercise.

### Try pinging hosts

As a start, try to use Mininet to ping any two hosts of the first subnet. It
should not work:

On the Mininet CLI:

```
mininet> h1a ping h1b
PING 2001:1:1::b(2001:1:1::b) 56 data bytes
From 2001:1:1::a icmp_seq=1 Destination unreachable: Address unreachable
From 2001:1:1::a icmp_seq=2 Destination unreachable: Address unreachable
From 2001:1:1::a icmp_seq=3 Destination unreachable: Address unreachable
...
```

However, since `h1a` is expected to generate NDP Neighbor Solicitation (NS)
messages to discover the Ethernet address of `h1b`, and since we have activated
the `hostprovider` app in the previous exercise (remember the ACL flow rules
cloning NDP packets to the CPU), we expect ONOS to discover host `h1a`. To check
that, use the ONOS CLI:

```
onos> hosts -s
id=00:00:00:00:00:1A/None, mac=00:00:00:00:00:1A, locations=[device:leaf1/3], vlan=None, ip(s)=[2001:1:1::a]
```

The host MAC address, the location, and the IPv6 address have been
learned by the `hostprovider` app by sniffing the NDP NS packet.

## Exercise steps

### 1. Modify PTF tests

To get you more familiar with the given P4 implementation, let's start by
looking at the PTF tests for the L2 bridging behavior, located in
`ptf/tests/bridging.py`. Open that file up and modify wherever requested (look
for `TODO EXERCISE 5`).

To run all the tests for this exercise:

    make p4-test TEST=bridging

This command will run all tests in the `bridging` group (i.e. the content of
`ptf/tests/bridging.py`). To run a specific test case you can use:

    make p4-test TEST=<PYTHON MODULE>.<TEST CLASS NAME>

For example:

    make p4-test TEST=bridging.ArpNdpRequestWithCloneTest

If all `bridging` tests succeed, congratulations! You can move to the next step.

### 2. Modify ONOS app

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

#### Enable the bridging component

Once you're confident your solution to the previous step should work, before
building and reloading the app, remember to enable the app component by setting
the `enabled` flag to `true` at the top of the class definition:

```
@Component(
        immediate = true,
        enabled = true
)
public class L2BridgingComponent {
    ...
```

#### Build and reload the app

Use the following command to build and reload your app while ONOS is running:

```
$ make app-build app-reload
```

After reloading the app, you should see messages signaling that a new pipeline
configuration has been set and the `L2BridgingComponent` has been activated:

```
INFO  [PiPipeconfManager] Unregistered pipeconf: org.onosproject.ngsdn-tutorial (fingerprint=...)
INFO  [PipeconfLoader] Found 1 outdated drivers for pipeconf 'org.onosproject.ngsdn-tutorial', removing...
INFO  [PiPipeconfManager] New pipeconf registered: org.onosproject.ngsdn-tutorial (fingerprint=...)
INFO  [PipelineConfigClientImpl] Setting pipeline config for device:leaf1 to org.onosproject.ngsdn-tutorial...
...
INFO  [MainComponent] Waiting to remove flows and groups from previous execution of org.onosproject.ngsdn-tutorial..
...
INFO  [MainComponent] Started
INFO  [L2BridgingComponent] Started
...
INFO  [L2BridgingComponent] *** L2 BRIDGING - Starting initial set up for device:leaf1...
INFO  [L2BridgingComponent] Adding L2 multicast group with 4 ports on device:leaf1...
INFO  [L2BridgingComponent] Adding L2 multicast rules on device:leaf1...
INFO  [L2BridgingComponent] Adding L2 unicast rule on device:leaf1 for host 00:00:00:00:00:1A/None (port 3)...
...
```

#### Understanding ONOS error logs

Before trying your solution in Mininet, it's worth looking at the ONOS log for
possible errors. There are mainly 2 types of errors that you might see when
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

### 3. Examine flow rules and groups

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

### 4. Test L2 bridging on Mininet

Now that the app has been modified and reloaded, flow rules and groups look
right, and the ONOS log is free of potentially harmful errors, you should be
able to repeat the same ping test done at the beginning of the exercise. This
time it should work:

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
ones to them (remember that `h1a` was already discovered at the beginning of
the exercise):

```
INFO  [L2BridgingComponent] HOST_ADDED event! host=00:00:00:00:00:1B/None, deviceId=device:leaf1, port=4
INFO  [L2BridgingComponent] Adding L2 unicast rule on device:leaf1 for host 00:00:00:00:00:1B/None (port 4)...
```

#### Troubleshooting

If ping is not working, here are few steps you can take to troubleshoot your
network:

1. **Check that all flow rules and groups have been written successfully to the
   device.** Using ONOS CLI commands such as `flows -s any device:leaf1` and
   `groups any device:leaf1`, verify that all flows and groups are in state
   `ADDED`. If you see other states such as `PENDING_ADD`, check the ONOS log
   for possible errors with writing those entries to the device. You can also
   use the ONOS web UI to check flows and group state.

2. **Use table counters to verify that tables are being hit as expected.**
   If you don't already have direct counters defined for your table(s), modify
   the P4 program to add some, build and reload the app (`make app-build
   app-reload`). ONOS should automatically detect that and poll counters every
   3-4 seconds (the same period for the reconciliation process). To check their
   values, you can either use the ONOS CLI (`flows -s any device:leaf1`) or the
   web UI.

3. **Double check the PTF tests** and make sure you are creating similar flow
   rules in the `L2BridgingComponent.java`. Do you notice any difference?

4. **Look at the BMv2 logs for possible errors.** Check file
   `/tmp/leaf1/stratum_bmv2.log`.

5. If here and still not working, **reach out to one of the instructors for
   assistance.**

### 5. Visualize hosts on the ONOS web UI

Using the ONF Cloud Tutorial Portal, click on the "ONOS UI" button in the top
bar. If you are using the tutorial VM, open up a browser (e.g. Firefox) to
<http://127.0.0.1:8181/onos/ui>.

To toggle showing hosts on the topology view, press `H` on your keyboard.

## Congratulations

You have completed the fifth exercise! Now your fabric is capable of forwarding
packets between hosts in the same subnet and connected to the same leaf switch.
