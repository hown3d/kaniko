# Copyright 2018 Google, Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
ARG SHADOW_VERSION=v4.11.1
ARG ROOTLESSKIT_VERSION=v1.0.1

FROM golang:1.17
WORKDIR /src

# This arg is passed by docker buildx & contains the target CPU architecture (e.g., amd64, arm64, etc.)
ARG TARGETARCH

ENV GOARCH=$TARGETARCH
ENV CGO_ENABLED=0
ENV GOBIN=/usr/local/bin

# Get GCR credential helper
RUN go install github.com/GoogleCloudPlatform/docker-credential-gcr@4cdd60d0f2d8a69bc70933f4d7718f9c4e956ff8

# Get Amazon ECR credential helper
RUN go install github.com/awslabs/amazon-ecr-credential-helper/ecr-login/cli/docker-credential-ecr-login@69c85dc22db6511932bbf119e1a0cc5c90c69a7f # v0.6.0

# Get ACR docker env credential helper
RUN go install github.com/chrismellard/docker-credential-acr-env@09e2b5a8ac86c3ec347b2473e42b34367d8fa419

# Add .docker config dir
RUN mkdir -p /kaniko/.docker

COPY . .
RUN \
  --mount=type=cache,target=/root/.cache/go-build \
  --mount=type=cache,target=/go/pkg \
  make GOARCH=$TARGETARCH

# Generate latest ca-certificates
FROM debian:bullseye-slim AS certs
RUN apt update && apt install -y ca-certificates


FROM debian:bullseye-slim as rootlesskit
ARG ROOTLESSKIT_VERSION
RUN apt update && apt install -y curl
RUN curl -sSL https://github.com/rootless-containers/rootlesskit/releases/download/${ROOTLESSKIT_VERSION}/rootlesskit-$(uname -m).tar.gz | tar Cxzv /bin

RUN curl -sSL -o /bin/slirp4netns https://github.com/rootless-containers/slirp4netns/releases/download/${SLIRP4NETNS_VERSION}/slirp4netns-x86_64 && \
  chmod +x /bin/slirp4netns
# create subuid mappings
RUN echo "kaniko:100000:65536" > /subuid
RUN echo "kaniko:100000:65536" > /subgid


# idmap runnable without --privileged (but still requires seccomp=unconfined apparmor=unconfined)
FROM alpine AS idmap
ARG SHADOW_VERSION
ENV DEBIAN_FRONTEND=noninteractive
RUN apk add --no-cache automake autoconf gettext git build-base libcap-dev libtool make gettext gettext-dev linux-pam-dev expect byacc
RUN git clone https://github.com/shadow-maint/shadow.git /shadow
WORKDIR /shadow
RUN git fetch && git checkout $SHADOW_VERSION
RUN  ./autogen.sh --disable-nls --disable-man --without-audit --without-selinux --without-acl --without-attr --without-tcb --without-nscd \
  --disable-shared --enable-static=yes 
RUN make && \
  cp src/newuidmap src/newgidmap /bin

FROM debian:bullseye-slim as rootless
COPY --from=idmap /bin/newuidmap /bin/newgidmap /kaniko/
# shadowutils is not a static binary, need to use musl libc
COPY --from=idmap /lib/ld-musl-*.so.1 /lib/libc.musl-*.so.1 /lib/
COPY --from=wildwildangel/setcap-static:sha-5657804 /setcap-static /kaniko/setcap
# set setuid and setgid capabilties on newuidmap and newgidmap
RUN ["/kaniko/setcap", "cap_setuid+eip", "/kaniko/newuidmap"]
RUN ["/kaniko/setcap", "cap_setgid+eip", "/kaniko/newgidmap"]
# use musl busybox since it's staticly compiled
# rootlesskit needs a /tmp directory
RUN --mount=from=busybox:musl,dst=/usr/ ["busybox", "sh", "-c", "touch /etc/passwd /etc/group && mkdir -p /home/kaniko /run/user/1000 /tmp && addgroup -g 1000 kaniko && adduser -u 1000 -h /home/kaniko -G kaniko -D kaniko && chown -R kaniko:kaniko /tmp && chown -R kaniko:kaniko /run/user/1000"]
USER kaniko
COPY --from=rootlesskit /subuid /subgid /etc/
COPY --from=0 /src/out/executor /kaniko/executor
COPY --from=0 /usr/local/bin/docker-credential-gcr /kaniko/docker-credential-gcr
COPY --from=0 /usr/local/bin/docker-credential-ecr-login /kaniko/docker-credential-ecr-login
COPY --from=0 /usr/local/bin/docker-credential-acr-env /kaniko/docker-credential-acr-env
COPY --from=rootlesskit /bin/rootlesskit /kaniko/rootlesskit
COPY --from=rootlesskit /bin/slirp4netns /kaniko/slirp4netns
COPY --from=certs /etc/ssl/certs/ca-certificates.crt /kaniko/ssl/certs/
COPY --from=0 /kaniko/.docker /kaniko/.docker
COPY files/nsswitch.conf /etc/nsswitch.conf
ENV HOME /home/kaniko
ENV USER kaniko
ENV XDG_RUNTIME_DIR=/run/user/1000
ENV PATH /usr/local/bin:/kaniko:/busybox:/bin
ENV SSL_CERT_DIR=/kaniko/ssl/certs
ENV DOCKER_CONFIG /kaniko/.docker/
ENV DOCKER_CREDENTIAL_GCR_CONFIG /kaniko/.config/gcloud/docker_credential_gcr_config.json

WORKDIR /workspace
ENTRYPOINT ["/kaniko/rootlesskit", "/kaniko/executor"]


FROM scratch
# Create kaniko directory with world write permission to allow non root run
# use musl busybox since it's staticly compiled
RUN --mount=from=busybox:musl,dst=/usr/ ["busybox", "sh", "-c", "mkdir -p /kaniko && chmod 777 /kaniko"] 

COPY --from=0 /src/out/executor /kaniko/executor
COPY --from=0 /usr/local/bin/docker-credential-gcr /kaniko/docker-credential-gcr
COPY --from=0 /usr/local/bin/docker-credential-ecr-login /kaniko/docker-credential-ecr-login
COPY --from=0 /usr/local/bin/docker-credential-acr-env /kaniko/docker-credential-acr-env
COPY --from=certs /etc/ssl/certs/ca-certificates.crt /kaniko/ssl/certs/
COPY --from=0 /kaniko/.docker /kaniko/.docker
COPY files/nsswitch.conf /etc/nsswitch.conf
ENV HOME /root
ENV USER root
ENV PATH /usr/local/bin:/kaniko
ENV SSL_CERT_DIR=/kaniko/ssl/certs
ENV DOCKER_CONFIG /kaniko/.docker/
ENV DOCKER_CREDENTIAL_GCR_CONFIG /kaniko/.config/gcloud/docker_credential_gcr_config.json
WORKDIR /workspace

ENTRYPOINT ["/kaniko/executor"]


