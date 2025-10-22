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
API_KEY_HEADER="${API_KEY_HEADER:-X-API-Key}"
COMPOSE_DIR_PREFIX="${COMPOSE_DIR_PREFIX:-/data/compose}"
COMPOSE_CANDIDATES="${COMPOSE_CANDIDATES:-docker-compose.yml docker-compose.yaml}"
CONTAINER_PORTAINER_MOUNT="${CONTAINER_PORTAINER_MOUNT:-/data}"
CONTAINER_BACKUP_MOUNT="${CONTAINER_BACKUP_MOUNT:-/backups}"
USE_TIMESTAMPS="${USE_TIMESTAMPS:-false}"
TIMESTAMP_FMT="${TIMESTAMP_FMT:-_%F_%H%M%S}"

# Helper / environment checks
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is not installed. Please install jq."; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "ERROR: docker is not installed or not in PATH."; exit 1; }

# Ensure backup directory exists
if ! mkdir -p "$BACKUP_DIR"; then
  echo "ERROR: cannot create backup directory '$BACKUP_DIR'"
  exit 1
fi

echo "===== Portainer stacks backup started: $(date --iso-8601=seconds) ====="

# If LOG_FILE is set and LOG_MAX_BYTES>0, perform simple rotation to limit size.
if [ -n "${LOG_FILE:-}" ] && [ "${LOG_MAX_BYTES:-0}" -gt 0 ]; then
  if [ -f "$LOG_FILE" ]; then
    log_size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$log_size" -ge "$LOG_MAX_BYTES" ]; then
      timestamp=$(date +%Y%m%d%H%M%S)
      mv "$LOG_FILE" "${LOG_FILE}.${timestamp}"
      : > "$LOG_FILE" || true
    fi
  else
    : > "$LOG_FILE" || true
  fi
fi

# Query Portainer stacks
# Query Portainer stacks with retries/backoff
stacks_json=""
attempt=0
while [ $attempt -le ${CURL_RETRIES:-3} ]; do
  if stacks_json="$(curl -s -k ${CURL_OPTS:-} -H "${API_KEY_HEADER}: $PORTAINER_API_KEY" "$PORTAINER_URL/api/stacks")"; then
    break
  fi
  attempt=$((attempt + 1))
  echo "WARN: curl attempt $attempt failed, retrying in ${CURL_BACKOFF_SEC:-5}s..."
  sleep ${CURL_BACKOFF_SEC:-5}
done
if [ -z "$stacks_json" ]; then
  echo "ERROR: curl failed to fetch stacks after ${CURL_RETRIES:-3} attempts"
  exit 1
fi

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

  # Build base filename (without timestamp)
  if [ "${SIMPLE_MODE,,}" = "true" ] || [ "${SIMPLE_MODE,,}" = "1" ]; then
    base_filename="${SIMPLE_PREFIX}${id}"
  else
    base_filename="${safe_name}"
  fi

  # Optionally append timestamp
  if [ "${USE_TIMESTAMPS,,}" = "true" ] || [ "${USE_TIMESTAMPS,,}" = "1" ]; then
    ts=$(date +"${TIMESTAMP_FMT}")
    target_filename="${base_filename}${ts}.yml"
  else
    target_filename="${base_filename}.yml"
  fi
  target_path="$BACKUP_DIR/$target_filename"

  echo "Backing up stack id=$id name='$name' -> $target_path"

  # Before copying, ensure there's enough free space on the target mount
  if [ "${MIN_FREE_BYTES:-0}" -gt 0 ]; then
    free_bytes=$(df --output=avail -B1 "$BACKUP_DIR" 2>/dev/null | tail -1 || echo 0)
    if [ "$free_bytes" -lt "$MIN_FREE_BYTES" ]; then
      echo "ERROR: insufficient free space in $BACKUP_DIR (have $free_bytes < need $MIN_FREE_BYTES). Skipping $id" >&2
      continue
    fi
  fi

  # Build the shell command that will run inside the container.
  # It checks candidate compose filenames under the configured compose prefix and copies the first that exists.
  container_sh_cmd="set -e\n"
  for candidate in $COMPOSE_CANDIDATES; do
    container_sh_cmd+="if [ -f \"${COMPOSE_DIR_PREFIX}/$id/$candidate\" ]; then src='${COMPOSE_DIR_PREFIX}/$id/$candidate'; fi\n"
    container_sh_cmd+="[ -n \"\$src\" ] && cp \"\$src\" \"${CONTAINER_BACKUP_MOUNT}/$target_filename\" && exit 0\n"
  done
  container_sh_cmd+="echo 'ERROR: compose file not found for stack id $id' 1>&2\nexit 2\n"

  # Run an ephemeral container to copy the file (mount portainer_data read-only, backup dir read-write)
  # Use alpine (small) and POSIX sh
  # Run with retries for docker copy
  copy_ok=1
  dr_attempt=0
  while [ $dr_attempt -le ${DOCKER_RETRIES:-2} ]; do
    if docker run --rm -v "$PORTAINER_VOLUME":"$CONTAINER_PORTAINER_MOUNT":ro -v "$BACKUP_DIR":"$CONTAINER_BACKUP_MOUNT":rw "$ALPINE_IMAGE" sh -c "$container_sh_cmd"; then
      copy_ok=0
      break
    fi
    dr_attempt=$((dr_attempt + 1))
    echo "WARN: docker copy attempt $dr_attempt failed for stack $id, retrying in ${DOCKER_BACKOFF_SEC:-5}s..." >&2
    sleep ${DOCKER_BACKOFF_SEC:-5}
  done
  if [ $copy_ok -ne 0 ]; then
    echo "ERROR: failed to copy compose file for stack '$name' (id=$id) after ${DOCKER_RETRIES:-2} attempts" >&2
    continue
  fi

  # Verify the file was written and is not empty
  if [ ! -f "$target_path" ] || [ ! -s "$target_path" ]; then
    echo "ERROR: target file $target_path missing or empty after copy" >&2
    continue
  fi

  echo "OK: wrote $target_path"

  # Rotation: if KEEP_COUNT > 0, keep last N files per stack (by filename prefix)
  if [ "${KEEP_COUNT:-0}" -gt 0 ]; then
    # Build a glob pattern for this stack's files. If SIMPLE_MODE use prefix+id, else use the safe_name base.
    if [ "${SIMPLE_MODE,,}" = "true" ] || [ "${SIMPLE_MODE,,}" = "1" ]; then
      pattern="$BACKUP_DIR/${SIMPLE_PREFIX}${id}*"
    else
      pattern="$BACKUP_DIR/${safe_name}*"
    fi
    # List files sorted by mtime (newest first) then remove files beyond KEEP_COUNT
    files=( $(ls -1t $pattern 2>/dev/null || true) )
    if [ ${#files[@]} -gt ${KEEP_COUNT:-0} ]; then
      # Remove the oldest ones (from index KEEP_COUNT onwards)
      for ((i=${KEEP_COUNT:-0}; i<${#files[@]}; i++)); do
        rm -f "${files[$i]}" || echo "WARN: failed to remove old backup ${files[$i]}"
      done
    fi
  fi
done

echo "===== Portainer stacks backup finished: $(date --iso-8601=seconds) ====="
