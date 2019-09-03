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
package org.p4.p4d2.tutorial.cli;

import org.apache.karaf.shell.api.action.lifecycle.Service;
import org.apache.karaf.shell.api.console.CommandLine;
import org.apache.karaf.shell.api.console.Completer;
import org.apache.karaf.shell.api.console.Session;
import org.apache.karaf.shell.support.completers.StringsCompleter;
import org.onosproject.cli.AbstractShellCommand;
import org.onosproject.net.config.NetworkConfigService;
import org.onosproject.net.device.DeviceService;
import org.p4.p4d2.tutorial.common.Srv6DeviceConfig;

import java.util.List;
import java.util.Objects;
import java.util.SortedSet;

import static com.google.common.collect.Streams.stream;

/**
 * Completer for SIDs based on device config.
 */
@Service
public class Srv6SidCompleter implements Completer {

    @Override
    public int complete(Session session, CommandLine commandLine, List<String> candidates) {
        DeviceService deviceService = AbstractShellCommand.get(DeviceService.class);
        NetworkConfigService netCfgService = AbstractShellCommand.get(NetworkConfigService.class);

        // Delegate string completer
        StringsCompleter delegate = new StringsCompleter();
        SortedSet<String> strings = delegate.getStrings();

        stream(deviceService.getDevices())
                .map(d -> netCfgService.getConfig(d.id(), Srv6DeviceConfig.class))
                .filter(Objects::nonNull)
                .map(Srv6DeviceConfig::mySid)
                .filter(Objects::nonNull)
                .forEach(sid -> strings.add(sid.toString()));

        // Now let the completer do the work for figuring out what to offer.
        return delegate.complete(session, commandLine, candidates);
    }
}
