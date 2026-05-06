#!/bin/sh

set -eu

prune_enabled="${PRUNE_LOCAL_IMAGES:-true}"
prune_until="${PRUNE_LOCAL_IMAGES_UNTIL:-168h}"

case "$prune_enabled" in
  true|TRUE|1|yes|YES)
    ;;
  *)
    echo "Skipping local Docker image prune. PRUNE_LOCAL_IMAGES=$prune_enabled"
    exit 0
    ;;
esac

if ! command -v docker >/dev/null 2>&1; then
  echo "Skipping local Docker image prune. docker command not found."
  exit 0
fi

echo "Pruning unused Docker images older than $prune_until."
docker image prune -af --filter "until=$prune_until" || {
  echo "Docker image prune failed; deployment has already completed." >&2
  exit 0
}
