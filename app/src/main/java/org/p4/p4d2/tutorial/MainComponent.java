package org.p4.p4d2.tutorial;

import com.google.common.collect.Lists;
import org.onlab.util.SharedScheduledExecutors;
import org.onosproject.cfg.ComponentConfigService;
import org.onosproject.core.ApplicationId;
import org.onosproject.core.CoreService;
import org.onosproject.net.Device;
import org.onosproject.net.DeviceId;
import org.onosproject.net.config.ConfigFactory;
import org.onosproject.net.config.NetworkConfigRegistry;
import org.onosproject.net.config.basics.SubjectFactories;
import org.onosproject.net.device.DeviceService;
import org.onosproject.net.flow.FlowRule;
import org.onosproject.net.flow.FlowRuleService;
import org.onosproject.net.group.Group;
import org.onosproject.net.group.GroupService;
import org.osgi.service.component.annotations.Activate;
import org.osgi.service.component.annotations.Component;
import org.osgi.service.component.annotations.Deactivate;
import org.osgi.service.component.annotations.Reference;
import org.osgi.service.component.annotations.ReferenceCardinality;
import org.p4.p4d2.tutorial.common.Srv6DeviceConfig;
import org.p4.p4d2.tutorial.pipeconf.PipeconfLoader;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Collection;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

import static org.p4.p4d2.tutorial.AppConstants.APP_NAME;
import static org.p4.p4d2.tutorial.AppConstants.CLEAN_UP_DELAY;
import static org.p4.p4d2.tutorial.AppConstants.DEFAULT_CLEAN_UP_RETRY_TIMES;
import static org.p4.p4d2.tutorial.common.Utils.sleep;

/**
 * A component which among other things registers the Srv6DeviceConfig to the
 * netcfg subsystem.
 */
@Component(immediate = true, service = MainComponent.class)
public class MainComponent {

    private static final Logger log =
            LoggerFactory.getLogger(MainComponent.class.getName());

    @Reference(cardinality = ReferenceCardinality.MANDATORY)
    private CoreService coreService;

    @Reference(cardinality = ReferenceCardinality.MANDATORY)
    //Force activation of this component after the pipeconf has been registered.
    @SuppressWarnings("unused")
    protected PipeconfLoader pipeconfLoader;

    @Reference(cardinality = ReferenceCardinality.MANDATORY)
    protected NetworkConfigRegistry configRegistry;

    @Reference(cardinality = ReferenceCardinality.MANDATORY)
    private GroupService groupService;

    @Reference(cardinality = ReferenceCardinality.MANDATORY)
    private DeviceService deviceService;

    @Reference(cardinality = ReferenceCardinality.MANDATORY)
    private FlowRuleService flowRuleService;

    @Reference(cardinality = ReferenceCardinality.MANDATORY)
    private ComponentConfigService compCfgService;

    private final ConfigFactory<DeviceId, Srv6DeviceConfig> srv6ConfigFactory =
            new ConfigFactory<DeviceId, Srv6DeviceConfig>(
                    SubjectFactories.DEVICE_SUBJECT_FACTORY, Srv6DeviceConfig.class, Srv6DeviceConfig.CONFIG_KEY) {
                @Override
                public Srv6DeviceConfig createConfig() {
                    return new Srv6DeviceConfig();
                }
            };

    private ApplicationId appId;

    // For the sake of simplicity and to facilitate reading logs, use a
    // single-thread executor to serialize all configuration tasks.
    private final ExecutorService executorService = Executors.newSingleThreadExecutor();

    @Activate
    protected void activate() {
        appId = coreService.registerApplication(APP_NAME);

        // Wait to remove flow and groups from previous executions.
        waitPreviousCleanup();

        compCfgService.preSetProperty("org.onosproject.net.flow.impl.FlowRuleManager",
                                      "fallbackFlowPollFrequency", "4", false);
        compCfgService.preSetProperty("org.onosproject.net.group.impl.GroupManager",
                                      "fallbackGroupPollFrequency", "3", false);
        compCfgService.preSetProperty("org.onosproject.provider.host.impl.HostLocationProvider",
                                      "requestIpv6ND", "true", false);

        configRegistry.registerConfigFactory(srv6ConfigFactory);
        log.info("Started");
    }

    @Deactivate
    protected void deactivate() {
        configRegistry.unregisterConfigFactory(srv6ConfigFactory);

        cleanUp();

        log.info("Stopped");
    }

    /**
     * Returns the application ID.
     *
     * @return application ID
     */
    ApplicationId getAppId() {
        return appId;
    }

    /**
     * Returns the executor service managed by this component.
     *
     * @return executor service
     */
    public ExecutorService getExecutorService() {
        return executorService;
    }

    /**
     * Schedules a task for the future using the executor service managed by
     * this component.
     *
     * @param task task runnable
     * @param delaySeconds delay in seconds
     */
    public void scheduleTask(Runnable task, int delaySeconds) {
        SharedScheduledExecutors.newTimeout(
                () -> executorService.execute(task),
                delaySeconds, TimeUnit.SECONDS);
    }

    /**
     * Triggers clean up of flows and groups from this app, returns false if no
     * flows or groups were found, true otherwise.
     *
     * @return false if no flows or groups were found, true otherwise
     */
    private boolean cleanUp() {
        Collection<FlowRule> flows = Lists.newArrayList(
                flowRuleService.getFlowEntriesById(appId).iterator());

        Collection<Group> groups = Lists.newArrayList();
        for (Device device : deviceService.getAvailableDevices()) {
            groupService.getGroups(device.id(), appId).forEach(groups::add);
        }

        if (flows.isEmpty() && groups.isEmpty()) {
            return false;
        }

        flows.forEach(flowRuleService::removeFlowRules);
        if (!groups.isEmpty()) {
            // Wait for flows to be removed in case those depend on groups.
            sleep(1000);
            groups.forEach(g -> groupService.removeGroup(
                    g.deviceId(), g.appCookie(), g.appId()));
        }

        return true;
    }

    private void waitPreviousCleanup() {
        int retry = DEFAULT_CLEAN_UP_RETRY_TIMES;
        while (retry != 0) {

            if (!cleanUp()) {
                return;
            }

            log.info("Waiting to remove flows and groups from " +
                             "previous execution of {}...",
                     appId.name());

            sleep(CLEAN_UP_DELAY);

            --retry;
        }
    }
}
