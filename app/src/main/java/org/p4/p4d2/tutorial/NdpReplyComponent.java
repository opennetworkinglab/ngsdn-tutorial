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

import org.onlab.packet.Ip6Address;
import org.onlab.packet.IpAddress;
import org.onlab.packet.MacAddress;
import org.onlab.util.ItemNotFoundException;
import org.onosproject.core.ApplicationId;
import org.onosproject.mastership.MastershipService;
import org.onosproject.net.DeviceId;
import org.onosproject.net.config.NetworkConfigService;
import org.onosproject.net.device.DeviceEvent;
import org.onosproject.net.device.DeviceListener;
import org.onosproject.net.device.DeviceService;
import org.onosproject.net.flow.DefaultFlowRule;
import org.onosproject.net.flow.DefaultTrafficSelector;
import org.onosproject.net.flow.DefaultTrafficTreatment;
import org.onosproject.net.flow.FlowRule;
import org.onosproject.net.flow.FlowRuleOperations;
import org.onosproject.net.flow.FlowRuleService;
import org.onosproject.net.flow.TrafficSelector;
import org.onosproject.net.flow.TrafficTreatment;
import org.onosproject.net.flow.criteria.PiCriterion;
import org.onosproject.net.host.InterfaceIpAddress;
import org.onosproject.net.intf.Interface;
import org.onosproject.net.intf.InterfaceService;
import org.onosproject.net.pi.model.PiActionId;
import org.onosproject.net.pi.model.PiActionParamId;
import org.onosproject.net.pi.model.PiMatchFieldId;
import org.onosproject.net.pi.model.PiTableId;
import org.onosproject.net.pi.runtime.PiAction;
import org.onosproject.net.pi.runtime.PiActionParam;
import org.osgi.service.component.annotations.Activate;
import org.osgi.service.component.annotations.Component;
import org.osgi.service.component.annotations.Deactivate;
import org.osgi.service.component.annotations.Reference;
import org.osgi.service.component.annotations.ReferenceCardinality;
import org.p4.p4d2.tutorial.common.Srv6DeviceConfig;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Collection;
import java.util.stream.Collectors;

import static org.p4.p4d2.tutorial.AppConstants.DEFAULT_FLOW_RULE_PRIORITY;
import static org.p4.p4d2.tutorial.AppConstants.INITIAL_SETUP_DELAY;

/**
 * App component that configures devices to generate NDP Neighbor Advertisement
 * packets for all interface IPv6 addresses configured in the netcfg.
 */
@Component(
        immediate = true,
        enabled = true
)
public class NdpReplyComponent {

    private static final Logger log =
            LoggerFactory.getLogger(NdpReplyComponent.class.getName());

    @Reference(cardinality = ReferenceCardinality.MANDATORY)
    protected NetworkConfigService configService;

    @Reference(cardinality = ReferenceCardinality.MANDATORY)
    protected FlowRuleService flowRuleService;

    @Reference(cardinality = ReferenceCardinality.MANDATORY)
    protected InterfaceService interfaceService;

    @Reference(cardinality = ReferenceCardinality.MANDATORY)
    protected MastershipService mastershipService;

    @Reference(cardinality = ReferenceCardinality.MANDATORY)
    protected DeviceService deviceService;

    @Reference(cardinality = ReferenceCardinality.MANDATORY)
    private MainComponent mainComponent;

    private DeviceListener deviceListener = new InternalDeviceListener();
    private ApplicationId appId;

    @Activate
    public void activate() {
        appId = mainComponent.getAppId();

        deviceService.addListener(deviceListener);

        mainComponent.scheduleTask(this::setUpAllDevices, INITIAL_SETUP_DELAY);

        log.info("Started");
    }

    @Deactivate
    public void deactivate() {
        deviceService.removeListener(deviceListener);

        log.info("Stopped");
    }

    private void setUpAllDevices() {
        deviceService.getAvailableDevices().forEach(device -> {
            if (mastershipService.isLocalMaster(device.id())) {
                log.info("*** NDP REPLY - Starting Initial set up for {}...", device.id());
                setUpDevice(device.id());
            }
        });
    }

    private void setUpDevice(DeviceId deviceId) {
        Srv6DeviceConfig config = configService.getConfig(deviceId, Srv6DeviceConfig.class);
        if (config == null) {
            // Config not available yet
            throw new ItemNotFoundException("Missing Srv6Config for " + deviceId);
        }

        final MacAddress deviceMac = config.myStationMac();

        // Get all interface for the device
        final Collection<Interface> interfaces = interfaceService.getInterfaces()
                .stream()
                .filter(iface -> iface.connectPoint().deviceId().equals(deviceId))
                .collect(Collectors.toSet());

        if (interfaces.isEmpty()) {
            log.info("{} does not have any IPv6 interface configured",
                     deviceId);
            return;
        }

        log.info("Adding rules to {} to generate NDP NA for {} IPv6 interfaces...",
                 deviceId, interfaces.size());

        final Collection<FlowRule> flowRules = interfaces.stream()
                .map(this::getIp6Addresses)
                .flatMap(Collection::stream)
                .map(iaddr -> buildNdpReplyFlowRule(deviceId, deviceMac, iaddr))
                .collect(Collectors.toSet());

        installRules(flowRules);
    }

    private Collection<Ip6Address> getIp6Addresses(Interface iface) {
        return iface.ipAddressesList()
                .stream()
                .map(InterfaceIpAddress::ipAddress)
                .filter(IpAddress::isIp6)
                .map(IpAddress::getIp6Address)
                .collect(Collectors.toSet());
    }

    private void installRules(Collection<FlowRule> flowRules) {
        FlowRuleOperations.Builder ops = FlowRuleOperations.builder();
        flowRules.forEach(ops::add);
        flowRuleService.apply(ops.build());
    }

    private FlowRule buildNdpReplyFlowRule(DeviceId deviceId,
                                           MacAddress deviceMac,
                                           Ip6Address targetIp) {
        PiCriterion match = PiCriterion.builder()
                .matchExact(PiMatchFieldId.of("hdr.ndp.target_addr"), targetIp.toOctets())
                .build();

        PiActionParam paramRouterMac = new PiActionParam(
                PiActionParamId.of("target_mac"), deviceMac.toBytes());
        PiAction action = PiAction.builder()
                .withId(PiActionId.of("IngressPipeImpl.ndp_ns_to_na"))
                .withParameter(paramRouterMac)
                .build();

        TrafficSelector selector = DefaultTrafficSelector.builder()
                .matchPi(match)
                .build();

        TrafficTreatment treatment = DefaultTrafficTreatment.builder()
                .piTableAction(action)
                .build();

        return DefaultFlowRule.builder()
                .forDevice(deviceId)
                .forTable(PiTableId.of("IngressPipeImpl.ndp_reply_table"))
                .fromApp(appId)
                .makePermanent()
                .withSelector(selector)
                .withTreatment(treatment)
                .withPriority(DEFAULT_FLOW_RULE_PRIORITY)
                .build();
    }

    /**
     * Listener of device events.
     */
    public class InternalDeviceListener implements DeviceListener {

        @Override
        public boolean isRelevant(DeviceEvent event) {
            switch (event.type()) {
                case DEVICE_ADDED:
                case DEVICE_AVAILABILITY_CHANGED:
                    break;
                default:
                    // Ignore other events.
                    return false;
            }
            // Process only if this controller instance is the master.
            final DeviceId deviceId = event.subject().id();
            return mastershipService.isLocalMaster(deviceId);
        }

        @Override
        public void event(DeviceEvent event) {
            final DeviceId deviceId = event.subject().id();
            if (deviceService.isAvailable(deviceId)) {
                // A P4Runtime device is considered available in ONOS when there
                // is a StreamChannel session open and the pipeline
                // configuration has been set.
                mainComponent.getExecutorService().execute(() -> {
                    log.info("{} event! deviceId={}", event.type(), deviceId);

                    setUpDevice(deviceId);
                });
            }
        }
    }
}
