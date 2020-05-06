#!/usr/bin/python

#  Copyright 2019-present Open Networking Foundation
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

import argparse

from mininet.cli import CLI
from mininet.log import setLogLevel
from mininet.net import Mininet
from mininet.node import Host
from mininet.topo import Topo
from stratum import StratumBmv2Switch

CPU_PORT = 255


class IPv6Host(Host):
    """Host that can be configured with an IPv6 gateway (default route).
    """

    def config(self, ipv6, ipv6_gw=None, **params):
        super(IPv6Host, self).config(**params)
        self.cmd('ip -4 addr flush dev %s' % self.defaultIntf())
        self.cmd('ip -6 addr flush dev %s' % self.defaultIntf())
        self.cmd('ip -6 addr add %s dev %s' % (ipv6, self.defaultIntf()))
        if ipv6_gw:
            self.cmd('ip -6 route add default via %s' % ipv6_gw)
        # Disable offload
        for attr in ["rx", "tx", "sg"]:
            cmd = "/sbin/ethtool --offload %s %s off" % (self.defaultIntf(), attr)
            self.cmd(cmd)

        def updateIP():
            return ipv6.split('/')[0]

        self.defaultIntf().updateIP = updateIP

    def terminate(self):
        super(IPv6Host, self).terminate()


class TutorialTopo(Topo):
    """2x2 fabric topology with IPv6 hosts"""

    def __init__(self, *args, **kwargs):
        Topo.__init__(self, *args, **kwargs)

        # Leaves
        # gRPC port 50001
        leaf1 = self.addSwitch('leaf1', cls=StratumBmv2Switch, cpuport=CPU_PORT)
        # gRPC port 50002
        leaf2 = self.addSwitch('leaf2', cls=StratumBmv2Switch, cpuport=CPU_PORT)

        # Spines
        # gRPC port 50003
        spine1 = self.addSwitch('spine1', cls=StratumBmv2Switch, cpuport=CPU_PORT)
        # gRPC port 50004
        spine2 = self.addSwitch('spine2', cls=StratumBmv2Switch, cpuport=CPU_PORT)

        # Switch Links
        self.addLink(spine1, leaf1)
        self.addLink(spine1, leaf2)
        self.addLink(spine2, leaf1)
        self.addLink(spine2, leaf2)

        # IPv6 hosts attached to leaf 1
        h1a = self.addHost('h1a', cls=IPv6Host, mac="00:00:00:00:00:1A",
                           ipv6='2001:1:1::a/64', ipv6_gw='2001:1:1::ff')
        h1b = self.addHost('h1b', cls=IPv6Host, mac="00:00:00:00:00:1B",
                           ipv6='2001:1:1::b/64', ipv6_gw='2001:1:1::ff')
        h1c = self.addHost('h1c', cls=IPv6Host, mac="00:00:00:00:00:1C",
                           ipv6='2001:1:1::c/64', ipv6_gw='2001:1:1::ff')
        h2 = self.addHost('h2', cls=IPv6Host, mac="00:00:00:00:00:20",
                          ipv6='2001:1:2::1/64', ipv6_gw='2001:1:2::ff')
        self.addLink(h1a, leaf1)  # port 3
        self.addLink(h1b, leaf1)  # port 4
        self.addLink(h1c, leaf1)  # port 5
        self.addLink(h2, leaf1)  # port 6

        # IPv6 hosts attached to leaf 2
        h3 = self.addHost('h3', cls=IPv6Host, mac="00:00:00:00:00:30",
                          ipv6='2001:2:3::1/64', ipv6_gw='2001:2:3::ff')
        h4 = self.addHost('h4', cls=IPv6Host, mac="00:00:00:00:00:40",
                          ipv6='2001:2:4::1/64', ipv6_gw='2001:2:4::ff')
        self.addLink(h3, leaf2)  # port 3
        self.addLink(h4, leaf2)  # port 4


def main():
    net = Mininet(topo=TutorialTopo(), controller=None)
    net.start()
    CLI(net)
    net.stop()
    print '#' * 80
    print 'ATTENTION: Mininet was stopped! Perhaps accidentally?'
    print 'No worries, it will restart automatically in a few seconds...'
    print 'To access again the Mininet CLI, use `make mn-cli`'
    print 'To detach from the CLI (without stopping), press Ctrl-D'
    print 'To permanently quit Mininet, use `make stop`'
    print '#' * 80


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description='Mininet topology script for 2x2 fabric with stratum_bmv2 and IPv6 hosts')
    args = parser.parse_args()
    setLogLevel('info')

    main()
