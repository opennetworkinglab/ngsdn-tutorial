# Copyright 2019-present Open Networking Foundation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Docker image that extends opennetworking/mn-stratum with other dependencies
# required by this tutorial. opennetworking/mn-stratum is the official image
# from the Stratum project which contains stratum_bmv2 and the Mininet
# libraries. We extend that with PTF, scapy, etc.

ARG MN_STRATUM_SHA="sha256:1bba2e2c06460c73b0133ae22829937786217e5f20f8f80fcc3063dcf6707ebe"

FROM bitnami/minideb:stretch as builder

ENV BUILD_DEPS \
    python-pip \
    python-setuptools \
    git
RUN install_packages $BUILD_DEPS

RUN mkdir -p /ouput

ENV PIP_DEPS \
    scapy==2.4.3 \
    git+https://github.com/p4lang/ptf.git \
    googleapis-common-protos==1.6.0 \
    ipaddress
RUN pip install --no-cache-dir --root /output $PIP_DEPS

FROM opennetworking/mn-stratum:latest@$MN_STRATUM_SHA as runtime

ENV RUNTIME_DEPS \
    make
RUN install_packages $RUNTIME_DEPS

COPY --from=builder /output /

ENV DOCKER_RUN true

ENTRYPOINT []
