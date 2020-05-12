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


class IPv4Host(Host):
    """Host that can be configured with an IPv4 gateway (default route).
    """

    def config(self, mac=None, ip=None, defaultRoute=None, lo='up', gw=None,
               **_params):
        super(IPv4Host, self).config(mac, ip, defaultRoute, lo, **_params)
        self.cmd('ip -4 addr flush dev %s' % self.defaultIntf())
        self.cmd('ip -6 addr flush dev %s' % self.defaultIntf())
        self.cmd('ip -4 link set up %s' % self.defaultIntf())
        self.cmd('ip -4 addr add %s dev %s' % (ip, self.defaultIntf()))
        if gw:
            self.cmd('ip -4 route add default via %s' % gw)
        # Disable offload
        for attr in ["rx", "tx", "sg"]:
            cmd = "/sbin/ethtool --offload %s %s off" % (
                self.defaultIntf(), attr)
            self.cmd(cmd)

        def updateIP():
            return ip.split('/')[0]

        self.defaultIntf().updateIP = updateIP


class TaggedIPv4Host(Host):
    """VLAN-tagged host that can be configured with an IPv4 gateway
    (default route).
    """
    vlanIntf = None

    def config(self, mac=None, ip=None, defaultRoute=None, lo='up', gw=None,
               vlan=None, **_params):
        super(TaggedIPv4Host, self).config(mac, ip, defaultRoute, lo, **_params)
        self.vlanIntf = "%s.%s" % (self.defaultIntf(), vlan)
        # Replace default interface with a tagged one
        self.cmd('ip -4 addr flush dev %s' % self.defaultIntf())
        self.cmd('ip -6 addr flush dev %s' % self.defaultIntf())
        self.cmd('ip -4 link add link %s name %s type vlan id %s' % (
            self.defaultIntf(), self.vlanIntf, vlan))
        self.cmd('ip -4 link set up %s' % self.vlanIntf)
        self.cmd('ip -4 addr add %s dev %s' % (ip, self.vlanIntf))
        if gw:
            self.cmd('ip -4 route add default via %s' % gw)

        self.defaultIntf().name = self.vlanIntf
        self.nameToIntf[self.vlanIntf] = self.defaultIntf()

        # Disable offload
        for attr in ["rx", "tx", "sg"]:
            cmd = "/sbin/ethtool --offload %s %s off" % (
                self.defaultIntf(), attr)
            self.cmd(cmd)

        def updateIP():
            return ip.split('/')[0]

        self.defaultIntf().updateIP = updateIP

    def terminate(self):
        self.cmd('ip -4 link remove link %s' % self.vlanIntf)
        super(TaggedIPv4Host, self).terminate()


class TutorialTopo(Topo):
    """2x2 fabric topology with IPv4 hosts"""

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

        # IPv4 hosts attached to leaf 1
        h1a = self.addHost('h1a', cls=IPv4Host, mac="00:00:00:00:00:1A",
                           ip='172.16.1.1/24', gw='172.16.1.254')
        h1b = self.addHost('h1b', cls=IPv4Host, mac="00:00:00:00:00:1B",
                           ip='172.16.1.2/24', gw='172.16.1.254')
        h1c = self.addHost('h1c', cls=TaggedIPv4Host, mac="00:00:00:00:00:1C",
                           ip='172.16.1.3/24', gw='172.16.1.254', vlan=100)
        h2 = self.addHost('h2', cls=TaggedIPv4Host, mac="00:00:00:00:00:20",
                          ip='172.16.2.1/24', gw='172.16.2.254', vlan=200)
        self.addLink(h1a, leaf1)  # port 3
        self.addLink(h1b, leaf1)  # port 4
        self.addLink(h1c, leaf1)  # port 5
        self.addLink(h2, leaf1)  # port 6

        # IPv4 hosts attached to leaf 2
        h3 = self.addHost('h3', cls=TaggedIPv4Host, mac="00:00:00:00:00:30",
                          ip='172.16.3.1/24', gw='172.16.3.254', vlan=300)
        h4 = self.addHost('h4', cls=IPv4Host, mac="00:00:00:00:00:40",
                          ip='172.16.4.1/24', gw='172.16.4.254')
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
        description='Mininet topology script for 2x2 fabric with stratum_bmv2 and IPv4 hosts')
    args = parser.parse_args()
    setLogLevel('info')

    main()
