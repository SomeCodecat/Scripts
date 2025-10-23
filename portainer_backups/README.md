# Portainer Stacks Backup

**Simple, reliable backups of Portainer stacks - no API key required!**

This script backs up Portainer stack compose files and environment variables by reading directly from the Portainer database.

## Why This Approach?

- ✅ **No API dependency**: Works without Portainer running or API access
- ✅ **More reliable**: Direct access to the source database
- ✅ **Complete data**: Includes environment variables from the database
- ✅ **Simpler setup**: Just point to the Docker volume - no API keys needed
- ✅ **Offline backups**: Can backup even when Portainer is stopped

## Installation

### Option 1: Interactive Install (Easiest - Recommended)

```bash
# Clone or download the script
cd /tmp
git clone https://github.com/SomeCodecat/Scripts.git
cd Scripts/portainer_backups

# Run interactive installer (does everything for you)
sudo ./install.sh -i
```

The interactive installer will:

1. ✅ Install the script to `/usr/local/bin` (or custom directory)
2. ✅ Create your backup directory (asks for path)
3. ✅ Set up automatic cron schedule (you choose frequency)
4. ✅ Optionally run a test backup immediately

### Option 2: Quick Install (Script Only)

```bash
# Install to /usr/local/bin (default, adds to PATH)
sudo ./install.sh

# Or install to custom directory
sudo ./install.sh /opt/scripts
```

You'll need to manually create backup directory and set up cron.

### Option 3: Manual Install

```bash
# Just copy the script anywhere you want
sudo cp backup_stacks.sh /usr/local/bin/
sudo chmod 755 /usr/local/bin/backup_stacks.sh

# Or run directly from current directory (no installation)
./backup_stacks.sh -d /mnt/nas/backups --backup-envs
```

## Quick Start

**Note: You must specify a backup destination with `-d`**

```bash
# Basic usage - backup to local directory
./backup_stacks.sh -d /backup/portainer

# With environment variables (recommended)
./backup_stacks.sh -d /backup/portainer --backup-envs

# Backup to network location
./backup_stacks.sh -d /mnt/nas/portainer-backups --backup-envs

# Keep more backups (default is 7)
./backup_stacks.sh -d /backup/portainer --backup-envs --keep-count 14

# Test first with dry run
./backup_stacks.sh -d /backup/portainer --backup-envs --dry-run
```

## Scheduling with Cron

Run backups automatically at 3 AM daily:

```bash
# Run daily at 3 AM, backup to local directory
0 3 * * * /usr/local/bin/backup_stacks.sh -d /backup/portainer -e >> /var/log/portainer_backup.log 2>&1

# Or backup to network location
0 3 * * * /usr/local/bin/backup_stacks.sh -d /mnt/nas/portainer-backups -e >> /var/log/portainer_backup.log 2>&1
```

## Command Line Options

**Required:**

- `-d, --backup-dir DIR`: **Where to save backups** (network path, local directory, etc.)

**Optional:**

- `-v, --volume NAME`: Portainer data volume name (default: portainer_data)
- `-e, --backup-envs`: Backup environment variables from database
- `-s, --simple`: Use simple mode (stack ID filenames instead of names)
- `-c, --keep-count N`: Keep last N backup runs per stack (default: 7)
- `-n, --dry-run`: Show what would be done without making changes
- `-h, --help`: Show full help message

## Backup to Network Location

The script works perfectly with network-mounted storage:

```bash
# Mount your NAS/network share
sudo mkdir -p /mnt/nas
sudo mount -t cifs //nas.local/backups /mnt/nas -o credentials=/root/.smbcredentials

# Backup directly to network location
backup_stacks.sh -d /mnt/nas/portainer-backups --backup-envs

# Add to cron for automatic backups
0 3 * * * /usr/local/bin/backup_stacks.sh -d /mnt/nas/portainer-backups -e >> /var/log/portainer_backup.log 2>&1
```

**Alternative: Two-stage backup** (faster, more reliable)

```bash
# Backup to local first (fast), then sync to network (resilient)
backup_stacks.sh -d /var/backups/portainer -e && rsync -av /var/backups/portainer/ /mnt/nas/portainer-backups/
```

## File structure

All backup files now include timestamps for proper rotation:

```text
/opt/portainer_backups/backups/
├── my-app/
│   ├── my-app_2025-10-23_030000.yml
│   ├── my-app_2025-10-23_030000.env
│   └── my-app_2025-10-23_030000.stack.json
└── web-frontend/
    ├── web-frontend_2025-10-23_030000.yml
    ├── web-frontend_2025-10-23_030000.env
    └── web-frontend_2025-10-23_030000.stack.json
```

Simple mode uses stack IDs as folder names:

```text
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

## Requirements

- `jq` - JSON parsing (install with `apt install jq` or `yum install jq`)
- `docker` - Docker CLI access
- Access to Portainer data volume (usually `portainer_data`)

## Notes

- Stack names are taken from the Portainer database (what you see in the UI)
- Filenames are sanitized by replacing non-alphanumeric characters with underscores
- All backup files include timestamps for history tracking and rotation
- Checksums verify file integrity after copying
- Retries automatically handle temporary failures

## How It Works

The script reads directly from Portainer's BoltDB database (`/data/portainer.db`) to extract:

1. **Stack information**: ID, name, project path
2. **Environment variables**: Stored in the `Env` array for each stack
3. **Stack metadata**: Creation date, update info, etc.

It then:

- Copies compose files from `/data/compose/<stack-id>/` using Docker containers
- Extracts environment variables from the database JSON
- Organizes everything in per-stack folders with timestamps
- Automatically rotates old backups

## What Gets Backed Up

For each stack, the script creates:

```text
/backup/portainer/
└── stack-name/
    ├── stack-name_2025-10-23_030000.yml           # Compose file
    ├── stack-name_2025-10-23_030000.env           # Environment variables (if --backup-envs)
    └── stack-name_2025-10-23_030000.stack.json    # Full stack metadata from database
```

## Security Notes

**Environment variables often contain sensitive data!**

- The `.env` files contain passwords, API keys, and other secrets
- Backup files are created with `600` permissions (owner read/write only)
- Store backups in a secure location
- Consider encrypting backup directories
- Never commit `.env` files to version control

## Advanced Options

- **Simple mode** (`--simple`): Use stack IDs instead of names for folder structure
- **Custom rotation** (`--keep-count`): Adjust how many backup runs to keep per stack
- **Dry run** (`--dry-run`): Test the backup process without making changes
