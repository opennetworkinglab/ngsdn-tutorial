#!/bin/bash
set -xe

cd /home/sdn

cp /etc/skel/.bashrc ~/
cp /etc/skel/.profile ~/
cp /etc/skel/.bash_logout ~/

#  With Ubuntu 18.04 sometimes .cache is owned by root...
mkdir -p ~/.cache
sudo chown -hR sdn:sdn ~/.cache

git clone https://github.com/opennetworkinglab/ngsdn-tutorial.git
cd ngsdn-tutorial
make deps
