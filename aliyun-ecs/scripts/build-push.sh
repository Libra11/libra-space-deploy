#!/bin/sh

set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
repo_root="$(CDPATH= cd -- "$script_dir/../../.." && pwd)"

require_env() {
  name="$1"
  eval "value=\${$name:-}"
  if [ -z "$value" ]; then
    echo "Missing required environment variable: $name" >&2
    exit 1
  fi
}

require_env ACR_REGISTRY
require_env ACR_NAMESPACE
require_env VERSION

server_image="$ACR_REGISTRY/$ACR_NAMESPACE/libra-space-server:$VERSION"
admin_image="$ACR_REGISTRY/$ACR_NAMESPACE/libra-space-admin:$VERSION"

docker_build() {
  image="$1"
  context="$2"
  build_args=""

  if [ -n "${NODE_IMAGE:-}" ]; then
    build_args="--build-arg NODE_IMAGE=$NODE_IMAGE"
  fi
  if [ -n "${NGINX_IMAGE:-}" ]; then
    build_args="$build_args --build-arg NGINX_IMAGE=$NGINX_IMAGE"
  fi

  if [ -n "${BUILD_PLATFORM:-}" ]; then
    docker build --platform "$BUILD_PLATFORM" $build_args -t "$image" "$context"
  else
    docker build $build_args -t "$image" "$context"
  fi
}

docker_build "$server_image" "$repo_root/libra-space-server"
docker_build "$admin_image" "$repo_root/libra-space-admin"

docker push "$server_image"
docker push "$admin_image"

cat <<EOF
SERVER_IMAGE=$server_image
ADMIN_IMAGE=$admin_image
EOF
