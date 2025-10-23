#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Show usage information
show_usage() {
  cat << EOF
Usage: backup_stacks.sh -d BACKUP_DIR [OPTIONS]

Backup Portainer stacks by reading directly from the Portainer database.

REQUIRED:
  -d, --backup-dir DIR       Backup directory (where to save backups)

OPTIONS:
  -v, --volume NAME          Portainer data volume name (default: portainer_data)
  -s, --simple               Use simple mode (stack ID filenames instead of names)
  -e, --backup-envs          Backup environment variables from database
  -n, --dry-run              Show what would be done without making changes
  -c, --keep-count N         Keep last N backup runs per stack (default: 7)
  -h, --help                 Show this help message

EXAMPLES:
  backup_stacks.sh -d /backup/portainer -e
  backup_stacks.sh --backup-dir /backup/portainer --simple --backup-envs
  backup_stacks.sh -v portainer_data -d /backup/portainer --dry-run
  backup_stacks.sh -d /backup/portainer --simple --keep-count 14

EOF
}

# Parse command line arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -d|--backup-dir)
        BACKUP_DIR="$2"
        shift 2
        ;;
      -v|--volume)
        PORTAINER_VOLUME="$2"
        shift 2
        ;;
      -s|--simple)
        SIMPLE_MODE="true"
        shift
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
BACKUP_DIR="${BACKUP_DIR:-}"  # No default - user must specify
PORTAINER_VOLUME="${PORTAINER_VOLUME:-portainer_data}"
SIMPLE_MODE="${SIMPLE_MODE:-false}"
BACKUP_ENVS="${BACKUP_ENVS:-false}"
DRY_RUN="${DRY_RUN:-false}"
KEEP_COUNT="${KEEP_COUNT:-7}"

# Internal constants (not configurable via CLI)
ALPINE_IMAGE="alpine:3.19"
SIMPLE_PREFIX="stack_"
PORTAINER_DB_PATH="/data/portainer.db"
COMPOSE_DIR_PREFIX="/data/compose"
COMPOSE_CANDIDATES="docker-compose.yml docker-compose.yaml"
CONTAINER_PORTAINER_MOUNT="/data"
CONTAINER_BACKUP_MOUNT="/backups"
DOCKER_RETRIES=2
DOCKER_BACKOFF_SEC=5

# Parse command line arguments
parse_args "$@"

# Validate required arguments
if [ -z "$BACKUP_DIR" ]; then
  echo "ERROR: Backup directory is required. Use -d/--backup-dir to specify where to save backups." >&2
  echo "" >&2
  echo "Example: $0 -d /mnt/nas/portainer-backups --backup-envs" >&2
  echo "" >&2
  echo "For help: $0 --help" >&2
  exit 1
fi

# Helper / environment checks
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is not installed. Please install jq."; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "ERROR: docker is not installed or not in PATH."; exit 1; }

# Ensure backup directory exists
if ! mkdir -p "$BACKUP_DIR"; then
  echo "ERROR: cannot create backup directory '$BACKUP_DIR'" >&2
  echo "Make sure the path is valid and you have write permissions." >&2
  exit 1
fi

echo "===== Portainer stacks backup started: $(date --iso-8601=seconds) ====="

# Show dry run status
if [ "${DRY_RUN,,}" = "true" ] || [ "${DRY_RUN,,}" = "1" ]; then
  echo "DRY RUN MODE: No files will be created, modified, or deleted"
fi

# Read stacks from Portainer database
echo "INFO: Reading stacks from Portainer database..."

# Extract stack JSON objects from the database using strings command
# The database stores stack data as JSON strings that we can extract
# We extract the raw JSON from the container, then process with jq on the host
raw_stacks=$(docker run --rm -v "$PORTAINER_VOLUME:$CONTAINER_PORTAINER_MOUNT" "$ALPINE_IMAGE" sh -c "
  if [ ! -f '$PORTAINER_DB_PATH' ]; then
    echo 'ERROR: Portainer database not found at $PORTAINER_DB_PATH' >&2
    exit 1
  fi
  
  # Extract all stack JSON objects from the database
  # Stack entries contain \"Type\":2 and \"ProjectPath\":
  # Some lines may have leading characters (garbage from binary), so we strip them
  strings '$PORTAINER_DB_PATH' | grep '\"Type\":2' | grep '\"ProjectPath\":' | sed 's/^[^{]*//'
" 2>/dev/null)

# Process with jq on the host (where jq is installed)
stacks_json=$(echo "$raw_stacks" | jq -c 'select(.Type == 2 and .ProjectPath != null)' 2>/dev/null | jq -s '.')

if [ -z "$stacks_json" ] || [ "$stacks_json" = "[]" ]; then
  echo "ERROR: No stacks found in Portainer database"
  exit 1
fi

echo "INFO: Found $(echo "$stacks_json" | jq '. | length') stacks in database"

# Iterate stacks safely (one stack per line)
printf '%s\n' "$stacks_json" | jq -c '.[]' | while read -r row; do
  # Extract stack information from database JSON
  id="$(printf '%s' "$row" | jq -r '.Id')"
  name="$(printf '%s' "$row" | jq -r '.Name')"
  
  # Store the full row for later use (env vars extraction)
  stack_data="$row"

  # Validation
  if [ -z "$id" ] || [ "$id" = "null" ]; then
    echo "WARN: skipping stack with missing Id"
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

  # Set filenames (always with timestamp for rotation)
  ts=$(date +"_%F_%H%M%S")
  target_filename="${base_filename}${ts}.yml"
  env_filename="${base_filename}${ts}.env"
  json_filename="${base_filename}${ts}.stack.json"
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
    container_sh_cmd+="  echo \"\$checksum \$size\"\n"
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

  # Back up env variables from database if enabled
  if [ "${BACKUP_ENVS:-false}" = "true" ] || [ "${BACKUP_ENVS:-false}" = "1" ]; then
    if [ "${DRY_RUN,,}" = "true" ] || [ "${DRY_RUN,,}" = "1" ]; then
      echo "DRY RUN: would extract env variables from database to $env_path"
    else
      # Save full stack JSON from database
      printf '%s\n' "$stack_data" > "$json_path" 2>/dev/null || true
      
      # Extract environment variables from the Env array in the database JSON
      # Format: [{"name":"VAR","value":"val"},...] or ["VAR=val",...]
      if printf '%s\n' "$stack_data" | jq -r '.Env[]? | if type=="string" then . else ((.name//.Name) + "=" + (.value//.Value//"")) end' > "$env_path" 2>/dev/null; then
        chmod 600 "$env_path" || true
        echo "OK: extracted environment variables to $env_path"
      else
        # No env vars or extraction failed
        : > "$env_path" || true
        rm -f "$env_path" || true
      fi
    fi
  fi

  # Rotation: keep last N backup runs per stack (grouped by timestamp)
  if [ "${KEEP_COUNT:-0}" -gt 0 ]; then
    if [ "${DRY_RUN,,}" = "true" ] || [ "${DRY_RUN,,}" = "1" ]; then
      echo "DRY RUN: would perform rotation in $stack_dir (keep ${KEEP_COUNT} runs)"
      # Still show what would be deleted for dry run
      if [ -d "$stack_dir" ]; then
        declare -A run_groups
        for f in "$stack_dir"/${base_filename}*.*; do
          [ -e "$f" ] || continue
          name=$(basename -- "$f")
          
          # Extract timestamp from filename (always present now)
          temp="${name#${base_filename}}"
          run_id="${temp%.*}"
          if [ -z "$run_id" ]; then
            run_id="notimestamp"
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
        
        # Extract timestamp from filename (always present)
        # Remove base_filename prefix and extension suffix to get timestamp part
        temp="${name#${base_filename}}"
        run_id="${temp%.*}"
        if [ -z "$run_id" ]; then
          run_id="notimestamp"
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
