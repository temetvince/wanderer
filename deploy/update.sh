#!/bin/bash
# Daily update for a wanderer server running the temetvince forks.
#
# For each fork: mirror the canonical `custom` branch from GitHub, then try to
# rebase it onto the latest upstream main. If the rebase conflicts, fall back
# to building `custom` as-is (yesterday's upstream) and keep running - resolve
# the conflict on a dev machine, push, and the next run picks it up.
#
# One-time server setup:
#   cd /home/ubuntu
#   git clone --branch custom https://github.com/temetvince/wanderer.git
#   git -C wanderer remote add upstream https://github.com/wanderer-industries/wanderer.git
#   git clone --branch custom https://github.com/temetvince/eve-route-builder.git
#   git -C eve-route-builder remote add upstream https://github.com/wanderer-industries/eve-route-builder.git
#   cp wanderer/deploy/docker-compose.override.yml community-edition/
#   cp wanderer/deploy/community-edition.env community-edition/.env   # append instead if .env exists
#   cp wanderer/deploy/update.sh /home/ubuntu/update.sh && chmod +x /home/ubuntu/update.sh

set -euo pipefail

COMPOSE_DIR=/home/ubuntu/community-edition
WANDERER_DIR=/home/ubuntu/wanderer
ROUTE_BUILDER_DIR=/home/ubuntu/eve-route-builder

update_repo() {
  local dir=$1
  echo "=== Updating $dir ==="
  git -C "$dir" fetch origin
  git -C "$dir" checkout custom
  git -C "$dir" reset --hard origin/custom
  git -C "$dir" fetch upstream
  if ! git -C "$dir" rebase upstream/main; then
    git -C "$dir" rebase --abort
    echo "WARNING: $dir: rebase onto upstream/main conflicts."
    echo "         Building from origin/custom WITHOUT today's upstream changes."
    echo "         Resolve on your dev machine, push custom, and rerun."
  fi
}

update_repo "$WANDERER_DIR"
update_repo "$ROUTE_BUILDER_DIR"

# Build before taking the stack down so the old version keeps serving.
docker build -t wanderer-custom:latest "$WANDERER_DIR"
docker build -t eve-route-builder-custom:latest "$ROUTE_BUILDER_DIR"

cd "$COMPOSE_DIR"
git pull

# Pull only the services that still come from Docker Hub; the two custom
# images are local-only and have nothing to pull.
docker compose pull wanderer-kills wanderer_db

docker compose down
docker compose up -d

# Drop dangling layers from superseded builds so disk use stays flat.
docker image prune -f
