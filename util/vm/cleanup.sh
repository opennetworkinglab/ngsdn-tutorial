#!/bin/bash
set -ex

sudo apt-get clean
sudo apt-get -y autoremove

sudo rm -rf /tmp/*

history -c
rm -f ~/.bash_history

# Zerofill virtual hd to save space when exporting
time sudo dd if=/dev/zero of=/tmp/zero bs=1M || true
sync ; sleep 1 ; sync ; sudo rm -f /tmp/zero

# Delete vagrant user
sudo userdel -r -f vagrant
