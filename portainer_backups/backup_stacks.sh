#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Config file (sourced if present). By default we look for a config next to the script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CONFIG_FILE="$SCRIPT_DIR/backup_stacks.conf"

# If a config file exists, source it. It may define PORTAINER_URL, PORTAINER_API_KEY, BACKUP_DIR, PORTAINER_VOLUME, ALPINE_IMAGE, etc.
if [ -f "$CONFIG_FILE" ]; then
  # shellcheck source=/dev/null
  . "$CONFIG_FILE"
fi

# Defaults (can be overridden by environment variables or the config file)
: ""  # no-op to ensure last command status for set -e
PORTAINER_URL="${PORTAINER_URL:-https://portainer.example:9443}"
PORTAINER_API_KEY="${PORTAINER_API_KEY:-your_api_key_here}"
BACKUP_DIR="${BACKUP_DIR:-/opt/portainer_backups/backups}"
PORTAINER_VOLUME="${PORTAINER_VOLUME:-portainer_data}"
ALPINE_IMAGE="${ALPINE_IMAGE:-alpine:3.19}"
SIMPLE_MODE="${SIMPLE_MODE:-false}"
SIMPLE_PREFIX="${SIMPLE_PREFIX:-stack_}"

# Helper / environment checks
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is not installed. Please install jq."; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "ERROR: docker is not installed or not in PATH."; exit 1; }

# Ensure backup directory exists
if ! mkdir -p "$BACKUP_DIR"; then
  echo "ERROR: cannot create backup directory '$BACKUP_DIR'"
  exit 1
fi

echo "===== Portainer stacks backup started: $(date --iso-8601=seconds) ====="

# Query Portainer stacks
stacks_json="$(curl -s -k -H "X-API-Key: $PORTAINER_API_KEY" "$PORTAINER_URL/api/stacks")" || {
  echo "ERROR: curl failed when contacting $PORTAINER_URL/api/stacks"
  exit 1
}

# Validate JSON
if ! printf '%s' "$stacks_json" | jq -e . >/dev/null 2>&1; then
  echo "ERROR: received invalid JSON from Portainer API"
  exit 1
fi

# Iterate stacks safely (one stack per line)
printf '%s\n' "$stacks_json" | jq -c '.[]' | while read -r row; do
  # Extract Id and Name (Portainer stack fields)
  id="$(printf '%s' "$row" | jq -r '.Id // .id')"
  name="$(printf '%s' "$row" | jq -r '.Name // .name')"

  # Fallbacks
  if [ -z "$id" ] || [ "$id" = "null" ]; then
    echo "WARN: skipping stack with missing Id (raw: $row)"
    continue
  fi
  if [ -z "$name" ] || [ "$name" = "null" ]; then
    name="stack_$id"
  fi

  # Create a filesystem-safe human-readable filename from the stack name
  # Replace unsafe characters with underscore, collapse multiple underscores, trim leading/trailing underscores.
  safe_name="$(printf '%s' "$name" | sed 's/[^A-Za-z0-9._ -]/_/g' | tr ' ' '_' | sed 's/_\+/_/g' | sed 's/^_//; s/_$//')"
  if [ -z "$safe_name" ]; then
    safe_name="stack_$id"
  fi

  if [ "${SIMPLE_MODE,,}" = "true" ] || [ "${SIMPLE_MODE,,}" = "1" ]; then
    target_filename="${SIMPLE_PREFIX}${id}.yml"
  else
    target_filename="${safe_name}.yml"
  fi
  target_path="$BACKUP_DIR/$target_filename"

  echo "Backing up stack id=$id name='$name' -> $target_path"

  # Build the shell command that will run inside the container.
  # It checks both docker-compose.yml and docker-compose.yaml and copies whichever exists.
  container_sh_cmd="
    set -e
    if [ -f \"/data/compose/$id/docker-compose.yml\" ]; then
      src='/data/compose/$id/docker-compose.yml'
    elif [ -f \"/data/compose/$id/docker-compose.yaml\" ]; then
      src='/data/compose/$id/docker-compose.yaml'
    else
      echo 'ERROR: compose file not found for stack id $id' 1>&2
      exit 2
    fi
    cp \"\$src\" \"/backups/$target_filename\"
  "

  # Run an ephemeral container to copy the file (mount portainer_data read-only, backup dir read-write)
  # Use alpine (small) and POSIX sh
  if docker run --rm -v "$PORTAINER_VOLUME":/data:ro -v "$BACKUP_DIR":/backups:rw "$ALPINE_IMAGE" sh -c "$container_sh_cmd"; then
    echo "OK: wrote $target_path"
  else
    echo "ERROR: failed to copy compose file for stack '$name' (id=$id)" >&2
    # continue with next stack (do not exit the whole script)
  fi
done

echo "===== Portainer stacks backup finished: $(date --iso-8601=seconds) ====="
