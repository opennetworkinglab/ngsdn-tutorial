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

package org.p4.p4d2.tutorial;

import com.google.common.collect.Lists;
import org.onlab.packet.Ip6Address;
import org.onlab.packet.Ip6Prefix;
import org.onlab.packet.IpAddress;
import org.onlab.packet.IpPrefix;
import org.onlab.packet.MacAddress;
import org.onlab.util.ItemNotFoundException;
import org.onosproject.core.ApplicationId;
import org.onosproject.mastership.MastershipService;
import org.onosproject.net.Device;
import org.onosproject.net.DeviceId;
import org.onosproject.net.Host;
import org.onosproject.net.Link;
import org.onosproject.net.PortNumber;
import org.onosproject.net.config.NetworkConfigService;
import org.onosproject.net.device.DeviceEvent;
import org.onosproject.net.device.DeviceListener;
import org.onosproject.net.device.DeviceService;
import org.onosproject.net.flow.FlowRule;
import org.onosproject.net.flow.FlowRuleService;
import org.onosproject.net.flow.criteria.PiCriterion;
import org.onosproject.net.group.GroupDescription;
import org.onosproject.net.group.GroupService;
import org.onosproject.net.host.HostEvent;
import org.onosproject.net.host.HostListener;
import org.onosproject.net.host.HostService;
import org.onosproject.net.host.InterfaceIpAddress;
import org.onosproject.net.intf.Interface;
import org.onosproject.net.intf.InterfaceService;
import org.onosproject.net.link.LinkEvent;
import org.onosproject.net.link.LinkListener;
import org.onosproject.net.link.LinkService;
import org.onosproject.net.pi.model.PiActionId;
import org.onosproject.net.pi.model.PiActionParamId;
import org.onosproject.net.pi.model.PiMatchFieldId;
import org.onosproject.net.pi.runtime.PiAction;
import org.onosproject.net.pi.runtime.PiActionParam;
import org.onosproject.net.pi.runtime.PiActionProfileGroupId;
import org.onosproject.net.pi.runtime.PiTableAction;
import org.osgi.service.component.annotations.Activate;
import org.osgi.service.component.annotations.Component;
import org.osgi.service.component.annotations.Deactivate;
import org.osgi.service.component.annotations.Reference;
import org.osgi.service.component.annotations.ReferenceCardinality;
import org.p4.p4d2.tutorial.common.Srv6DeviceConfig;
import org.p4.p4d2.tutorial.common.Utils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Collection;
import java.util.Collections;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.stream.Collectors;

import static com.google.common.collect.Streams.stream;
import static org.p4.p4d2.tutorial.AppConstants.INITIAL_SETUP_DELAY;

/**
 * App component that configures devices to provide IPv6 routing capabilities
 * across the whole fabric.
 */
@Component(
        immediate = true,
        enabled = true
)
public class Ipv6RoutingComponent {

    private static final Logger log = LoggerFactory.getLogger(Ipv6RoutingComponent.class);

    private static final int DEFAULT_ECMP_GROUP_ID = 0xec3b0000;
    private static final long GROUP_INSERT_DELAY_MILLIS = 200;

    private final HostListener hostListener = new InternalHostListener();
    private final LinkListener linkListener = new InternalLinkListener();
    private final DeviceListener deviceListener = new InternalDeviceListener();

    private ApplicationId appId;

    //--------------------------------------------------------------------------
    // ONOS CORE SERVICE BINDING
    //
    // These variables are set by the Karaf runtime environment before calling
    // the activate() method.
    //--------------------------------------------------------------------------

    @Reference(cardinality = ReferenceCardinality.MANDATORY)
    private FlowRuleService flowRuleService;

    @Reference(cardinality = ReferenceCardinality.MANDATORY)
    private HostService hostService;

    @Reference(cardinality = ReferenceCardinality.MANDATORY)
    private MastershipService mastershipService;

    @Reference(cardinality = ReferenceCardinality.MANDATORY)
    private GroupService groupService;

    @Reference(cardinality = ReferenceCardinality.MANDATORY)
    private DeviceService deviceService;

    @Reference(cardinality = ReferenceCardinality.MANDATORY)
    private NetworkConfigService networkConfigService;

    @Reference(cardinality = ReferenceCardinality.MANDATORY)
    private InterfaceService interfaceService;

    @Reference(cardinality = ReferenceCardinality.MANDATORY)
    private LinkService linkService;

    @Reference(cardinality = ReferenceCardinality.MANDATORY)
    private MainComponent mainComponent;

    //--------------------------------------------------------------------------
    // COMPONENT ACTIVATION.
    //
    // When loading/unloading the app the Karaf runtime environment will call
    // activate()/deactivate().
    //--------------------------------------------------------------------------

    @Activate
    protected void activate() {
        appId = mainComponent.getAppId();

        hostService.addListener(hostListener);
        linkService.addListener(linkListener);
        deviceService.addListener(deviceListener);

        // Schedule set up for all devices.
        mainComponent.scheduleTask(this::setUpAllDevices, INITIAL_SETUP_DELAY);

        log.info("Started");
    }

    @Deactivate
    protected void deactivate() {
        hostService.removeListener(hostListener);
        linkService.removeListener(linkListener);
        deviceService.removeListener(deviceListener);

        log.info("Stopped");
    }

    //--------------------------------------------------------------------------
    // METHODS TO COMPLETE.
    //
    // Complete the implementation wherever you see TODO.
    //--------------------------------------------------------------------------

    /**
     * Sets up the "My Station" table for the given device using the
     * myStationMac address found in the config.
     * <p>
     * This method will be called at component activation for each device
     * (switch) known by ONOS, and every time a new device-added event is
     * captured by the InternalDeviceListener defined below.
     *
     * @param deviceId the device ID
     */
    private void setUpMyStationTable(DeviceId deviceId) {

        log.info("Adding My Station rules to {}...", deviceId);

        final MacAddress myStationMac = getMyStationMac(deviceId);

        // HINT: in our solution, the My Station table matches on the *ethernet
        // destination* and there is only one action called *NoAction*, which is
        // used as an indication of "table hit" in the control block.

        // TODO EXERCISE 3
        // Modify P4Runtime entity names to match content of P4Info file (look
        // for the fully qualified name of tables, match fields, and actions.
        // ---- START SOLUTION ----
        final String tableId = "IngressPipeImpl.l2_my_station";

        final PiCriterion match = PiCriterion.builder()
                .matchExact(
                        PiMatchFieldId.of("hdr.ethernet.dst_addr"),
                        myStationMac.toBytes())
                .build();

        // Creates an action which do *NoAction* when hit.
        final PiTableAction action = PiAction.builder()
                .withId(PiActionId.of("NoAction"))
                .build();
        // ---- END SOLUTION ----

        final FlowRule myStationRule = Utils.buildFlowRule(
                deviceId, appId, tableId, match, action);

        flowRuleService.applyFlowRules(myStationRule);
    }

    /**
     * Creates an ONOS SELECT group for the routing table to provide ECMP
     * forwarding for the given collection of next hop MAC addresses. ONOS
     * SELECT groups are equivalent to P4Runtime action selector groups.
     * <p>
     * This method will be called by the routing policy methods below to insert
     * groups in the L3 table
     *
     * @param nextHopMacs the collection of mac addresses of next hops
     * @param deviceId    the device where the group will be installed
     * @return a SELECT group
     */
    private GroupDescription createNextHopGroup(int groupId,
                                                Collection<MacAddress> nextHopMacs,
                                                DeviceId deviceId) {

        String actionProfileId = "IngressPipeImpl.ecmp_selector";

        final List<PiAction> actions = Lists.newArrayList();

        // Build one "set next hop" action for each next hop
        // TODO EXERCISE 3
        // Modify P4Runtime entity names to match content of P4Info file (look
        // for the fully qualified name of tables, match fields, and actions.
        // ---- START SOLUTION ----
        final String tableId = "IngressPipeImpl.l3_table";
        for (MacAddress nextHopMac : nextHopMacs) {
            final PiAction action = PiAction.builder()
                    .withId(PiActionId.of("IngressPipeImpl.set_l2_next_hop"))
                    .withParameter(new PiActionParam(
                            // Action param name.
                            PiActionParamId.of("dmac"),
                            // Action param value.
                            nextHopMac.toBytes()))
                    .build();

            actions.add(action);
        }
        // ---- END SOLUTION ----

        return Utils.buildSelectGroup(
                deviceId, tableId, actionProfileId, groupId, actions, appId);
    }

    /**
     * Creates a routing flow rule that matches on the given IPv6 prefix and
     * executes the given group ID (created before).
     *
     * @param deviceId  the device where flow rule will be installed
     * @param ip6Prefix the IPv6 prefix
     * @param groupId   the group ID
     * @return a flow rule
     */
    private FlowRule createRoutingRule(DeviceId deviceId, Ip6Prefix ip6Prefix,
                                       int groupId) {

        // TODO EXERCISE 3
        // Modify P4Runtime entity names to match content of P4Info file (look
        // for the fully qualified name of tables, match fields, and actions.
        // ---- START SOLUTION ----
        final String tableId = "IngressPipeImpl.l3_table";
        final PiCriterion match = PiCriterion.builder()
                .matchLpm(
                        PiMatchFieldId.of("hdr.ipv6.dst_addr"),
                        ip6Prefix.address().toOctets(),
                        ip6Prefix.prefixLength())
                .build();

        final PiTableAction action = PiActionProfileGroupId.of(groupId);
        // ---- END SOLUTION ----

        return Utils.buildFlowRule(
                deviceId, appId, tableId, match, action);
    }

    /**
     * Creates a flow rule for the L2 table mapping the given next hop MAC to
     * the given output port.
     * <p>
     * This is called by the routing policy methods below to establish L2-based
     * forwarding inside the fabric, e.g., when deviceId is a leaf switch and
     * nextHopMac is the one of a spine switch.
     *
     * @param deviceId   the device
     * @param nexthopMac the next hop (destination) mac
     * @param outPort    the output port
     */
    private FlowRule createL2NextHopRule(DeviceId deviceId, MacAddress nexthopMac,
                                         PortNumber outPort) {

        // TODO EXERCISE 3
        // Modify P4Runtime entity names to match content of P4Info file (look
        // for the fully qualified name of tables, match fields, and actions.
        // ---- START SOLUTION ----
        final String tableId = "IngressPipeImpl.l2_exact_table";
        final PiCriterion match = PiCriterion.builder()
                .matchExact(PiMatchFieldId.of("hdr.ethernet.dst_addr"),
                            nexthopMac.toBytes())
                .build();


        final PiAction action = PiAction.builder()
                .withId(PiActionId.of("IngressPipeImpl.set_output_port"))
                .withParameter(new PiActionParam(
                        PiActionParamId.of("port_num"),
                        outPort.toLong()))
                .build();
        // ---- END SOLUTION ----

        return Utils.buildFlowRule(
                deviceId, appId, tableId, match, action);
    }

    //--------------------------------------------------------------------------
    // EVENT LISTENERS
    //
    // Events are processed only if isRelevant() returns true.
    //--------------------------------------------------------------------------

    /**
     * Listener of host events which triggers configuration of routing rules on
     * the device where the host is attached.
     */
    class InternalHostListener implements HostListener {

        @Override
        public boolean isRelevant(HostEvent event) {
            switch (event.type()) {
                case HOST_ADDED:
                    break;
                case HOST_REMOVED:
                case HOST_UPDATED:
                case HOST_MOVED:
                default:
                    // Ignore other events.
                    // Food for thoughts:
                    // how to support host moved/removed events?
                    return false;
            }
            // Process host event only if this controller instance is the master
            // for the device where this host is attached.
            final Host host = event.subject();
            final DeviceId deviceId = host.location().deviceId();
            return mastershipService.isLocalMaster(deviceId);
        }

        @Override
        public void event(HostEvent event) {
            Host host = event.subject();
            DeviceId deviceId = host.location().deviceId();
            mainComponent.getExecutorService().execute(() -> {
                log.info("{} event! host={}, deviceId={}, port={}",
                         event.type(), host.id(), deviceId, host.location().port());
                setUpHostRules(deviceId, host);
            });
        }
    }

    /**
     * Listener of link events, which triggers configuration of routing rules to
     * forward packets across the fabric, i.e. from leaves to spines and vice
     * versa.
     * <p>
     * Reacting to link events instead of device ones, allows us to make sure
     * all device are always configured with a topology view that includes all
     * links, e.g. modifying an ECMP group as soon as a new link is added. The
     * downside is that we might be configuring the same device twice for the
     * same set of links/paths. However, the ONOS core treats these cases as a
     * no-op when the device is already configured with the desired forwarding
     * state (i.e. flows and groups)
     */
    class InternalLinkListener implements LinkListener {

        @Override
        public boolean isRelevant(LinkEvent event) {
            switch (event.type()) {
                case LINK_ADDED:
                    break;
                case LINK_UPDATED:
                case LINK_REMOVED:
                default:
                    return false;
            }
            DeviceId srcDev = event.subject().src().deviceId();
            DeviceId dstDev = event.subject().dst().deviceId();
            return mastershipService.isLocalMaster(srcDev) ||
                    mastershipService.isLocalMaster(dstDev);
        }

        @Override
        public void event(LinkEvent event) {
            DeviceId srcDev = event.subject().src().deviceId();
            DeviceId dstDev = event.subject().dst().deviceId();

            if (mastershipService.isLocalMaster(srcDev)) {
                mainComponent.getExecutorService().execute(() -> {
                    log.info("{} event! Configuring {}... linkSrc={}, linkDst={}",
                             event.type(), srcDev, srcDev, dstDev);
                    setUpFabricRoutes(srcDev);
                    setUpL2NextHopRules(srcDev);
                });
            }
            if (mastershipService.isLocalMaster(dstDev)) {
                mainComponent.getExecutorService().execute(() -> {
                    log.info("{} event! Configuring {}... linkSrc={}, linkDst={}",
                             event.type(), dstDev, srcDev, dstDev);
                    setUpFabricRoutes(dstDev);
                    setUpL2NextHopRules(dstDev);
                });
            }
        }
    }

    /**
     * Listener of device events which triggers configuration of the My Station
     * table.
     */
    class InternalDeviceListener implements DeviceListener {

        @Override
        public boolean isRelevant(DeviceEvent event) {
            switch (event.type()) {
                case DEVICE_AVAILABILITY_CHANGED:
                case DEVICE_ADDED:
                    break;
                default:
                    return false;
            }
            // Process device event if this controller instance is the master
            // for the device and the device is available.
            DeviceId deviceId = event.subject().id();
            return mastershipService.isLocalMaster(deviceId) &&
                    deviceService.isAvailable(event.subject().id());
        }

        @Override
        public void event(DeviceEvent event) {
            mainComponent.getExecutorService().execute(() -> {
                DeviceId deviceId = event.subject().id();
                log.info("{} event! device id={}", event.type(), deviceId);
                setUpMyStationTable(deviceId);
            });
        }
    }

    //--------------------------------------------------------------------------
    // ROUTING POLICY METHODS
    //
    // Called by event listeners, these methods implement the actual routing
    // policy, responsible of computing paths and creating ECMP groups.
    //--------------------------------------------------------------------------

    /**
     * Set up L2 nexthop rules of a device to providing forwarding inside the
     * fabric, i.e. between leaf and spine switches.
     *
     * @param deviceId the device ID
     */
    private void setUpL2NextHopRules(DeviceId deviceId) {

        Set<Link> egressLinks = linkService.getDeviceEgressLinks(deviceId);

        for (Link link : egressLinks) {
            // For each other switch directly connected to this.
            final DeviceId nextHopDevice = link.dst().deviceId();
            // Get port of this device connecting to next hop.
            final PortNumber outPort = link.src().port();
            // Get next hop MAC address.
            final MacAddress nextHopMac = getMyStationMac(nextHopDevice);

            final FlowRule nextHopRule = createL2NextHopRule(
                    deviceId, nextHopMac, outPort);

            flowRuleService.applyFlowRules(nextHopRule);
        }
    }

    /**
     * Sets up the given device with the necessary rules to route packets to the
     * given host.
     *
     * @param deviceId deviceId the device ID
     * @param host     the host
     */
    private void setUpHostRules(DeviceId deviceId, Host host) {

        // Get all IPv6 addresses associated to this host. In this tutorial we
        // use hosts with only 1 IPv6 address.
        final Collection<Ip6Address> hostIpv6Addrs = host.ipAddresses().stream()
                .filter(IpAddress::isIp6)
                .map(IpAddress::getIp6Address)
                .collect(Collectors.toSet());

        if (hostIpv6Addrs.isEmpty()) {
            // Ignore.
            log.debug("No IPv6 addresses for host {}, ignore", host.id());
            return;
        } else {
            log.info("Adding routes on {} for host {} [{}]",
                     deviceId, host.id(), hostIpv6Addrs);
        }

        // Create an ECMP group with only one member, where the group ID is
        // derived from the host MAC.
        final MacAddress hostMac = host.mac();
        int groupId = macToGroupId(hostMac);

        final GroupDescription group = createNextHopGroup(
                groupId, Collections.singleton(hostMac), deviceId);

        // Map each host IPV6 address to corresponding /128 prefix and obtain a
        // flow rule that points to the group ID. In this tutorial we expect
        // only one flow rule per host.
        final List<FlowRule> flowRules = hostIpv6Addrs.stream()
                .map(IpAddress::toIpPrefix)
                .filter(IpPrefix::isIp6)
                .map(IpPrefix::getIp6Prefix)
                .map(prefix -> createRoutingRule(deviceId, prefix, groupId))
                .collect(Collectors.toList());

        // Helper function to install flows after groups, since here flows
        // points to the group and P4Runtime enforces this dependency during
        // write operations.
        insertInOrder(group, flowRules);
    }

    /**
     * Set up routes on a given device to forward packets across the fabric,
     * making a distinction between spines and leaves.
     *
     * @param deviceId the device ID.
     */
    private void setUpFabricRoutes(DeviceId deviceId) {
        if (isSpine(deviceId)) {
            setUpSpineRoutes(deviceId);
        } else {
            setUpLeafRoutes(deviceId);
        }
    }

    /**
     * Insert routing rules on the given spine switch, matching on leaf
     * interface subnets and forwarding packets to the corresponding leaf.
     *
     * @param spineId the spine device ID
     */
    private void setUpSpineRoutes(DeviceId spineId) {

        log.info("Adding up spine routes on {}...", spineId);

        for (Device device : deviceService.getDevices()) {

            if (isSpine(device.id())) {
                // We only need routes to leaf switches. Ignore spines.
                continue;
            }

            final DeviceId leafId = device.id();
            final MacAddress leafMac = getMyStationMac(leafId);
            final Set<Ip6Prefix> subnetsToRoute = getInterfaceIpv6Prefixes(leafId);

            // Since we're here, we also add a route for SRv6, to forward
            // packets with IPv6 dst the SID of a leaf switch.
            final Ip6Address leafSid = getDeviceSid(leafId);
            subnetsToRoute.add(Ip6Prefix.valueOf(leafSid, 128));

            // Create a group with only one member.
            int groupId = macToGroupId(leafMac);

            GroupDescription group = createNextHopGroup(
                    groupId, Collections.singleton(leafMac), spineId);

            List<FlowRule> flowRules = subnetsToRoute.stream()
                    .map(subnet -> createRoutingRule(spineId, subnet, groupId))
                    .collect(Collectors.toList());

            insertInOrder(group, flowRules);
        }
    }

    /**
     * Insert routing rules on the given leaf switch, matching on interface
     * subnets associated to other leaves and forwarding packets the spines
     * using ECMP.
     *
     * @param leafId the leaf device ID
     */
    private void setUpLeafRoutes(DeviceId leafId) {
        log.info("Setting up leaf routes: {}", leafId);

        // Get the set of subnets (interface IPv6 prefixes) associated to other
        // leafs but not this one.
        Set<Ip6Prefix> subnetsToRouteViaSpines = stream(deviceService.getDevices())
                .map(Device::id)
                .filter(this::isLeaf)
                .filter(deviceId -> !deviceId.equals(leafId))
                .map(this::getInterfaceIpv6Prefixes)
                .flatMap(Collection::stream)
                .collect(Collectors.toSet());

        // Get myStationMac address of all spines.
        Set<MacAddress> spineMacs = stream(deviceService.getDevices())
                .map(Device::id)
                .filter(this::isSpine)
                .map(this::getMyStationMac)
                .collect(Collectors.toSet());

        // Create an ECMP group to distribute traffic across all spines.
        final int groupId = DEFAULT_ECMP_GROUP_ID;
        final GroupDescription ecmpGroup = createNextHopGroup(
                groupId, spineMacs, leafId);

        // Generate a flow rule for each subnet pointing to the ECMP group.
        List<FlowRule> flowRules = subnetsToRouteViaSpines.stream()
                .map(subnet -> createRoutingRule(leafId, subnet, groupId))
                .collect(Collectors.toList());

        insertInOrder(ecmpGroup, flowRules);

        // Since we're here, we also add a route for SRv6, to forward
        // packets with IPv6 dst the SID of a spine switch, in this case using a
        // single-member group.
        stream(deviceService.getDevices())
                .map(Device::id)
                .filter(this::isSpine)
                .forEach(spineId -> {
                    MacAddress spineMac = getMyStationMac(spineId);
                    Ip6Address spineSid = getDeviceSid(spineId);
                    int spineGroupId = macToGroupId(spineMac);
                    GroupDescription group = createNextHopGroup(
                            spineGroupId, Collections.singleton(spineMac), leafId);
                    FlowRule routingRule = createRoutingRule(
                            leafId, Ip6Prefix.valueOf(spineSid, 128),
                            spineGroupId);
                    insertInOrder(group, Collections.singleton(routingRule));
                });
    }

    //--------------------------------------------------------------------------
    // UTILITY METHODS
    //--------------------------------------------------------------------------

    /**
     * Returns true if the given device has isSpine flag set to true in the
     * config, false otherwise.
     *
     * @param deviceId the device ID
     * @return true if the device is a spine, false otherwise
     */
    private boolean isSpine(DeviceId deviceId) {
        return getDeviceConfig(deviceId).map(Srv6DeviceConfig::isSpine)
                .orElseThrow(() -> new ItemNotFoundException(
                        "Missing isSpine config for " + deviceId));
    }

    /**
     * Returns true if the given device is not configured as spine.
     *
     * @param deviceId the device ID
     * @return true if the device is a leaf, false otherwise
     */
    private boolean isLeaf(DeviceId deviceId) {
        return !isSpine(deviceId);
    }

    /**
     * Returns the MAC address configured in the "myStationMac" property of the
     * given device config.
     *
     * @param deviceId the device ID
     * @return MyStation MAC address
     */
    private MacAddress getMyStationMac(DeviceId deviceId) {
        return getDeviceConfig(deviceId)
                .map(Srv6DeviceConfig::myStationMac)
                .orElseThrow(() -> new ItemNotFoundException(
                        "Missing myStationMac config for " + deviceId));
    }

    /**
     * Returns the Srv6 config object for the given device.
     *
     * @param deviceId the device ID
     * @return Srv6  device config
     */
    private Optional<Srv6DeviceConfig> getDeviceConfig(DeviceId deviceId) {
        Srv6DeviceConfig config = networkConfigService.getConfig(
                deviceId, Srv6DeviceConfig.class);
        return Optional.ofNullable(config);
    }

    /**
     * Returns the set of interface IPv6 subnets (prefixes) configured for the
     * given device.
     *
     * @param deviceId the device ID
     * @return set of IPv6 prefixes
     */
    private Set<Ip6Prefix> getInterfaceIpv6Prefixes(DeviceId deviceId) {
        return interfaceService.getInterfaces().stream()
                .filter(iface -> iface.connectPoint().deviceId().equals(deviceId))
                .map(Interface::ipAddressesList)
                .flatMap(Collection::stream)
                .map(InterfaceIpAddress::subnetAddress)
                .filter(IpPrefix::isIp6)
                .map(IpPrefix::getIp6Prefix)
                .collect(Collectors.toSet());
    }

    /**
     * Returns a 32 bit bit group ID from the given MAC address.
     *
     * @param mac the MAC address
     * @return an integer
     */
    private int macToGroupId(MacAddress mac) {
        return mac.hashCode() & 0x7fffffff;
    }

    /**
     * Inserts the given groups and flow rules in order, groups first, then flow
     * rules. In P4Runtime, when operating on an indirect table (i.e. with
     * action selectors), groups must be inserted before table entries.
     *
     * @param group     the group
     * @param flowRules the flow rules depending on the group
     */
    private void insertInOrder(GroupDescription group, Collection<FlowRule> flowRules) {
        try {
            groupService.addGroup(group);
            // Wait for groups to be inserted.
            Thread.sleep(GROUP_INSERT_DELAY_MILLIS);
            flowRules.forEach(flowRuleService::applyFlowRules);
        } catch (InterruptedException e) {
            log.error("Interrupted!", e);
            Thread.currentThread().interrupt();
        }
    }

    /**
     * Gets Srv6 SID for the given device.
     *
     * @param deviceId the device ID
     * @return SID for the device
     */
    private Ip6Address getDeviceSid(DeviceId deviceId) {
        return getDeviceConfig(deviceId)
                .map(Srv6DeviceConfig::mySid)
                .orElseThrow(() -> new ItemNotFoundException(
                        "Missing mySid config for " + deviceId));
    }

    /**
     * Sets up IPv6 routing on all devices known by ONOS and for which this ONOS
     * node instance is currently master.
     */
    private synchronized void setUpAllDevices() {
        // Set up host routes
        stream(deviceService.getAvailableDevices())
                .map(Device::id)
                .filter(mastershipService::isLocalMaster)
                .forEach(deviceId -> {
                    log.info("*** IPV6 ROUTING - Starting initial set up for {}...", deviceId);
                    setUpMyStationTable(deviceId);
                    setUpFabricRoutes(deviceId);
                    setUpL2NextHopRules(deviceId);
                    hostService.getConnectedHosts(deviceId)
                            .forEach(host -> setUpHostRules(deviceId, host));
                });
    }
}
