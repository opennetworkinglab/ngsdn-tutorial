# Exercise 3 - Using ONOS as the control plane

This exercise provides a hands-on introduction to ONOS where you will learn how
to:

1. Start ONOS along with a set of built-in apps for basic services such as
   topology discovery
2. Load a custom ONOS app and pipeconf
3. Push a configuration file to ONOS to discover and control the
   `stratum_bmv2` switches using P4Runtime and gNMI
4. Access the ONOS CLI and UI to verify that all `stratum_bmv2` switches have
   been discovered and configured correctly.

### 2. Start ONOS

In a terminal window, type:

```
$ make restart
```

This command will restart the ONOS and Mininet containers, in case those were
running from previous exercises, clearing any previous state.

The parameters to start the ONOS container are specified in [docker
-compose.yml](docker-compose.yml). The container is configured to pass the
environment variable `ONOS_APPS`, used to define the built-in apps to load
during startup.

In our case this variable has value:

```
ONOS_APPS=gui,drivers.bmv2,lldpprovider,hostprovider
```

Requesting ONOS to pre-load the following built-in apps:

* `gui`: ONOS web user interface (available at <http://localhost:8181/onos/ui>)
* `drivers.bmv2`: BMv2/Stratum drivers based on P4Runtime, gNMI, and gNOI
* `lldpprovider`: LLDP-based link discovery application (used in Exercise 4)
* `hostprovider`: Host discovery application (used in Exercise 5)


Once ONOS has started, you can check its log using the `make onos-log` command.

To **verify that all required apps have been activated**, run the following
command in a new terminal window to access the ONOS CLI. Use password `rocks`
when prompted:

```
$ make onos-cli
```

If you see the following error, then ONOS is still starting; wait a minute and try again.
```
ssh_exchange_identification: Connection closed by remote host
make: *** [onos-cli] Error 255
```

When you see the Password prompt, type the default password: `rocks`

Type the following command in the ONOS CLI to show the list of running apps:

```
onos> apps -a -s
```

Make sure you see the following list of apps displayed:

```
*   5 org.onosproject.protocols.grpc        2.2.0    gRPC Protocol Subsystem
*   6 org.onosproject.protocols.gnmi        2.2.0    gNMI Protocol Subsystem
*  29 org.onosproject.drivers               2.2.0    Default Drivers
*  34 org.onosproject.generaldeviceprovider 2.2.0    General Device Provider
*  35 org.onosproject.protocols.p4runtime   2.2.0    P4Runtime Protocol Subsystem
*  36 org.onosproject.p4runtime             2.2.0    P4Runtime Provider
*  37 org.onosproject.drivers.p4runtime     2.2.0    P4Runtime Drivers
*  42 org.onosproject.protocols.gnoi        2.2.0    gNOI Protocol Subsystem
*  52 org.onosproject.hostprovider          2.2.0    Host Location Provider
*  53 org.onosproject.lldpprovider          2.2.0    LLDP Link Provider
*  66 org.onosproject.drivers.gnoi          2.2.0    gNOI Drivers
*  70 org.onosproject.drivers.gnmi          2.2.0    gNMI Drivers
*  71 org.onosproject.pipelines.basic       2.2.0    Basic Pipelines
*  72 org.onosproject.drivers.stratum       2.2.0    Stratum Drivers
* 161 org.onosproject.gui                   2.2.0    ONOS Legacy GUI
* 181 org.onosproject.drivers.bmv2          2.2.0    BMv2 Drivers
```

This is definitely more apps than what defined in `$ONOS_APPS`. That's
because each app in ONOS can define other apps as dependencies. When loading an
app, ONOS automatically resolve dependencies and loads all other required apps.

**Disable link discovery service**

Link discovery will be the focus of the next exercise. For now, this service
lacks support in the P4 program. We suggest you deactivate it for the rest of
this exercise, to avoid running into issues. To deactivate the link discovery
service, using the following ONOS CLI command:

```
onos> app deactivate lldpprovider
```

To quit out of the ONOS CLI, use `Ctrl-D`. This will just end the CLI process
and will not stop the ONOS process.

**Restart ONOS in case of errors**

If anything goes wrong and you need to kill ONOS, you can use command `make
restart` to restart both Mininet and ONOS.

### 3. Build app and register pipeconf

Inside the [app/](./app) directory you will find a starter implementation of an
ONOS app that includes a pipeconf. The pipeconf-related files are the following:

* [PipeconfLoader.java](./app/src/main/java/org/onosproject/ngsdn/tutorial/pipeconf/PipeconfLoader.java):
  A component that registers the pipeconf at app activation;
* [InterpreterImpl.java](./app/src/main/java/org/onosproject/ngsdn/tutorial/pipeconf/InterpreterImpl.java):
  An implementation of the `PipelineInterpreter` driver behavior;
* [PipelinerImpl.java](./app/src/main/java/org/onosproject/ngsdn/tutorial/pipeconf/PipelinerImpl.java):
  An implementation of the `Pipeliner` driver behavior;

To build the ONOS app (including the pipeconf), In the second terminal window,
use the command:

```
$ make app-build
```

This will produce a binary file `app/target/ngsdn-tutorial-1.0-SNAPSHOT.oar`
that we will use to install the application in the running ONOS instance.

Use the following command to upload to ONOS and activate the app binary:

```
$ make app-reload
```

After the app has been activated, you should see the following messages in the
ONOS log (`make onos-log`) signaling that the pipeconf has been registered and
the different app components have been started:

```
INFO  [PiPipeconfManager] New pipeconf registered: org.onosproject.ngsdn-tutorial (fingerprint=...)
INFO  [MainComponent] Started
```

Alternatively, you can show the list of registered pipeconfs using the ONOS CLI
(`make onos-cli`) command:

```
onos> pipeconfs
```

### 4. Push netcfg to ONOS

Now that ONOS and Mininet are running, it's time to let ONOS know how to reach
the 4 switches and control them. We do this by using a configuration file
located at [mininet/netcfg.json](mininet/netcfg.json), which contains
information such as:

* The gRPC address and port associated to each Stratum device;
* The ONOS driver to use for each device, `stratum-bmv2` in this case;
* The pipeconf to use for each device, `org.onosproject.ngsdn-tutorial` in this
  case, as defined in [PipeconfLoader.java][PipeconfLoader.java];
* Configuration specific to our custom app, such as the `myStationMac` or a flag
  to signal if a switch has to be considered a spine or not.

This file contains also information related to the IPv6 configuration associated
to each switch interface. We will discuss this information in more details in
the next exercises.

On a terminal window, type:

```
$ make netcfg
```

This command will push the `netcfg.json` to ONOS, triggering discovery and
configuration of the 4 switches.

FIXME: do log later, or deactivate lldp app for now to avoid clogging with error messages

Check the ONOS log (`make onos-log`), you should see messages like:

```
INFO  [GrpcChannelControllerImpl] Creating new gRPC channel grpc:///mininet:50001?device_id=1...
...
INFO  [StreamClientImpl] Setting mastership on device:leaf1...
...
INFO  [PipelineConfigClientImpl] Setting pipeline config for device:leaf1 to org.onosproject.ngsdn-tutorial...
...
INFO  [GnmiDeviceStateSubscriber] Started gNMI subscription for 6 ports on device:leaf1
...
INFO  [DeviceManager] Device device:leaf1 port [leaf1-eth1](1) status changed (enabled=true)
INFO  [DeviceManager] Device device:leaf1 port [leaf1-eth2](2) status changed (enabled=true)
INFO  [DeviceManager] Device device:leaf1 port [leaf1-eth3](3) status changed (enabled=true)
INFO  [DeviceManager] Device device:leaf1 port [leaf1-eth4](4) status changed (enabled=true)
INFO  [DeviceManager] Device device:leaf1 port [leaf1-eth5](5) status changed (enabled=true)
INFO  [DeviceManager] Device device:leaf1 port [leaf1-eth6](6) status changed (enabled=true)
```

### 5. Use the ONOS CLI to verify the network configuration

Access the ONOS CLI using `make onos-cli`. Enter the following command to
verify the network config pushed before:

```
onos> netcfg
```

#### Devices

Verify that all 4 devices have been discovered and are connected:

```
onos> devices -s
id=device:leaf1, available=true, role=MASTER, type=SWITCH, driver=stratum-bmv2:org.onosproject.ngsdn-tutorial
id=device:leaf2, available=true, role=MASTER, type=SWITCH, driver=stratum-bmv2:org.onosproject.ngsdn-tutorial
id=device:spine1, available=true, role=MASTER, type=SWITCH, driver=stratum-bmv2:org.onosproject.ngsdn-tutorial
id=device:spine2, available=true, role=MASTER, type=SWITCH, driver=stratum-bmv2:org.onosproject.ngsdn-tutorial
```

Make sure you see `available=true` for all devices. That means ONOS is connected
to the device and the pipeline configuration has been pushed.


#### Ports

Check port information, obtained by ONOS by performing a gNMI Get RPC for the
OpenConfig Interfaces model:

```
onos> ports -s device:spine1
id=device:spine1, available=true, role=MASTER, type=SWITCH, driver=stratum-bmv2:org.onosproject.ngsdn-tutorial
  port=[spine1-eth1](1), state=enabled, type=copper, speed=10000 , ...
  port=[spine1-eth2](2), state=enabled, type=copper, speed=10000 , ...
```

Check port statistics, also obtained by querying the OpenConfig Interfaces model
via gNMI:

```
onos> portstats device:spine1
deviceId=device:spine1
   port=[spine1-eth1](1), pktRx=114, pktTx=114, bytesRx=14022, bytesTx=14136, pktRxDrp=0, pktTxDrp=0, Dur=173
   port=[spine1-eth2](2), pktRx=114, pktTx=114, bytesRx=14022, bytesTx=14136, pktRxDrp=0, pktTxDrp=0, Dur=173

```

#### Links

Verify that all links have been discovered. You should see 8 links in total:

FIXME

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

**If you don't see any link**, check the ONOS log for any error with
packet-in/out handling. In case of errors, it's possible that you have not
modified `InterpreterImpl.java` correctly. In this case, kill the ONOS
container (`make reset`) and go back to exercise step 1.

**Note:** in theory, there should be no need to kill and restart ONOS. However,
while ONOS supports reloading apps with a modified one, the version of ONOS used
in this tutorial (2.2.0, the most recent at the time of writing) does not
support reloading *pipeconf behavior classes*, as the old classes will still be
used. For this reason, to reload a modified version of `InterpreterImpl.java`,
you need to kill ONOS first.

#### Flow rules and groups

Check the ONOS flow rules, you should see 12 flow rules for each device. For
example, to show all flow rules installed so far on device `leaf1`:

```
onos> flows -s any device:leaf1
deviceId=device:leaf1, flowRuleCount=12
    ADDED, bytes=0, packets=0, table=IngressPipeImpl.acl_table, priority=40000, selector=[ETH_TYPE:arp], treatment=[immediate=[IngressPipeImpl.clone_to_cpu()]]
    ADDED, bytes=3596, packets=29, table=IngressPipeImpl.acl_table, priority=40000, selector=[ETH_TYPE:lldp], treatment=[immediate=[IngressPipeImpl.clone_to_cpu()]]
    ADDED, bytes=0, packets=0, table=IngressPipeImpl.acl_table, priority=40000, selector=[ETH_TYPE:ipv6, IP_PROTO:58, ICMPV6_TYPE:136], treatment=[immediate=[IngressPipeImpl.clone_to_cpu()]]
    ADDED, bytes=0, packets=0, table=IngressPipeImpl.acl_table, priority=40000, selector=[ETH_TYPE:ipv6, IP_PROTO:58, ICMPV6_TYPE:135], treatment=[immediate=[IngressPipeImpl.clone_to_cpu()]]
    ADDED, bytes=3596, packets=29, table=IngressPipeImpl.acl_table, priority=40000, selector=[ETH_TYPE:bddp], treatment=[immediate=[IngressPipeImpl.clone_to_cpu()]]
    ADDED, bytes=0, packets=0, table=IngressPipeImpl.l2_exact_table, priority=10, selector=[hdr.ethernet.dst_addr=0xbb00000001], treatment=[immediate=[IngressPipeImpl.set_egress_port(port_num=0x1)]]
    ADDED, bytes=0, packets=0, table=IngressPipeImpl.l2_exact_table, priority=10, selector=[hdr.ethernet.dst_addr=0xbb00000002], treatment=[immediate=[IngressPipeImpl.set_egress_port(port_num=0x2)]]
    ADDED, bytes=0, packets=0, table=IngressPipeImpl.l2_ternary_table, priority=10, selector=[hdr.ethernet.dst_addr=0x333300000000&&&0xffff00000000], treatment=[immediate=[IngressPipeImpl.set_multicast_group(gid=0xff)]]
    ADDED, bytes=3596, packets=29, table=IngressPipeImpl.l2_ternary_table, priority=10, selector=[hdr.ethernet.dst_addr=0xffffffffffff&&&0xffffffffffff], treatment=[immediate=[IngressPipeImpl.set_multicast_group(gid=0xff)]]
    ADDED, bytes=0, packets=0, table=IngressPipeImpl.my_station_table, priority=10, selector=[hdr.ethernet.dst_addr=0xaa00000001], treatment=[immediate=[NoAction()]]
    ADDED, bytes=0, packets=0, table=IngressPipeImpl.routing_v6_table, priority=10, selector=[hdr.ipv6.dst_addr=0x20010002000400000000000000000000/64], treatment=[immediate=[GROUP:0xec3b0000]]
    ADDED, bytes=0, packets=0, table=IngressPipeImpl.routing_v6_table, priority=10, selector=[hdr.ipv6.dst_addr=0x20010002000300000000000000000000/64], treatment=[immediate=[GROUP:0xec3b0000]]

```

This list include flow rules installed by the ONOS built-in apps as well as our
custom app. To check which flow rules come from the built-in apps, you can
`grep` the output of the `flows` command using the app ID
`appId=org.onosproject.core`:

```
onos> flows any device:leaf1 | grep appId=org.onosproject.core
    id=100001e5fba59, state=ADDED, bytes=0, packets=0, duration=355, liveType=UNKNOWN, priority=40000, tableId=IngressPipeImpl.acl_table, appId=org.onosproject.core, selector=[ETH_TYPE:arp], treatment=DefaultTrafficTreatment{immediate=[IngressPipeImpl.clone_to_cpu()], ...}
    id=10000217b5edd, state=ADDED, bytes=28644, packets=231, duration=355, liveType=UNKNOWN, priority=40000, tableId=IngressPipeImpl.acl_table, appId=org.onosproject.core, selector=[ETH_TYPE:lldp], treatment=DefaultTrafficTreatment{immediate=[IngressPipeImpl.clone_to_cpu()], ...}
    id=1000039959d4d, state=ADDED, bytes=0, packets=0, duration=355, liveType=UNKNOWN, priority=40000, tableId=IngressPipeImpl.acl_table, appId=org.onosproject.core, selector=[ETH_TYPE:ipv6, IP_PROTO:58, ICMPV6_TYPE:136], treatment=DefaultTrafficTreatment{immediate=[IngressPipeImpl.clone_to_cpu()], ...}
    id=1000078c06d68, state=ADDED, bytes=0, packets=0, duration=355, liveType=UNKNOWN, priority=40000, tableId=IngressPipeImpl.acl_table, appId=org.onosproject.core, selector=[ETH_TYPE:ipv6, IP_PROTO:58, ICMPV6_TYPE:135], treatment=DefaultTrafficTreatment{immediate=[IngressPipeImpl.clone_to_cpu()], ...}
    id=10000d1887c0b, state=ADDED, bytes=28644, packets=231, duration=356, liveType=UNKNOWN, priority=40000, tableId=IngressPipeImpl.acl_table, appId=org.onosproject.core, selector=[ETH_TYPE:bddp], treatment=DefaultTrafficTreatment{immediate=[IngressPipeImpl.clone_to_cpu()], ...}
```

These rules are the result of the translation of flow objectives generated
automatically for each device by the `hostprovider` and `lldpprovider` apps.

The `hostprovider` app provides host discovery capabilities by sniffing ARP
(`selector=[ETH_TYPE:arp]`) and NDP packets (`selector=[ETH_TYPE:ipv6,
IP_PROTO:58, ICMPV6_TYPE:...]`), which are cloned to the controller
(`treatment=[immediate=[IngressPipeImpl.clone_to_cpu()]]`). Similarly,
`lldpprovider` generates flow objectives to sniff LLDP and BBDP packets
(`selector=[ETH_TYPE:lldp]` and `selector=[ETH_TYPE:bbdp]`) periodically emitted
on all devices' ports as P4Runtime packet-outs, allowing automatic link
discovery.

Flow objectives are translated to flow rules and groups by the pipeconf, which
provides a `Pipeliner` behavior implementation
([PipelinerImpl.java][PipelinerImpl.java]). Moreover, these flow rules specify a
match key by using ONOS standard/known header fields (or "Criteria" using ONOS
terminology), such as `ETH_TYPE`, `ICMPV6_TYPE`, etc.  These types are mapped to
P4Info-specific match fields by the same pipeline interpreter modified before
[InterpreterImpl.java][InterpreterImpl.java] (look for method
`mapCriterionType`)

To show all groups installed so far, you can use the `groups` command. For
example to show groups on `leaf1`:
```
onos> groups any device:leaf1
deviceId=device:leaf1, groupCount=3
   id=0xec3b0000, state=ADDED, type=SELECT, bytes=0, packets=0, appId=org.onosproject.ngsdn-tutorial, referenceCount=0
       id=0xec3b0000, bucket=1, bytes=0, packets=0, weight=1, actions=[IngressPipeImpl.set_next_hop(dmac=0xbb00000002)]
       id=0xec3b0000, bucket=2, bytes=0, packets=0, weight=1, actions=[IngressPipeImpl.set_next_hop(dmac=0xbb00000001)]
   id=0x63, state=ADDED, type=CLONE, bytes=0, packets=0, appId=org.onosproject.core, referenceCount=0
       id=0x63, bucket=1, bytes=0, packets=0, weight=-1, actions=[OUTPUT:CONTROLLER]
   id=0xff, state=ADDED, type=ALL, bytes=0, packets=0, appId=org.onosproject.ngsdn-tutorial, referenceCount=0
       id=0xff, bucket=1, bytes=0, packets=0, weight=-1, actions=[OUTPUT:3]
       id=0xff, bucket=2, bytes=0, packets=0, weight=-1, actions=[OUTPUT:4]
       id=0xff, bucket=3, bytes=0, packets=0, weight=-1, actions=[OUTPUT:5]
       id=0xff, bucket=4, bytes=0, packets=0, weight=-1, actions=[OUTPUT:6]
```

"Group" is an ONOS northbound abstraction that is mapped internally to different
types of P4Runtime entities. In this case you should see 3 groups of 3 different
types.

* `SELECT`: mapped to a P4Runtime `ActionProfileGroup` and
  `ActionProfileMember`. This specific group is created by the app's
  `Ipv6RoutingComponent.java` and installed in the P4 `routing_v6_table` to
  provide ECMP hashing to the spines.
* `CLONE`: mapped to a P4Runtime `CloneSessionEntry`, here used to clone
  packets to the controller via packet-in. Note that the `id=0x63` is the same
  as `#define CPU_CLONE_SESSION_ID 99` in the P4 program. This ID is hardcoded
  in the pipeconf code, as the group is created by `InterpreterImpl.java` in
  response to flow objectives mapped to the ACL table and requesting to clone
  packets such as NDP and LLDP.
* `ALL`: mapped to a P4Runtime `MulticastGroupEntry`. In this case used to
  broadcast NDP NS packets to all host-facing ports. This group is installed by
  `L2BridgingComponent.java`, and is used by an entry in the P4
  `l2_ternary_table` (look for a flow rule with
  `treatment=[immediate=[IngressPipeImpl.set_multicast_group(gid=0xff)]`)

### 6. Test ping between hosts

Now that the app has been loaded, you should be able to repeat the same ping
test done in exercise 1:

```
mininet> h1a ping h1b
PING 2001:1:1::b(2001:1:1::b) 56 data bytes
64 bytes from 2001:1:1::b: icmp_seq=1 ttl=64 time=1068 ms
64 bytes from 2001:1:1::b: icmp_seq=2 ttl=64 time=5.38 ms
64 bytes from 2001:1:1::b: icmp_seq=3 ttl=64 time=1.75 ms
...
```

Differently from exercise 1, here we have NOT set any NDP static entry. Instead,
NDP NS and NA packets are handled by the data plane thanks to the `ALL` group
and `l2_ternary_table`'s flow rule described above. Moreover, given the ACL flow
rules to clone NDP packets to the controller, hosts can be discovered by ONOS.
Host discovery events are used by `L2BridgingComponent.java` to insert entries
in the P4 `l2_exact_table`to enable forwarding between hosts in the same subnet.

Check the ONOS log (`make onos-log`). You should see messages related to the
discovery of hosts `h1a` and `h1b`:

```
INFO  [L2BridgingComponent] HOST_ADDED event! host=00:00:00:00:00:1A/None, deviceId=device:leaf1, port=3
INFO  [L2BridgingComponent] Adding L2 unicast rule on device:leaf1 for host 00:00:00:00:00:1A/None (port 3)...
...
INFO  [L2BridgingComponent] HOST_ADDED event! host=00:00:00:00:00:1B/None, deviceId=device:leaf1, port=4
INFO  [L2BridgingComponent] Adding L2 unicast rule on device:leaf1 for host 00:00:00:00:00:1B/None (port 4)...
```

### 7. Visualize the topology on the ONOS web UI

Open a browser from within the tutorial VM (e.g. Firefox) to
<http://127.0.0.1:8181/onos/ui>. When asked, use the username `onos` and password
`rocks`.

While here, feel free to interact with and discover the ONOS UI. For more
information on how to use the ONOS web UI please refer to this guide:

<https://wiki.onosproject.org/x/OYMg>

On the same page where the ONOS topology view is shown:
* Press `H` on your keyboard to show hosts;
* Press `L` to show device labels;
* Press `A` multiple times until you see link stats, in either 
  packets/seconds (pps) or bits/seconds.

Link stats are derived by ONOS by periodically obtaining the port counters for
each device. ONOS internally uses gNMI to read port information, including
counters.

### Congratulations!

You have completed the third exercise! If there is still time before the end of
this session, you can check the bonus steps below.

### Bonus: inspect stratum_bmv2 internal state

You can use the P4Runtime shell to dump all table entries currently
installed on the switch by ONOS. On a separate terminal window type, start a
P4Runtime shell for leaf1:

```
$ util/p4rt-sh --grpc-addr localhost:50001 --election-id 0,1
```

On the shell prompt, type the following command to dump all entries from the ACL
table:

```
P4Runtime sh >>> for te in table_entry["IngressPipeImpl.acl_table"].read(): 
            ...:     print(te) 
            ...:       
```

You should see exactly 5 entries, each one corresponding to a flow rule
in ONOS. For example, the flow rule matching on NDP NS packets should look
like this in the P4runtime shell:

```
table_id: 33557865 ("IngressPipeImpl.acl_table")
match {
  field_id: 4 ("hdr.ethernet.ether_type")
  ternary {
    value: "\\x86\\xdd"
    mask: "\\xff\\xff"
  }
}
match {
  field_id: 5 ("hdr.ipv6.next_hdr")
  ternary {
    value: "\\x3a"
    mask: "\\xff"
  }
}
match {
  field_id: 6 ("hdr.icmpv6.type")
  ternary {
    value: "\\x87"
    mask: "\\xff"
  }
}
action {
  action {
    action_id: 16782152 ("IngressPipeImpl.clone_to_cpu")
  }
}
priority: 40001
```

### Bonus: show ONOS gRPC log

ONOS provides a debugging feature that allow dumping to file all gRPC messages
exchanged with a device. To enable this feature, type the following command in
the ONOS CLI (`make onos-cli`):

```
onos> cfg set org.onosproject.grpc.ctl.GrpcChannelControllerImpl enableMessageLog true
```

Check the content of directory `tmp/onos` in the `ngsdn-tutorial` root. You
should see many files, some of which starting with name `grpc___mininet_`. You
should see 4 of such files in total, one file per device, named after the gRPC
port used to establish the gRPC chanel.

Check content of one of these files, you should see a dump of the gRPC messages
in Protobuf Text format for messages like:

* P4Runtime `PacketIn` and `PacketOut`;
* P4Runtime Read RPCs used to periodically dump table entries and read counters;
* gNMI Get RPCs to read port counters.

Remember to disable the gRPC message logging in ONOS when you're done, to avoid
affecting performances:

```
onos> cfg set org.onosproject.grpc.ctl.GrpcChannelControllerImpl enableMessageLog false
```

[PipeconfLoader.java]: app/src/main/java/org/onosproject/ngsdn/tutorial/pipeconf/PipeconfLoader.java
[InterpreterImpl.java]: app/src/main/java/org/onosproject/ngsdn/tutorial/pipeconf/InterpreterImpl.java
[PipelinerImpl.java]: app/src/main/java/org/onosproject/ngsdn/tutorial/pipeconf/PipelinerImpl.java