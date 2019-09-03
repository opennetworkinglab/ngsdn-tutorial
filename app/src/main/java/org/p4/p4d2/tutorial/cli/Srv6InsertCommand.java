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

import org.apache.karaf.shell.api.action.Argument;
import org.apache.karaf.shell.api.action.Command;
import org.apache.karaf.shell.api.action.Completion;
import org.apache.karaf.shell.api.action.lifecycle.Service;
import org.onlab.packet.Ip6Address;
import org.onlab.packet.IpAddress;
import org.onosproject.cli.AbstractShellCommand;
import org.onosproject.cli.net.DeviceIdCompleter;
import org.onosproject.net.Device;
import org.onosproject.net.DeviceId;
import org.onosproject.net.device.DeviceService;
import org.p4.p4d2.tutorial.Srv6Component;

import java.util.List;
import java.util.stream.Collectors;

/**
 * SRv6 Transit Insert Command
 */
@Service
@Command(scope = "onos", name = "srv6-insert",
         description = "Insert a t_insert rule into the SRv6 Transit table")
public class Srv6InsertCommand extends AbstractShellCommand {

    @Argument(index = 0, name = "uri", description = "Device ID",
              required = true, multiValued = false)
    @Completion(DeviceIdCompleter.class)
    String uri = null;

    @Argument(index = 1, name = "segments",
            description = "SRv6 Segments (space separated list); last segment is target IP address",
            required = false, multiValued = true)
    @Completion(Srv6SidCompleter.class)
    List<String> segments = null;

    @Override
    protected void doExecute() {
        DeviceService deviceService = get(DeviceService.class);
        Srv6Component app = get(Srv6Component.class);

        Device device = deviceService.getDevice(DeviceId.deviceId(uri));
        if (device == null) {
            print("Device \"%s\" is not found", uri);
            return;
        }
        if (segments.size() == 0) {
            print("No segments listed");
            return;
        }
        List<Ip6Address> sids = segments.stream()
                .map(Ip6Address::valueOf)
                .collect(Collectors.toList());
        Ip6Address destIp = sids.get(sids.size() - 1);

        print("Installing path on device %s: %s",
                uri, sids.stream()
                         .map(IpAddress::toString)
                         .collect(Collectors.joining(", ")));
        app.insertSrv6InsertRule(device.id(), destIp, 128, sids);

    }

}
