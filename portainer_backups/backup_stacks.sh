#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Show usage information
show_usage() {
  cat << EOF
Usage: $0 [OPTIONS]

Backup Portainer stacks (compose files and environment variables).

OPTIONS:
  -u, --url URL              Portainer URL (default: https://portainer.example:9443)
  -k, --api-key KEY          Portainer API key (required)
  -d, --backup-dir DIR       Backup directory (default: /opt/portainer_backups/backups)
  -v, --volume NAME          Portainer data volume name (default: portainer_data)
  -i, --image IMAGE          Alpine image for file operations (default: alpine:3.19)
  -s, --simple               Use simple mode (stack ID filenames)
  -p, --prefix PREFIX        Simple mode filename prefix (default: stack_)
  -t, --timestamps           Append timestamps to filenames
  -f, --timestamp-fmt FMT    Timestamp format (default: _%F_%H%M%S)
  -e, --backup-envs          Backup environment variables via API
  -n, --dry-run              Show what would be done without making changes
  -c, --keep-count N         Keep last N backup runs per stack (default: 7)
  -r, --curl-retries N       Curl retry attempts (default: 3)
  -b, --curl-backoff N       Curl backoff seconds (default: 5)
  -m, --min-free-bytes N     Minimum free bytes required (default: 10485760)
  -l, --log-max-bytes N      Log rotation size limit (default: 5242880)
  -o, --docker-retries N     Docker copy retry attempts (default: 2)
  -w, --docker-backoff N     Docker backoff seconds (default: 5)
  -g, --log-file FILE        Log file path (default: /var/log/portainer_backup.log)
  -a, --api-header HEADER    API key header name (default: X-API-Key)
  -x, --compose-prefix PATH  Compose directory prefix (default: /data/compose)
  -y, --compose-candidates LIST  Space-separated compose filenames (default: docker-compose.yml docker-compose.yaml)
  -z, --curl-opts OPTS       Additional curl options
  -h, --help                 Show this help message

EXAMPLES:
  $0 -u https://portainer.local:9443 -k myapikey123 -d /backup/portainer
  $0 --url https://portainer.local:9443 --api-key myapikey123 --simple --timestamps
  $0 -u https://portainer.local:9443 -k myapikey123 --dry-run

EOF
}

# Parse command line arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -u|--url)
        PORTAINER_URL="$2"
        shift 2
        ;;
      -k|--api-key)
        PORTAINER_API_KEY="$2"
        shift 2
        ;;
      -d|--backup-dir)
        BACKUP_DIR="$2"
        shift 2
        ;;
      -v|--volume)
        PORTAINER_VOLUME="$2"
        shift 2
        ;;
      -i|--image)
        ALPINE_IMAGE="$2"
        shift 2
        ;;
      -s|--simple)
        SIMPLE_MODE="true"
        shift
        ;;
      -p|--prefix)
        SIMPLE_PREFIX="$2"
        shift 2
        ;;
      -t|--timestamps)
        USE_TIMESTAMPS="true"
        shift
        ;;
      -f|--timestamp-fmt)
        TIMESTAMP_FMT="$2"
        shift 2
        ;;
      -e|--backup-envs)
        BACKUP_ENVS="true"
        shift
        ;;
      -n|--dry-run)
        DRY_RUN="true"
        shift
        ;;
      -c|--keep-count)
        KEEP_COUNT="$2"
        shift 2
        ;;
      -r|--curl-retries)
        CURL_RETRIES="$2"
        shift 2
        ;;
      -b|--curl-backoff)
        CURL_BACKOFF_SEC="$2"
        shift 2
        ;;
      -m|--min-free-bytes)
        MIN_FREE_BYTES="$2"
        shift 2
        ;;
      -l|--log-max-bytes)
        LOG_MAX_BYTES="$2"
        shift 2
        ;;
      -o|--docker-retries)
        DOCKER_RETRIES="$2"
        shift 2
        ;;
      -w|--docker-backoff)
        DOCKER_BACKOFF_SEC="$2"
        shift 2
        ;;
      -g|--log-file)
        LOG_FILE="$2"
        shift 2
        ;;
      -a|--api-header)
        API_KEY_HEADER="$2"
        shift 2
        ;;
      -x|--compose-prefix)
        COMPOSE_DIR_PREFIX="$2"
        shift 2
        ;;
      -y|--compose-candidates)
        COMPOSE_CANDIDATES="$2"
        shift 2
        ;;
      -z|--curl-opts)
        CURL_OPTS="$2"
        shift 2
        ;;
      -h|--help)
        show_usage
        exit 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        show_usage >&2
        exit 1
        ;;
    esac
  done
}

# Set defaults
# Set defaults
PORTAINER_URL="${PORTAINER_URL:-https://portainer.example:9443}"
PORTAINER_API_KEY="${PORTAINER_API_KEY:-}"
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
BACKUP_ENVS="${BACKUP_ENVS:-false}"
DRY_RUN="${DRY_RUN:-false}"
KEEP_COUNT="${KEEP_COUNT:-7}"
CURL_RETRIES="${CURL_RETRIES:-3}"
CURL_BACKOFF_SEC="${CURL_BACKOFF_SEC:-5}"
MIN_FREE_BYTES="${MIN_FREE_BYTES:-10485760}"
LOG_MAX_BYTES="${LOG_MAX_BYTES:-5242880}"
DOCKER_RETRIES="${DOCKER_RETRIES:-2}"
DOCKER_BACKOFF_SEC="${DOCKER_BACKOFF_SEC:-5}"
LOG_FILE="${LOG_FILE:-/var/log/portainer_backup.log}"
CURL_OPTS="${CURL_OPTS:-}"

# Parse command line arguments
parse_args "$@"

# Validate required arguments
if [ -z "$PORTAINER_API_KEY" ]; then
  echo "ERROR: API key is required. Use -k/--api-key or set PORTAINER_API_KEY environment variable." >&2
  exit 1
fi

# Helper / environment checks
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is not installed. Please install jq."; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "ERROR: docker is not installed or not in PATH."; exit 1; }

# Ensure backup directory exists
if ! mkdir -p "$BACKUP_DIR"; then
  echo "ERROR: cannot create backup directory '$BACKUP_DIR'"
  exit 1
fi

echo "===== Portainer stacks backup started: $(date --iso-8601=seconds) ====="

# Show dry run status
if [ "${DRY_RUN,,}" = "true" ] || [ "${DRY_RUN,,}" = "1" ]; then
  echo "DRY RUN MODE: No files will be created, modified, or deleted"
fi

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

  # Prepare stack directory and filenames
  stack_dir="$BACKUP_DIR/$base_filename"
  if [ "${DRY_RUN,,}" != "true" ] && [ "${DRY_RUN,,}" != "1" ]; then
    if ! mkdir -p "$stack_dir" >/dev/null 2>&1; then
      echo "ERROR: cannot create stack directory '$stack_dir'" >&2
      continue
    fi
  else
    echo "DRY RUN: would create directory '$stack_dir'"
  fi

  # Optionally append timestamp
  if [ "${USE_TIMESTAMPS,,}" = "true" ] || [ "${USE_TIMESTAMPS,,}" = "1" ]; then
    ts=$(date +"${TIMESTAMP_FMT}")
    target_filename="${base_filename}${ts}.yml"
    env_filename="${base_filename}${ts}.env"
    json_filename="${base_filename}${ts}.stack.json"
  else
    target_filename="${base_filename}.yml"
    env_filename="${base_filename}.env"
    json_filename="${base_filename}.stack.json"
  fi
  target_path="$stack_dir/$target_filename"
  env_path="$stack_dir/$env_filename"
  json_path="$stack_dir/$json_filename"

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
  # It copies the first candidate compose file it finds and prints its checksum and size: "<checksum|NO_CHECKSUM> <size>"
  container_sh_cmd="set -e\n"
  for candidate in $COMPOSE_CANDIDATES; do
    container_sh_cmd+="if [ -f \"${COMPOSE_DIR_PREFIX}/$id/$candidate\" ]; then src='${COMPOSE_DIR_PREFIX}/$id/$candidate'; fi\n"
  container_sh_cmd+="if [ -n \"\$src\" ]; then\n"
  container_sh_cmd+="  cp \"\$src\" \"${CONTAINER_BACKUP_MOUNT}/${base_filename}/$target_filename\" || exit 3\n"
    container_sh_cmd+="  size=\$(stat -c%s \"\$src\" 2>/dev/null || (ls -ln \"\$src\" | awk '{print \$5}'))\n"
    container_sh_cmd+="  if command -v sha256sum >/dev/null 2>&1; then checksum=\$(sha256sum \"\$src\" | awk '{print \$1}'); elif command -v shasum >/dev/null 2>&1; then checksum=\$(shasum -a 256 \"\$src\" | awk '{print \$1}'); else checksum=NO_CHECKSUM; fi\n"
    container_sh_cmd+="  echo \"$checksum $size\"\n"
    container_sh_cmd+="  exit 0\n"
    container_sh_cmd+="fi\n"
  done
  container_sh_cmd+="echo 'ERROR: compose file not found for stack id $id' 1>&2\nexit 2\n"

  # Run an ephemeral container to copy the file (mount portainer_data read-only, backup dir read-write)
  # Use alpine (small) and POSIX sh
  # Run with retries for docker copy + verification
  copy_ok=1
  dr_attempt=0
  while [ $dr_attempt -le ${DOCKER_RETRIES:-2} ]; do
    if [ "${DRY_RUN,,}" = "true" ] || [ "${DRY_RUN,,}" = "1" ]; then
      echo "DRY RUN: would copy compose file to $target_path"
      copy_ok=0
      break
    fi
    # Run container and capture output (stdout/stderr)
    container_out=""
    rc=0
  container_out=$(docker run --rm -v "$PORTAINER_VOLUME":"$CONTAINER_PORTAINER_MOUNT":ro -v "$BACKUP_DIR":"$CONTAINER_BACKUP_MOUNT":rw "$ALPINE_IMAGE" sh -c "$container_sh_cmd" 2>&1) || rc=$?
    if [ $rc -ne 0 ]; then
      echo "WARN: docker run failed (exit $rc). Output:\n$container_out" >&2
      dr_attempt=$((dr_attempt + 1))
      sleep ${DOCKER_BACKOFF_SEC:-5}
      continue
    fi

    # container_out should contain: <checksum_or_NO_CHECKSUM> <size>
    container_checksum=$(printf '%s' "$container_out" | tr -d '\r' | awk '{print $1}')
    container_size=$(printf '%s' "$container_out" | tr -d '\r' | awk '{print $2}')

    # Compute host-side checksum if container provided one
    host_checksum=""
    if [ "$container_checksum" != "NO_CHECKSUM" ] && [ -n "$container_checksum" ]; then
      if command -v sha256sum >/dev/null 2>&1; then
        host_checksum=$(sha256sum "$target_path" 2>/dev/null | awk '{print $1}' || true)
      elif command -v shasum >/dev/null 2>&1; then
        host_checksum=$(shasum -a 256 "$target_path" 2>/dev/null | awk '{print $1}' || true)
      fi
    fi
    host_size=$(stat -c%s "$target_path" 2>/dev/null || echo 0)

    if [ -n "$container_checksum" ] && [ "$container_checksum" != "NO_CHECKSUM" ] && [ -n "$host_checksum" ]; then
      if [ "$container_checksum" = "$host_checksum" ]; then
        copy_ok=0
        break
      else
        echo "WARN: checksum mismatch for $target_path (container:$container_checksum host:$host_checksum)" >&2
      fi
    else
      # Fallback to size comparison
      if [ "$container_size" -eq "$host_size" ] && [ "$host_size" -gt 0 ]; then
        copy_ok=0
        break
      else
        echo "WARN: size mismatch for $target_path (container:$container_size host:$host_size)" >&2
      fi
    fi

    dr_attempt=$((dr_attempt + 1))
    echo "WARN: verification failed for stack $id, retrying in ${DOCKER_BACKOFF_SEC:-5}s..." >&2
    sleep ${DOCKER_BACKOFF_SEC:-5}
  done
    if [ $copy_ok -ne 0 ]; then
      echo "ERROR: failed to copy and verify compose file for stack '$name' (id=$id) after ${DOCKER_RETRIES:-2} attempts" >&2
      continue
    fi

    echo "OK: wrote $target_path"

  # Back up env variables via Portainer API if enabled
  if [ "${BACKUP_ENVS:-false}" = "true" ] || [ "${BACKUP_ENVS:-false}" = "1" ]; then
    if [ "${DRY_RUN,,}" = "true" ] || [ "${DRY_RUN,,}" = "1" ]; then
      echo "DRY RUN: would fetch stack JSON and extract env variables to $env_path"
    else
      # Fetch stack JSON from Portainer and save raw
      stack_json=""
      sj_attempt=0
      while [ $sj_attempt -le ${CURL_RETRIES:-3} ]; do
        if stack_json="$(curl -s -k ${CURL_OPTS:-} -H "${API_KEY_HEADER}: $PORTAINER_API_KEY" "$PORTAINER_URL/api/stacks/$id")"; then
          break
        fi
        sj_attempt=$((sj_attempt + 1))
        sleep ${CURL_BACKOFF_SEC:-5}
      done
      if [ -n "$stack_json" ]; then
        printf '%s\n' "$stack_json" > "$json_path" 2>/dev/null || true
        # Try to extract envs: strings or objects
        if printf '%s\n' "$stack_json" | jq -r '.Env[]? | if type=="string" then . else ((.name//.Name) + "=" + (.value//.Value//"")) end' > "$env_path" 2>/dev/null; then
          chmod 600 "$env_path" || true
        else
          # if jq extraction failed, ensure an empty file isn't left
          : > "$env_path" || true
          rm -f "$env_path" || true
        fi
      else
        echo "WARN: could not fetch stack JSON for $id; skipping env backup" >&2
      fi
    fi
  fi

  # Rotation: keep last N backup runs per stack (grouped by core filename)
  if [ "${KEEP_COUNT:-0}" -gt 0 ]; then
    if [ "${DRY_RUN,,}" = "true" ] || [ "${DRY_RUN,,}" = "1" ]; then
      echo "DRY RUN: would perform rotation in $stack_dir (keep ${KEEP_COUNT} runs)"
      # Still show what would be deleted for dry run
      if [ -d "$stack_dir" ]; then
        declare -A run_groups
        for f in "$stack_dir"/${base_filename}*.*; do
          [ -e "$f" ] || continue
          name=$(basename -- "$f")
          
          # Parse timestamp if USE_TIMESTAMPS is enabled
          if [ "${USE_TIMESTAMPS,,}" = "true" ] || [ "${USE_TIMESTAMPS,,}" = "1" ]; then
            # Extract timestamp pattern from filename
            # Remove base_filename prefix and extension suffix to get timestamp part
            temp="${name#${base_filename}}"
            run_id="${temp%.*}"
            if [ -z "$run_id" ]; then
              run_id="notimestamp"
            fi
          else
            # Group by core filename (without extension)
            run_id="${name%.*}"
          fi
          
          # Track newest mtime for this run
          mtime=$(stat -c %Y "$f" 2>/dev/null || echo 0)
          if [ -z "${run_groups[$run_id]:-}" ] || [ "$mtime" -gt "${run_groups[$run_id]}" ]; then
            run_groups["$run_id"]=$mtime
          fi
        done
        
        # Sort runs by mtime and show what would be deleted
        if [ ${#run_groups[@]} -gt 0 ]; then
          runs_sorted=( $(for k in "${!run_groups[@]}"; do echo "${run_groups[$k]}::$k"; done | sort -r -n | awk -F:: '{print $2}') )
          if [ ${#runs_sorted[@]} -gt ${KEEP_COUNT:-0} ]; then
            echo "DRY RUN: would delete $(( ${#runs_sorted[@]} - ${KEEP_COUNT:-0} )) old backup runs:"
            for ((i=${KEEP_COUNT:-0}; i<${#runs_sorted[@]}; i++)); do
              for ext_file in "$stack_dir/${base_filename}${runs_sorted[$i]}".*; do
                [ -e "$ext_file" ] && echo "  would delete: $(basename "$ext_file")"
              done
            done
          fi
        fi
      fi
    else
      # Actual rotation logic
      declare -A run_groups
      for f in "$stack_dir"/${base_filename}*.*; do
        [ -e "$f" ] || continue
        name=$(basename -- "$f")
        
        # Parse timestamp if USE_TIMESTAMPS is enabled
        if [ "${USE_TIMESTAMPS,,}" = "true" ] || [ "${USE_TIMESTAMPS,,}" = "1" ]; then
          # Extract timestamp pattern from filename
          # Remove base_filename prefix and extension suffix to get timestamp part
          temp="${name#${base_filename}}"
          run_id="${temp%.*}"
          if [ -z "$run_id" ]; then
            run_id="notimestamp"
          fi
        else
          # Group by core filename (without extension)
          run_id="${name%.*}"
        fi
        
        # Track newest mtime for this run
        mtime=$(stat -c %Y "$f" 2>/dev/null || echo 0)
        if [ -z "${run_groups[$run_id]:-}" ] || [ "$mtime" -gt "${run_groups[$run_id]}" ]; then
          run_groups["$run_id"]=$mtime
        fi
      done

      # Sort runs by mtime desc and remove old ones
      if [ ${#run_groups[@]} -gt 0 ]; then
        runs_sorted=( $(for k in "${!run_groups[@]}"; do echo "${run_groups[$k]}::$k"; done | sort -r -n | awk -F:: '{print $2}') )
        if [ ${#runs_sorted[@]} -gt ${KEEP_COUNT:-0} ]; then
          for ((i=${KEEP_COUNT:-0}; i<${#runs_sorted[@]}; i++)); do
            rm -f "$stack_dir/${base_filename}${runs_sorted[$i]}".* || echo "WARN: failed to remove old backup files for ${runs_sorted[$i]}"
          done
        fi
      fi
    fi
  fi
done

echo "===== Portainer stacks backup finished: $(date --iso-8601=seconds) ====="
