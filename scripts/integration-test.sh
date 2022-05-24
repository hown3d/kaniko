#!/bin/bash
# Copyright 2018 Google LLC
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

set -e

function start_local_registry {
  docker start registry || docker run --name registry -d -p 5000:5000 registry:2
}

function start_fake_gcs_server {
  # run in network host, because kaniko will be run there too
  docker start fake-gcs-server || docker run -d --net=host --name fake-gcs-server fsouza/fake-gcs-server -scheme http
}

GCS_BUCKET="${GCS_BUCKET:-kaniko-test-bucket}"
IMAGE_REPO="${IMAGE_REPO:-gcr.io/kaniko-test}"

docker version

echo "Running integration tests..."
make out/executor
make out/warmer

if [[ -n $LOCAL ]]; then
 echo "running in local mode, mocking registry and gcs bucket..."
  start_local_registry
  start_fake_gcs_server
  IMAGE_REPO="localhost:5000/kaniko-test"
  go test -v ./integration/... --bucket "${GCS_BUCKET}" --repo "${IMAGE_REPO}" --timeout 50m --gcs-endpoint "http://fake-gcs-server:4443" --disable-gcs-auth "$@" 
else
  go test -v ./integration/... --bucket "${GCS_BUCKET}" --repo "${IMAGE_REPO}" --timeout 50m "$@"
fi
