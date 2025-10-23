# Portainer stacks backup

This directory contains a script to back up Portainer stack compose files and environment variables into organized backup directories.

Files

- `backup_stacks.sh` - main backup script. Use command line arguments to configure behavior.
- `install.sh` - helper to install the script into `/opt/portainer_backups/` and set permissions.

Usage

Run the script with command line arguments:

```bash
# Basic usage
./backup_stacks.sh -u https://portainer.local:9443 -k your_api_key_here

# Full example with options
./backup_stacks.sh \
  --url https://portainer.local:9443 \
  --api-key your_api_key_here \
  --backup-dir /opt/portainer_backups/backups \
  --simple \
  --timestamps \
  --backup-envs \
  --keep-count 14

# Dry run to test configuration
./backup_stacks.sh -u https://portainer.local:9443 -k your_api_key_here --dry-run
```

Cron

Use the following crontab line to run the backup daily at 03:00:

```bash
0 3 * * * /opt/portainer_backups/backup_stacks.sh -u https://portainer.local:9443 -k your_api_key -e -t >> /var/log/portainer_backup.log 2>&1
```

Command line options

- `-u, --url`: Portainer URL (required)
- `-k, --api-key`: Portainer API key (required)
- `-d, --backup-dir`: Directory where backups are stored
- `-s, --simple`: Use simple mode (stack ID filenames instead of names)
- `-t, --timestamps`: Append timestamps to filenames for historical backups
- `-e, --backup-envs`: Back up environment variables via Portainer API
- `-n, --dry-run`: Show what would be done without making changes
- `-c, --keep-count N`: Keep last N backup runs per stack (rotation)
- `-h, --help`: Show full help with all options

File structure

Normal mode creates folders like:

```
/opt/portainer_backups/backups/
├── my-app/
│   ├── my-app.yml
│   ├── my-app.env
│   └── my-app.stack.json
└── web-frontend/
    ├── web-frontend.yml
    ├── web-frontend.env
    └── web-frontend.stack.json
```

Simple mode with timestamps:

```
/opt/portainer_backups/backups/
├── stack_a1b2c3d4/
│   ├── stack_a1b2c3d4_2025-10-23_030000.yml
│   ├── stack_a1b2c3d4_2025-10-23_030000.env
│   └── stack_a1b2c3d4_2025-10-23_030000.stack.json
└── stack_e5f6g7h8/
    ├── stack_e5f6g7h8_2025-10-23_030000.yml
    ├── stack_e5f6g7h8_2025-10-23_030000.env
    └── stack_e5f6g7h8_2025-10-23_030000.stack.json
```

Notes & assumptions

- The script uses `jq` and `docker` and expects a Docker volume named `portainer_data` containing Portainer's data.
- It expects compose files under `/data/compose/<STACK_ID>/docker-compose.yml` or `.yaml` inside the volume. Adjust with `--compose-prefix` if needed.
- Filenames are sanitized by replacing non-alphanumeric characters with underscores.

Checksum verification

- After copying each compose file the script attempts to verify integrity by comparing a checksum calculated inside the helper container with the copied file on the host. If the container-side checksum cannot be computed (older base images), the script falls back to a host-side size/exists check. If verification fails the copy is retried up to the configured retry count.

Enhancements

- Add timestamping or rotation to keep historical backups.
- Compress backups to save space.
