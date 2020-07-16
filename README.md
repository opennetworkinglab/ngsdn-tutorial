# Next-Gen SDN Tutorial (Advanced)

Welcome to the Next-Gen SDN tutorial!

This tutorial is targeted at students and practitioners who want to learn about
the building blocks of the next-generation SDN (NG-SDN) architecture, such as:

* Data plane programming and control via P4 and P4Runtime
* Configuration via YANG, OpenConfig, and gNMI
* Stratum switch OS
* ONOS SDN controller

Tutorial sessions are organized around a sequence of hands-on exercises that
show how to build a leaf-spine data center fabric based on IPv6, using P4,
Stratum, and ONOS. Exercises assume an intermediate knowledge of the P4
language, and a basic knowledge of Java and Python. Participants will be
provided with a starter P4 program and ONOS app implementation. Exercises will
focus on concepts such as:

* Using Stratum APIs (P4Runtime, gNMI, OpenConfig, gNOI)
* Using ONOS with devices programmed with arbitrary P4 programs
* Writing ONOS applications to provide the control plane logic
  (bridging, routing, ECMP, etc.)
* Testing using bmv2 in Mininet
* PTF-based P4 unit tests

## Basic vs. advanced version

This tutorial comes in two versions: basic (`master` branch), and advanced
(this branch).

The basic version contains fewer exercises, and it does not assume prior
knowledge of the P4 language. Instead, it provides a gentle introduction to it.
Check the `master` branch of this repo if you're interested in the basic
version.

If you're interested in the advanced version, keep reading.

## Slides

Tutorial slides are available online:
<http://bit.ly/adv-ngsdn-tutorial-slides>

These slides provide an introduction to the topics covered in the tutorial. We
suggest you look at it before starting to work on the exercises.

## System requirements

If you are taking this tutorial at an event organized by ONF, you should have
received credentials to access the **ONF Cloud Tutorial Platform**, in which
case you can skip this section. Keep reading if you are interested in working on
the exercises on your laptop.

To facilitate access to the tools required to complete this tutorial, we provide
two options for you to choose from:

1. Download a pre-packaged VM with all included; **OR**
2. Manually install Docker and other dependencies.

### Option 1 - Download tutorial VM

Use the following link to download the VM (4 GB):
* <http://bit.ly/ngsdn-tutorial-ova>

The VM is in .ova format and has been created using VirtualBox v5.2.32. To run
the VM you can use any modern virtualization system, although we recommend using
VirtualBox. For instructions on how to get VirtualBox and import the VM, use the
following links:

* <https://www.virtualbox.org/wiki/Downloads>
* <https://docs.oracle.com/cd/E26217_01/E26796/html/qs-import-vm.html>

Alternatively, you can use the scripts in [util/vm](util/vm) to build a VM on
your machine using Vagrant.

**Recommended VM configuration:**
The current configuration of the VM is 4 GB of RAM and 4 core CPU. These are the
recommended minimum system requirements to complete the exercises. When
imported, the VM takes approx. 8 GB of HDD space. For a smooth experience, we
recommend running the VM on a host system that has at least the double of
resources.

**VM user credentials:**
Use credentials `sdn`/`rocks` to log in the Ubuntu system.

### Option 2 - Manually install Docker and other dependencies

All exercises can be executed by installing the following dependencies:

* Docker v1.13.0+ (with docker-compose)
* make
* Python 3
* Bash-like Unix shell
* Wireshark (optional)

**Note for Windows users**: all scripts have been tested on macOS and Ubuntu.
Although we think they should work on Windows, we have not tested it. For this
reason, we advise Windows users to prefer Option 1.

## Get this repo or pull latest changes

To work on the exercises you will need to clone this repo:

    cd ~
    git clone -b advanced https://github.com/opennetworkinglab/ngsdn-tutorial

If the `ngsdn-tutorial` directory is already present, make sure to update its
content:

    cd ~/ngsdn-tutorial
    git pull origin advanced

## Download / upgrade dependencies

The VM may have shipped with an older version of the dependencies than we would
like to use for the exercises. You can upgrade to the latest version using the
following command:

    cd ~/ngsdn-tutorial
    make deps

This command will download all necessary Docker images (~1.5 GB) allowing you to
work off-line. For this reason, we recommend running this step ahead of the
tutorial, with a reliable Internet connection.

## Using an IDE to work on the exercises

During the exercises you will need to write code in multiple languages such as
P4, Java, and Python. While the exercises do not prescribe the use of any
specific IDE or code editor, the **ONF Cloud Tutorial Platform** provides access
to a web-based version of Visual Studio Code (VS Code).

If you are using the tutorial VM, you will find the Java IDE [IntelliJ IDEA
Community Edition](https://www.jetbrains.com/idea/), already pre-loaded with
plugins for P4 syntax highlighting and Python development. We suggest using
IntelliJ IDEA especially when working on the ONOS app, as it provides code
completion for all ONOS APIs.

## Repo structure

This repo is structured as follows:

 * `p4src/` P4 implementation
 * `yang/` Yang model used in exercise 2
 * `app/` custom ONOS app Java implementation
 * `mininet/` Mininet script to emulate a 2x2 leaf-spine fabric topology of
   `stratum_bmv2` devices
 * `util/` Utility scripts
 * `ptf/` P4 data plane unit tests based on Packet Test Framework (PTF)

## Tutorial commands

To facilitate working on the exercises, we provide a set of make-based commands
to control the different aspects of the tutorial. Commands will be introduced in
the exercises, here's a quick reference:

| Make command        | Description                                            |
|---------------------|------------------------------------------------------- |
| `make deps`         | Pull and build all required dependencies               |
| `make p4-build`     | Build P4 program                                       |
| `make p4-test`      | Run PTF tests                                          |
| `make start`        | Start Mininet and ONOS containers                      |
| `make stop`         | Stop all containers                                    |
| `make restart`      | Restart containers clearing any previous state         |
| `make onos-cli`     | Access the ONOS CLI (password: `rocks`, Ctrl-D to exit)|
| `make onos-log`     | Show the ONOS log                                      |
| `make mn-cli`       | Access the Mininet CLI (Ctrl-D to exit)                |
| `make mn-log`       | Show the Mininet log (i.e., the CLI output)            |
| `make app-build`    | Build custom ONOS app                                  |
| `make app-reload`   | Install and activate the ONOS app                      |
| `make netcfg`       | Push netcfg.json file (network config) to ONOS         |

## Exercises

Click on the exercise name to see the instructions:

 1. [P4Runtime basics](./EXERCISE-1.md)
 2. [Yang, OpenConfig, and gNMI basics](./EXERCISE-2.md)
 3. [Using ONOS as the control plane](./EXERCISE-3.md)
 4. [Enabling ONOS built-in services](./EXERCISE-4.md)
 5. [Implementing IPv6 routing with ECMP](./EXERCISE-5.md)
 6. [Implementing SRv6](./EXERCISE-6.md)
 7. [Trellis Basics](./EXERCISE-7.md)
 8. [GTP termination with fabric.p4](./EXERCISE-8.md)

## Solutions

You can find solutions for each exercise in the [solution](solution) directory.
Feel free to compare your solution to the reference one whenever you feel stuck.

[![Build Status](https://travis-ci.org/opennetworkinglab/ngsdn-tutorial.svg?branch=advanced)](https://travis-ci.org/opennetworkinglab/ngsdn-tutorial)
