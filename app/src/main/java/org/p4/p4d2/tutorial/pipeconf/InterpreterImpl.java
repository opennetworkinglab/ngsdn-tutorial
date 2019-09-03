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

package org.p4.p4d2.tutorial.pipeconf;

import com.google.common.collect.ImmutableList;
import com.google.common.collect.ImmutableMap;
import org.onlab.packet.DeserializationException;
import org.onlab.packet.Ethernet;
import org.onlab.util.ImmutableByteSequence;
import org.onosproject.net.ConnectPoint;
import org.onosproject.net.DeviceId;
import org.onosproject.net.Port;
import org.onosproject.net.PortNumber;
import org.onosproject.net.device.DeviceService;
import org.onosproject.net.driver.AbstractHandlerBehaviour;
import org.onosproject.net.flow.TrafficTreatment;
import org.onosproject.net.flow.criteria.Criterion;
import org.onosproject.net.packet.DefaultInboundPacket;
import org.onosproject.net.packet.InboundPacket;
import org.onosproject.net.packet.OutboundPacket;
import org.onosproject.net.pi.model.PiMatchFieldId;
import org.onosproject.net.pi.model.PiPacketMetadataId;
import org.onosproject.net.pi.model.PiPipelineInterpreter;
import org.onosproject.net.pi.model.PiTableId;
import org.onosproject.net.pi.runtime.PiAction;
import org.onosproject.net.pi.runtime.PiPacketMetadata;
import org.onosproject.net.pi.runtime.PiPacketOperation;

import java.nio.ByteBuffer;
import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static java.lang.String.format;
import static java.util.stream.Collectors.toList;
import static org.onlab.util.ImmutableByteSequence.copyFrom;
import static org.onosproject.net.PortNumber.CONTROLLER;
import static org.onosproject.net.PortNumber.FLOOD;
import static org.onosproject.net.flow.instructions.Instruction.Type.OUTPUT;
import static org.onosproject.net.flow.instructions.Instructions.OutputInstruction;
import static org.onosproject.net.pi.model.PiPacketOperationType.PACKET_OUT;
import static org.p4.p4d2.tutorial.AppConstants.CPU_PORT_ID;


/**
 * Interpreter implementation.
 */
public class InterpreterImpl extends AbstractHandlerBehaviour
        implements PiPipelineInterpreter {


    // From v1model.p4
    private static final int V1MODEL_PORT_BITWIDTH = 9;

    // From P4Info.
    private static final Map<Criterion.Type, String> CRITERION_MAP =
            new ImmutableMap.Builder<Criterion.Type, String>()
                    .put(Criterion.Type.IN_PORT, "standard_metadata.ingress_port")
                    .put(Criterion.Type.ETH_DST, "hdr.ethernet.dst_addr")
                    .put(Criterion.Type.ETH_SRC, "hdr.ethernet.src_addr")
                    .put(Criterion.Type.ETH_TYPE, "hdr.ethernet.ether_type")
                    .put(Criterion.Type.IPV6_DST, "hdr.ipv6.dst_addr")
                    .put(Criterion.Type.IP_PROTO, "local_metadata.ip_proto")
                    .put(Criterion.Type.ICMPV4_TYPE, "local_metadata.icmp_type")
                    .put(Criterion.Type.ICMPV6_TYPE, "local_metadata.icmp_type")
                    .build();

    /**
     * Returns a collection of PI packet operations populated with metadata
     * specific for this pipeconf and equivalent to the given ONOS
     * OutboundPacket instance.
     *
     * @param packet ONOS OutboundPacket
     * @return collection of PI packet operations
     * @throws PiInterpreterException if the packet treatments cannot be
     *                                executed by this pipeline
     */
    @Override
    public Collection<PiPacketOperation> mapOutboundPacket(OutboundPacket packet)
            throws PiInterpreterException {
        TrafficTreatment treatment = packet.treatment();

        // Packet-out in main.p4 supports only setting the output port,
        // i.e. we only understand OUTPUT instructions.
        List<OutputInstruction> outInstructions = treatment
                .allInstructions()
                .stream()
                .filter(i -> i.type().equals(OUTPUT))
                .map(i -> (OutputInstruction) i)
                .collect(toList());

        if (treatment.allInstructions().size() != outInstructions.size()) {
            // There are other instructions that are not of type OUTPUT.
            throw new PiInterpreterException("Treatment not supported: " + treatment);
        }

        ImmutableList.Builder<PiPacketOperation> builder = ImmutableList.builder();
        for (OutputInstruction outInst : outInstructions) {
            if (outInst.port().isLogical() && !outInst.port().equals(FLOOD)) {
                throw new PiInterpreterException(format(
                        "Packet-out on logical port '%s' not supported",
                        outInst.port()));
            } else if (outInst.port().equals(FLOOD)) {
                // To emulate flooding, we create a packet-out operation for
                // each switch port.
                final DeviceService deviceService = handler().get(DeviceService.class);
                for (Port port : deviceService.getPorts(packet.sendThrough())) {
                    builder.add(buildPacketOut(packet.data(), port.number().toLong()));
                }
            } else {
                // Create only one packet-out for the given OUTPUT instruction.
                builder.add(buildPacketOut(packet.data(), outInst.port().toLong()));
            }
        }
        return builder.build();
    }

    /**
     * Builds a pipeconf-specific packet-out instance with the given payload and
     * egress port.
     *
     * @param pktData    packet payload
     * @param portNumber egress port
     * @return packet-out
     * @throws PiInterpreterException if packet-out cannot be built
     */
    private PiPacketOperation buildPacketOut(ByteBuffer pktData, long portNumber)
            throws PiInterpreterException {

        // Make sure port number can fit in v1model port metadata bitwidth.
        final ImmutableByteSequence portBytes;
        try {
            portBytes = copyFrom(portNumber).fit(V1MODEL_PORT_BITWIDTH);
        } catch (ImmutableByteSequence.ByteSequenceTrimException e) {
            throw new PiInterpreterException(format(
                    "Port number %d too big, %s", portNumber, e.getMessage()));
        }

        // Create metadata instance for egress port.
        // TODO EXERCISE 1: modify metadata names to match P4 program
        // ---- START SOLUTION ----
        final String outPortMetadataName = "egress_port";
        // ---- END SOLUTION ----
        final PiPacketMetadata outPortMetadata = PiPacketMetadata.builder()
                .withId(PiPacketMetadataId.of(outPortMetadataName))
                .withValue(portBytes)
                .build();

        // Build packet out.
        return PiPacketOperation.builder()
                .withType(PACKET_OUT)
                .withData(copyFrom(pktData))
                .withMetadata(outPortMetadata)
                .build();
    }

    /**
     * Returns an ONS InboundPacket equivalent to the given pipeconf-specific
     * packet-in operation.
     *
     * @param packetIn packet operation
     * @param deviceId ID of the device that originated the packet-in
     * @return inbound packet
     * @throws PiInterpreterException if the packet operation cannot be mapped
     *                                to an inbound packet
     */
    @Override
    public InboundPacket mapInboundPacket(PiPacketOperation packetIn, DeviceId deviceId)
            throws PiInterpreterException {

        // Find the ingress_port metadata.
        // TODO EXERCISE 1: modify metadata names to match P4 program
        // ---- START SOLUTION ----
        final String inportMetadataName = "ingress_port";
        // ---- END SOLUTION ----
        Optional<PiPacketMetadata> inportMetadata = packetIn.metadatas()
                .stream()
                .filter(meta -> meta.id().id().equals(inportMetadataName))
                .findFirst();

        if (!inportMetadata.isPresent()) {
            throw new PiInterpreterException(format(
                    "Missing metadata '%s' in packet-in received from '%s': %s",
                    inportMetadataName, deviceId, packetIn));
        }

        // Build ONOS InboundPacket instance with the given ingress port.

        // 1. Parse packet-in object into Ethernet packet instance.
        final byte[] payloadBytes = packetIn.data().asArray();
        final ByteBuffer rawData = ByteBuffer.wrap(payloadBytes);
        final Ethernet ethPkt;
        try {
            ethPkt = Ethernet.deserializer().deserialize(
                    payloadBytes, 0, packetIn.data().size());
        } catch (DeserializationException dex) {
            throw new PiInterpreterException(dex.getMessage());
        }

        // 2. Get ingress port
        final ImmutableByteSequence portBytes = inportMetadata.get().value();
        final short portNum = portBytes.asReadOnlyBuffer().getShort();
        final ConnectPoint receivedFrom = new ConnectPoint(
                deviceId, PortNumber.portNumber(portNum));

        return new DefaultInboundPacket(receivedFrom, ethPkt, rawData);
    }

    @Override
    public Optional<Integer> mapLogicalPortNumber(PortNumber port) {
        if (CONTROLLER.equals(port)) {
            return Optional.of(CPU_PORT_ID);
        } else {
            return Optional.empty();
        }
    }

    @Override
    public Optional<PiMatchFieldId> mapCriterionType(Criterion.Type type) {
        if (CRITERION_MAP.containsKey(type)) {
            return Optional.of(PiMatchFieldId.of(CRITERION_MAP.get(type)));
        } else {
            return Optional.empty();
        }
    }

    @Override
    public PiAction mapTreatment(TrafficTreatment treatment, PiTableId piTableId)
            throws PiInterpreterException {
        throw new PiInterpreterException("Treatment mapping not supported");
    }

    @Override
    public Optional<PiTableId> mapFlowRuleTableId(int flowRuleTableId) {
        return Optional.empty();
    }
}
