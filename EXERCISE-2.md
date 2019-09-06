# Exercise 2

WIP

make yang-tools

## Part 1: Understanding YANG

Use pyang to lint and visualize models

pyang -f tree demo-interface.yang


pyang -f tree \
-p ietf \
-p openconfig \
-p hercules \
openconfig/interfaces/openconfig-interfaces.yang \
openconfig/interfaces/openconfig-if-ethernet.yang  \
openconfig/platform/* \
openconfig/qos/* \
openconfig/system/openconfig-system.yang \
hercules/openconfig-hercules-*.yang



## Part 2: Understand YANG encoding

XML validate with DSDL

pyang -f dsdl demo-port.yang | xmllint --format -

JSON schema: not covered

Protobuf

proto_generator -output_dir=/proto -package_name=tutorial demo-port.yang

proto_generator \
-generate_fakeroot \
-output_dir=/proto \
-package_name=openconfig \
-exclude_modules=ietf-interfaces \
-compress_paths \
-base_import_path= \
-path=ietf,openconfig,hercules \
openconfig/interfaces/openconfig-interfaces.yang \
openconfig/interfaces/openconfig-if-ip.yang \
openconfig/lacp/openconfig-lacp.yang \
openconfig/platform/openconfig-platform-linecard.yang \
openconfig/platform/openconfig-platform-port.yang \
openconfig/platform/openconfig-platform-transceiver.yang \
openconfig/platform/openconfig-platform.yang \
openconfig/system/openconfig-system.yang \
openconfig/vlan/openconfig-vlan.yang \
hercules/openconfig-hercules-interfaces.yang \
hercules/openconfig-hercules-platform-chassis.yang \
hercules/openconfig-hercules-platform-linecard.yang \
hercules/openconfig-hercules-platform-node.yang \
hercules/openconfig-hercules-platform-port.yang \
hercules/openconfig-hercules-platform.yang \
hercules/openconfig-hercules-qos.yang \
hercules/openconfig-hercules.yang

- gNMI Schema-less: discuss in next part

Validation with Go code

generator -output_dir=/goSrc -package_name=tutorial demo-interface.yang

## Part 3: Understanding Config transports

gNMI (others are NETCONF and RESTCONF)

make mn-single
util/gnmi-cli --grpc-addr localhost:50001 get /
util/gnmi-cli --grpc-addr localhost:50001 get / | util/oc-pb-decoder

Some SETs and SUBSCRIBEs as well


