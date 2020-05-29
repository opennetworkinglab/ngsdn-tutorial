include Makefile.vars

build: build-stratum_bmv2 build-mvn
push: push-stratum_bmv2 push-mvn

build-stratum_bmv2:
	cd stratum_bmv2 && docker build -t ${STRATUM_BMV2_IMG} .

build-mvn:
	cd ../../app && docker build --squash -f ../util/docker/mvn/Dockerfile \
		-t ${MVN_IMG} .

push-stratum_bmv2:
	# Remember to update Makefile.vars with the new image sha
	docker push ${STRATUM_BMV2_IMG}

push-mvn:
	# Remember to update Makefile.vars with the new image sha
	docker push ${MVN_IMG}
