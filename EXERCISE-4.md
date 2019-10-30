# Exercise 4: Enabling link discovery via P4Runtime packet I/O

In this exercise, you will be asked to integrate the ONOS built-in link discovery
service with your P4 program. ONOS performs link discovery by using controller
packet-in/out. To make this work, you will need to apply simple changes to the
starter P4 code, validate the P4 changes using PTF-based data plane unit tests,
and finally, apply changes to the pipeconf Java implementation to enable ONOS's
built-in apps use the packet-in/out support provided by your P4 implementation.

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
* Skip ingress pipeline processing for packet-outs and set the egress port to
  the one specified in the `cpu_out` header
* Provide an ACL table with ternary match fields and an action to clone
  packets to the CPU port (used to generate a packet-ins)

One piece is missing to provide complete packet-in support, and you have to modify
the P4 program to implement it:

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

### 4. Restart ONOS and load updated pipeconf

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

### 3. Push netcfg to ONOS to trigger device and link discovery

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

In this case, you should see ~1 packet/s, as that's the rate of packet-outs
generated by the `lldpprovider` app.

### Congratulations!

You have completed the fourth exercise!
