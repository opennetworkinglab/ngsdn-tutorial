# Next-Gen SDN Tutorial

Welcome to Next-Gen SDN tutorial!

This tutorial is targeted to developers who want to learn the basics of the
building blocks of the NG-SDN architecture, such as:

* Data plane programming and control via P4 and P4Runtime
* Configuration via OpenConfig and gNMI
* Stratum
* ONOS

The tutorial is organized around a sequence of hands-on exercises that show how
to build an IPv6-based leaf-spine data center fabric.

## Slides

TODO

Tutorial slides are available [online](ADD SLIDES URL). These slides provide an
introduction to each exercise. We suggest you look at it before starting to work
on the exercises.

## Tutorial VM

TODO

To complete the exercises, you will need to download and run this tutorial VM
(XX GB):
 * ADD LINK TO VM

To run the VM you can use any modern x86 virtualization system. The VM has been
tested with VirtualBox v6.0.6. To download VirtualBox and import the VM use the
following links:

 * https://www.virtualbox.org/wiki/Downloads
 * https://docs.oracle.com/cd/E26217_01/E26796/html/qs-import-vm.html

### Recommended system requirements

The VM is configured with 4 GB of RAM and 4 CPU cores, while the disk has size
of approx. 8 GB. These are the recommended minimum requirements to be able to
run Ubuntu along with a Mininet network of 1-10 BMv2 devices controlled by 1
ONOS instance. For a flawless experience, we recommend running the VM on a host
system that has at least the double of resources.

### Use Docker instead of VM

TODO Add instructions to skip downloading the VM but use Docker instead.

### VM user credentials

Use the following credentials to log in the Ubuntu system:

 * **Username:** `sdn`
 * **Password:** `rocks`

### Get this tutorial repo

To work on the exercises you will need to clone this repo inside the VM:

    cd ~
    git clone https://github.com/opennetworkinglab/ngsdn-tutorial

If the `tutorial` directory is already present, make sure to update its
content:

    cd ~/ngsdn-tutorial
    git pull origin master

### Download / upgrade dependencies

The VM may have shipped with an older version of the dependencies than we would
like to use for the exercises. You can upgrade to the latest version used for
the tutorial using the following command:

    cd ~/ngsdn-tutorial
    make pull-deps

This command will download all necessary dependencies from the Internet,
allowing you to work off-line on the exercises. For this reason, we recommend
running this step ahead of the tutorial with a reliable Internet connection.


## Using an IDE to work on the exercises

During the exercises you will need to write code in multiple languages such as
P4, Python and Java. While the exercises do not prescribe the use of any
specific IDE or code editor, the tutorial VM comes with Java IDE [IntelliJ IDEA
Community Edition](https://www.jetbrains.com/idea/), already pre-loaded with
plugins for P4 syntax highlighting and Python development. We suggest using
IntelliJ IDEA especially when working on the ONOS app, as it provides code
completion for all ONOS APIs.

## Repo structure

FIXME

This repo is structured as follows:

 * `p4src/` P4 implementation
 * `app/` ONOS app Java implementation
 * `mininet/` Mininet script to emulate a 2x2 leaf-spine fabric topology of
   `stratum_bmv2` devices
 * `util/` Utilities (such as p4runtime-sh)

## Tutorial commands

To facilitate working on the exercises, we provide a set of make-based commands
to control the different aspects of the tutorial. Commands will be introduced in
the exercises, here's a quick reference:

| Make command        | Description                                            |
|---------------------|------------------------------------------------------- |
| `make pull-deps`    | Pull all required dependencies                         |
| `make p4-build `    | Build the P4 program                                   |
| `make app-build `   | Build ONOS app                                         |
| `make start`        | Start containers (`mininet` and `onos`)                |
| `make stop`         | Stop and remove all containers                         |
| `make onos-cli`     | Access the ONOS CLI (password: `rocks`, Ctrl+D to exit)|
| `make onos-ui`      | Open the ONOS Web UI (user `onos` password `rocks`)    |
| `make mn-cli`       | Access the Mininet CLI (Ctrl+P Ctrl+Q to exit)         |
| `make onos-log`     | Show the ONOS log                                      |
| `make mn-log`       | Show the Mininet log (i.e., the CLI output)            |
| `make netcfg`       | Push netcfg.json file (network config) to ONOS         |
| `make app-reload`   | Install and activate the ONOS app                      |
| `make reset`        | Reset the tutorial environment (to start from scratch) |

### P4Runtime shell

TODO add description

Usage:

```bash
./util/p4rt-sh --grpc-addr localhost:50001 --config p4src/build/p4info.txt,p4src/build/bmv2.json
```

## Exercises

Click on the exercise name to see the instructions:

 1. [P4 and P4Runtime basics](./EXERCISE-1.md)
 2. [OpenConfig and gNMI Basic](./EXERCISE-2.md)
 3. [Running ONOS](./EXERCISE-3.md)
 4. [Modify ONOS app](./EXERCISE-4.md)

## Solutions

TODO do we really need this?

You can find solutions for each exercise in the [solution](solution) directory.
Feel free to compare your implementation to the reference one whenever you feel
stuck. To use the solution code that is provided, simply use the same **make**
commands in the solution directory.
