mkfile_path := $(abspath $(lastword $(MAKEFILE_LIST)))
curr_dir := $(patsubst %/,%,$(dir $(mkfile_path)))

include util/docker/Makefile.vars

onos_url := http://localhost:8181/onos
onos_curl := curl --fail -sSL --user onos:rocks --noproxy localhost
app_name := org.onosproject.ngsdn-tutorial

NGSDN_TUTORIAL_SUDO ?=

default:
	$(error Please specify a make target (see README.md))

_docker_pull_all:
	docker pull ${ONOS_IMG}@${ONOS_SHA}
	docker tag ${ONOS_IMG}@${ONOS_SHA} ${ONOS_IMG}
	docker pull ${P4RT_SH_IMG}@${P4RT_SH_SHA}
	docker tag ${P4RT_SH_IMG}@${P4RT_SH_SHA} ${P4RT_SH_IMG}
	docker pull ${P4C_IMG}@${P4C_SHA}
	docker tag ${P4C_IMG}@${P4C_SHA} ${P4C_IMG}
	docker pull ${MN_STRATUM_IMG}@${MN_STRATUM_SHA}
	docker tag ${MN_STRATUM_IMG}@${MN_STRATUM_SHA} ${MN_STRATUM_IMG}
	docker pull ${MVN_IMG}@${MVN_SHA}
	docker tag ${MVN_IMG}@${MVN_SHA} ${MVN_IMG}
	docker pull ${PTF_IMG}@${PTF_SHA}
	docker tag ${PTF_IMG}@${PTF_SHA} ${PTF_IMG}
	docker pull ${GNMI_CLI_IMG}@${GNMI_CLI_SHA}
	docker tag ${GNMI_CLI_IMG}@${GNMI_CLI_SHA} ${GNMI_CLI_IMG}
	docker pull ${YANG_IMG}@${YANG_SHA}
	docker tag ${YANG_IMG}@${YANG_SHA} ${YANG_IMG}

deps: _docker_pull_all

_start:
	$(info *** Starting ONOS and Mininet (${NGSDN_TOPO_PY})... )
	@mkdir -p tmp/onos
	@NGSDN_TOPO_PY=${NGSDN_TOPO_PY} docker-compose up -d

start: NGSDN_TOPO_PY := topo-v6.py
start: _start

start-sr: NGSDN_TOPO_PY := topo-v4.py
start-sr: _start

stop:
	$(info *** Stopping ONOS and Mininet...)
	@NGSDN_TOPO_PY=foo docker-compose down -t0

restart: reset start

onos-cli:
	$(info *** Connecting to the ONOS CLI... password: rocks)
	$(info *** Top exit press Ctrl-D)
	@ssh -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" -o LogLevel=ERROR -p 8101 onos@localhost

onos-log:
	docker-compose logs -f onos

onos-ui:
	open ${onos_url}/ui

mn-cli:
	$(info *** Attaching to Mininet CLI...)
	$(info *** To detach press Ctrl-D (Mininet will keep running))
	-@docker attach --detach-keys "ctrl-d" $(shell docker-compose ps -q mininet) || echo "*** Detached from Mininet CLI"

mn-log:
	docker logs -f mininet

_netcfg:
	$(info *** Pushing ${NGSDN_NETCFG_JSON} to ONOS...)
	${onos_curl} -X POST -H 'Content-Type:application/json' \
		${onos_url}/v1/network/configuration -d@./mininet/${NGSDN_NETCFG_JSON}
	@echo

netcfg: NGSDN_NETCFG_JSON := netcfg.json
netcfg: _netcfg

netcfg-sr: NGSDN_NETCFG_JSON := netcfg-sr.json
netcfg-sr: _netcfg

reset: stop
	-$(NGSDN_TUTORIAL_SUDO) rm -rf ./tmp

clean:
	-$(NGSDN_TUTORIAL_SUDO) rm -rf p4src/build
	-$(NGSDN_TUTORIAL_SUDO) rm -rf app/target
	-$(NGSDN_TUTORIAL_SUDO) rm -rf app/src/main/resources/bmv2.json
	-$(NGSDN_TUTORIAL_SUDO) rm -rf app/src/main/resources/p4info.txt

p4-build: p4src/main.p4
	$(info *** Building P4 program...)
	@mkdir -p p4src/build
	docker run --rm -v ${curr_dir}:/workdir -w /workdir ${P4C_IMG} \
		p4c-bm2-ss --arch v1model -o p4src/build/bmv2.json \
		--p4runtime-files p4src/build/p4info.txt --Wdisable=unsupported \
		p4src/main.p4
	@echo "*** P4 program compiled successfully! Output files are in p4src/build"

p4-test:
	@cd ptf && PTF_DOCKER_IMG=$(PTF_IMG) ./run_tests $(TEST)

_copy_p4c_out:
	$(info *** Copying p4c outputs to app resources...)
	@mkdir -p app/src/main/resources
	cp -f p4src/build/p4info.txt app/src/main/resources/
	cp -f p4src/build/bmv2.json app/src/main/resources/

_mvn_package:
	$(info *** Building ONOS app...)
	@mkdir -p app/target
	@docker run --rm -v ${curr_dir}/app:/mvn-src -w /mvn-src ${MVN_IMG} mvn -o clean package

app-build: p4-build _copy_p4c_out _mvn_package
	$(info *** ONOS app .oar package created succesfully)
	@ls -1 app/target/*.oar

app-install:
	$(info *** Installing and activating app in ONOS...)
	${onos_curl} -X POST -HContent-Type:application/octet-stream \
		'${onos_url}/v1/applications?activate=true' \
		--data-binary @app/target/ngsdn-tutorial-1.0-SNAPSHOT.oar
	@echo

app-uninstall:
	$(info *** Uninstalling app from ONOS (if present)...)
	-${onos_curl} -X DELETE ${onos_url}/v1/applications/${app_name}
	@echo

app-reload: app-uninstall app-install

mn-single:
	docker run --privileged --rm -it -v /tmp/mn-stratum:/tmp -p 50001:50001 ${MN_STRATUM_IMG}

yang-tools:
	docker run --rm -it -v ${curr_dir}/yang/demo-port.yang:/models/demo-port.yang ${YANG_IMG}

solution-apply:
	mkdir working_copy
	cp -r app working_copy/app
	cp -r p4src working_copy/p4src
	cp -r ptf working_copy/ptf
	rsync -r solution/ ./

solution-revert:
	$(NGSDN_TUTORIAL_SUDO) rm -rf ./app
	$(NGSDN_TUTORIAL_SUDO) rm -rf ./p4src
	$(NGSDN_TUTORIAL_SUDO) rm -rf ./ptf
	cp -r working_copy/* ./
	$(NGSDN_TUTORIAL_SUDO) rm -rf working_copy/

check:
	make reset
	# P4 starter code and app should compile
	make p4-build
	make app-build
	# Check solution
	make solution-apply
	make start
	make p4-build
	make p4-test
	make app-build
	sleep 30
	make app-reload
	sleep 10
	make netcfg
	sleep 10
	# The first ping(s) might fail because of a known race condition in the
	# L2BridgingComponenet. Ping all hosts.
	-util/mn-cmd h1a ping -c 1 2001:1:1::b
	util/mn-cmd h1a ping -c 1 2001:1:1::b
	-util/mn-cmd h1b ping -c 1 2001:1:1::c
	util/mn-cmd h1b ping -c 1 2001:1:1::c
	-util/mn-cmd h2 ping -c 1 2001:1:1::b
	util/mn-cmd h2 ping -c 1 2001:1:1::b
	util/mn-cmd h2 ping -c 1 2001:1:1::a
	util/mn-cmd h2 ping -c 1 2001:1:1::c
	-util/mn-cmd h3 ping -c 1 2001:1:2::1
	util/mn-cmd h3 ping -c 1 2001:1:2::1
	util/mn-cmd h3 ping -c 1 2001:1:1::a
	util/mn-cmd h3 ping -c 1 2001:1:1::b
	util/mn-cmd h3 ping -c 1 2001:1:1::c
	-util/mn-cmd h4 ping -c 1 2001:1:2::1
	util/mn-cmd h4 ping -c 1 2001:1:2::1
	util/mn-cmd h4 ping -c 1 2001:1:1::a
	util/mn-cmd h4 ping -c 1 2001:1:1::b
	util/mn-cmd h4 ping -c 1 2001:1:1::c
	make stop
	make solution-revert

check-sr:
	make reset
	make start-sr
	sleep 45
	util/onos-cmd app activate segmentrouting
	util/onos-cmd app activate pipelines.fabric
	sleep 15
	util/onos-cmd cfg set org.onosproject.net.flow.impl.FlowRuleManager fallbackFlowPollFrequency 4
	util/onos-cmd cfg set org.onosproject.net.group.impl.GroupManager fallbackGroupPollFrequency 3
	make netcfg-sr
	sleep 20
	# Ping gateway (ONOS) to discover routing-only hosts
	util/mn-cmd h2 ping -c 1 172.16.2.254
	util/mn-cmd h3 ping -c 1 172.16.3.254
	util/mn-cmd h4 ping -c 1 172.16.4.254
	sleep 5
	# For bridged hosts (in the same subnet) no need to ping the gateway.
	# Make sure bridging works via broadcast.
	util/mn-cmd h1a ping -c 1 172.16.1.2
	util/mn-cmd h1b ping -c 1 172.16.1.3
	sleep 5
	# Ping all.
	util/mn-cmd h2 ping -c 1 172.16.1.2
	util/mn-cmd h2 ping -c 1 172.16.1.1
	util/mn-cmd h2 ping -c 1 172.16.1.3
	util/mn-cmd h3 ping -c 1 172.16.2.1
	util/mn-cmd h3 ping -c 1 172.16.1.1
	util/mn-cmd h3 ping -c 1 172.16.1.2
	util/mn-cmd h3 ping -c 1 172.16.1.3
	util/mn-cmd h4 ping -c 1 172.16.2.1
	util/mn-cmd h4 ping -c 1 172.16.1.1
	util/mn-cmd h4 ping -c 1 172.16.1.2
	util/mn-cmd h4 ping -c 1 172.16.1.3
	make stop
