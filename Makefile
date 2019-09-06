ONOS_IMG := onosproject/onos:2.2.0
P4RT_SH_IMG := p4lang/p4runtime-sh:latest
P4C_IMG := opennetworking/p4c:stable
MN_STRATUM_IMG := opennetworking/mn-stratum:latest
MAVEN_IMG := maven:3.6.1-jdk-11-slim
PTF_IMG := onosproject/fabric-p4test

ONOS_SHA := sha256:c1d18e6957a785d0234855eb8c70909bfc68849338f0567e12a6ae7ce6f4ba91
P4RT_SH_SHA := sha256:6ae50afb5bde620acb9473ce6cd7b990ff6cc63fe4113cf5584c8e38fe42176c
P4C_SHA := sha256:8f9d27a6edf446c3801db621359fec5de993ebdebc6844d8b1292e369be5dfea
MN_STRATUM_SHA := sha256:ae7c59885509ece8062e196e6a8fb6aa06386ba25df646ed27c765d92d131692
MAVEN_SHA := sha256:ca67b12d638fe1b8492fa4633200b83b118f2db915c1f75baf3b0d2ef32d7263
PTF_SHA := sha256:227207ff9d15f5e45c44c7904e815efdb3cea0b4e5644ac0878d41dd54aca78d

mkfile_path := $(abspath $(lastword $(MAKEFILE_LIST)))
curr_dir := $(patsubst %/,%,$(dir $(mkfile_path)))
curr_dir_sha := $(shell echo -n "$(curr_dir)" | shasum | cut -c1-7)

app_build_container_name := app-build-${curr_dir_sha}
onos_url := http://localhost:8181/onos
onos_curl := curl --fail -sSL --user onos:rocks --noproxy localhost
app_name := org.onosproject.ngsdn-tutorial

default:
	$(error Please specify a make target (see README.md))

_docker_pull_all:
	docker pull ${ONOS_IMG}@${ONOS_SHA}
	docker pull ${P4RT_SH_IMG}@${P4RT_SH_SHA}
	docker pull ${P4C_IMG}@${P4C_SHA}
	docker pull ${MN_STRATUM_IMG}@${MN_STRATUM_SHA}
	docker pull ${MAVEN_IMG}@${MAVEN_SHA}
	docker pull ${PTF_IMG}@${PTF_SHA}

# Pul lall Docker images and build app to seed mvn repo inside container, i.e.
# download deps
pull-deps: _docker_pull_all _create_mvn_container _mvn_package

start:
	docker-compose up -d

stop:
	docker-compose down -t0

restart: stop start

onos-cli:
	$(info *** Connecting to the ONOS CLI... password: rocks)
	$(info *** Top exit press ctrl+D)
	@ssh -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" -o LogLevel=ERROR -p 8101 onos@localhost

onos-log:
	docker-compose logs -f onos

onos-ui:
	open ${onos_url}/ui

mn-cli:
	$(info *** Attaching to Mininet CLI...)
	$(info *** To detach press ctrl+P ctrl+Q (Mininet will keep running))
	-@docker attach $(shell docker-compose ps -q mininet) || echo "*** Detached from Mininet CLI"

mn-log:
	docker-compose logs -f mininet

netcfg:
	$(info *** Pushing netcfg.json to ONOS...)
	${onos_curl} -X POST -H 'Content-Type:application/json' \
		${onos_url}/v1/network/configuration -d@./mininet/netcfg.json
	@echo

reset: stop
	-rm -rf ./tmp

clean:
	-rm -rf p4src/build
	-rm -rf app/target

deep-clean: clean
	-docker container rm ${app_build_container_name}

p4-build:
	$(info *** Building P4 program...)
	@mkdir -p p4src/build
	docker run --rm -v ${curr_dir}:${curr_dir} -w ${curr_dir} ${P4C_IMG} \
		p4c-bm2-ss --arch v1model -o p4src/build/bmv2.json \
		--p4runtime-files p4src/build/p4info.txt --Wdisable=unsupported \
		p4src/main.p4

p4-test:
	@cd ptf && ./run_tests

# Create container once, use it many times to preserve mvn repo cache.
_create_mvn_container:
	@if ! docker container ls -a --format '{{.Names}}' | grep -q ${app_build_container_name} ; then \
		docker create -v ${curr_dir}/app:/mvn-src -w /mvn-src --name ${app_build_container_name} ${MAVEN_IMG} mvn clean package; \
	fi

_copy_p4c_out:
	$(info *** Copying p4c outputs to app resources...)
	cp -f p4src/build/p4info.txt app/src/main/resources/
	cp -f p4src/build/bmv2.json app/src/main/resources/

_mvn_package:
	$(info *** Building ONOS app...)
	@docker start -a -i ${app_build_container_name}

app-build: p4-build _copy_p4c_out _create_mvn_container _mvn_package
	$(info *** ONOS app .oar package created succesfully)
	@ls -1 app/target/*.oar

app-install:
	$(info *** Installing and activating app in ONOS...)
	${onos_curl} -X POST -HContent-Type:application/octet-stream \
		'${onos_url}/v1/applications?activate=true' \
		--data-binary @app/target/srv6-tutorial-1.0-SNAPSHOT.oar
	@echo

app-uninstall:
	$(info *** Uninstalling app from ONOS...)
	-${onos_curl} -X DELETE ${onos_url}/v1/applications/${app_name}
	@echo

app-reload: app-uninstall app-install
