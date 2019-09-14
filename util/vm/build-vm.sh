#!/usr/bin/env bash

set -xe

function wait_vm_shutdown {
    set +x
    while vboxmanage showvminfo $1 | grep -c "running (since"; do
      echo "Waiting for VM to shutdown..."
      sleep 1
    done
    sleep 2
    set -x
}

# Provision
vagrant up

# Cleanup
VB_UUID=$(cat .vagrant/machines/default/virtualbox/id)
vagrant ssh -c 'bash /vagrant/cleanup.sh'
sleep 5
vboxmanage controlvm "${VB_UUID}" acpipowerbutton
wait_vm_shutdown "${VB_UUID}"
# Remove vagrant shared folder
vboxmanage sharedfolder remove "${VB_UUID}" -name "vagrant"

# Export
rm -f ngsdn-tutorial.ova
vboxmanage export "${VB_UUID}" -o ngsdn-tutorial.ova
