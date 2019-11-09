include Makefile.vars

build: build-ptf build-mvn
push: push-ptf push-mvn

build-ptf:
	cd ptf && docker build --build-arg MN_STRATUM_SHA=$(MN_STRATUM_SHA) \
		-t ${PTF_IMG} .

build-mvn:
	cd ../../app && docker build --squash -f ../util/docker/mvn/Dockerfile \
		-t ${MVN_IMG} .

push-ptf:
	# Remember to update Makefile.vars with the new image sha
	docker push ${PTF_IMG}

push-mvn:
	# Remember to update Makefile.vars with the new image sha
	docker push ${MVN_IMG}