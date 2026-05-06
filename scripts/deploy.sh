#!/bin/sh

set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
deploy_dir="$(CDPATH= cd -- "$script_dir/.." && pwd)"
compose_file="$deploy_dir/docker-compose.prod.yml"

if [ ! -f "$deploy_dir/.env" ]; then
  echo "Missing $deploy_dir/.env. Copy compose.env.example and fill image tags first." >&2
  exit 1
fi

if [ ! -f "$deploy_dir/.env.server" ]; then
  echo "Missing $deploy_dir/.env.server. Copy env.server.example and fill runtime secrets first." >&2
  exit 1
fi

cd "$deploy_dir"

docker compose -f "$compose_file" pull
docker compose -f "$compose_file" up --no-deps --abort-on-container-exit migrate
docker compose -f "$compose_file" up -d server admin proxy
docker compose -f "$compose_file" ps

for _ in $(seq 1 12); do
  if curl -fsS http://127.0.0.1/api/health >/dev/null 2>&1; then
    if [ -x "$deploy_dir/scripts/prune-local-images.sh" ]; then
      "$deploy_dir/scripts/prune-local-images.sh"
    else
      echo "Skipping local Docker image prune. prune-local-images.sh not found."
    fi
    exit 0
  fi
  sleep 5
done

curl -fsS http://127.0.0.1/api/health >/dev/null
