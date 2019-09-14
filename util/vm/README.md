# Scripts to build the tutorial VM

## Requirements

- [Vagrant](https://www.vagrantup.com/) (tested v2.2.5)
- [VirtualBox](https://www.virtualbox.org/wiki/Downloads) (tested with v5.2.32)

## Steps to build

If you want to provision and use the VM locally on your machine:

    cd util/vm
    vagrant up

Otherwise, if you want to export the VM in `.ova` format for distribution to
tutorial attendees:

    cd util/vm
    ./build-vm.sh

This script will:

1. provision the VM using Vagrant;
2. reduce VM disk size;
3. generate a file named `ngsdn-tutorial.ova`.

Use credentials `sdn`/`rocks` to log in the Ubuntu system.

**Note on IntelliJ IDEA plugins:** plugins need to be installed manually. We
recommend installing the following ones:

* https://plugins.jetbrains.com/plugin/10620-p4-plugin
* https://plugins.jetbrains.com/plugin/7322-python-community-edition