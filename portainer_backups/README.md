# Portainer Stacks Backup

**Simple, reliable backups of Portainer stacks - no API key required!**

This script backs up Portainer stack compose files and environment variables by reading directly from the Portainer database.

## 📑 Table of Contents

- [Portainer Stacks Backup](#portainer-stacks-backup)
  - [📑 Table of Contents](#-table-of-contents)
  - [Why This Approach?](#why-this-approach)
  - [Installation](#installation)
    - [Quick Start - Choose Your Setup](#quick-start---choose-your-setup)
    - [Option 1: Guided Setup (Easiest - Recommended) ⚡](#option-1-guided-setup-easiest---recommended-)
    - [Option 2: Simple Install (Script Only, Manual Config)](#option-2-simple-install-script-only-manual-config)
    - [Option 3: Update Mode (Update Script, Keep Config)](#option-3-update-mode-update-script-keep-config)
    - [Option 4: Manual Install](#option-4-manual-install)
  - [Uninstallation](#uninstallation)
  - [Quick Start](#quick-start)
  - [Scheduling with Cron](#scheduling-with-cron)
    - [Why Log Rotation Matters](#why-log-rotation-matters)
    - [Option 1: Use logrotate (Recommended)](#option-1-use-logrotate-recommended)
    - [Option 2: Redirect to /dev/null (no logs)](#option-2-redirect-to-devnull-no-logs)
    - [Option 3: Use systemd journal (systemd systems)](#option-3-use-systemd-journal-systemd-systems)
  - [Command Line Options](#command-line-options)
  - [Backup to Network Location](#backup-to-network-location)
    - [Direct Network Backup](#direct-network-backup)
    - [Two-Stage Backup (Recommended for Reliability)](#two-stage-backup-recommended-for-reliability)
  - [File Structure](#file-structure)
  - [Requirements](#requirements)
  - [Notes](#notes)
  - [How It Works](#how-it-works)
    - [Database Reading Process](#database-reading-process)
    - [Backup Process](#backup-process)
    - [What Gets Backed Up](#what-gets-backed-up)
  - [Security Notes](#security-notes)
    - [⚠️ Environment Variables Contain Sensitive Data](#️-environment-variables-contain-sensitive-data)
    - [Security Measures](#security-measures)
    - [Best Practices](#best-practices)
  - [Advanced Options](#advanced-options)
    - [Simple Mode](#simple-mode)
    - [Custom Rotation](#custom-rotation)
    - [Dry Run Mode](#dry-run-mode)
    - [Custom Portainer Volume](#custom-portainer-volume)

## Why This Approach?

- ✅ **No API dependency**: Works without Portainer running or API access
- ✅ **More reliable**: Direct access to the source database
- ✅ **Complete data**: Includes environment variables from the database
- ✅ **Simpler setup**: Just point to the Docker volume - no API keys needed
- ✅ **Offline backups**: Can backup even when Portainer is stopped

## Installation

### Quick Start - Choose Your Setup

The installer offers three modes:

```bash
# Interactive menu (recommended - choose mode on the fly)
sudo ./install.sh

# Or skip menu with flags:
sudo ./install.sh -i   # Guided setup (full interactive)
sudo ./install.sh -s   # Simple install (script only)
sudo ./install.sh -u   # Update script (keep config)
```

### Option 1: Guided Setup (Easiest - Recommended) ⚡

**⏱️ 10-second setup:** Just press Enter to accept smart defaults!

```bash
# Clone or download the script
cd /tmp
git clone https://github.com/SomeCodecat/Scripts.git
cd Scripts/portainer_backups

# Run guided installer (does everything for you)
sudo ./install.sh -i
# Or just: sudo ./install.sh  (then choose option 1)
```

**Quick Setup:** Just press Enter at each prompt to accept sensible defaults!

The guided installer will:

1. ✅ Detect existing configuration (if re-running)
   - Shows current backup directory
   - Shows current cron schedule
   - Shows current environment variable settings
   - Default is to keep existing settings (just press Enter)
2. ✅ Check and install dependencies (jq, cron, logrotate)
   - Automatically detects package manager (apt/yum/dnf/pacman)
   - Prompts for confirmation before installing
3. ✅ Install the script to `/usr/local/bin` (or custom directory)
4. ✅ Collect all configuration settings
   - Backup directory (default: current or `/var/backups/portainer`)
   - Cron schedule (default: keep existing or Daily at 3:00 AM)
   - Environment variables (default: keep existing or Yes)
   - Log rotation (default: keep existing or Yes, keeps 14 days)
   - Test backup (default: No)
5. ✅ Show complete review of all changes to be made
6. ✅ Apply changes only after your confirmation
   - **No partial installations** - if you cancel, only the script is installed
7. ✅ Optionally run a test backup to verify setup

**Default Configuration** (when pressing Enter at all prompts on fresh install):

| Setting                         | Default Value             |
| ------------------------------- | ------------------------- |
| 📦 Install Dependencies         | Yes (jq, cron, logrotate) |
| 📁 Backup Location              | `/var/backups/portainer`  |
| ⏰ Schedule                     | Daily at 3:00 AM          |
| 🔐 Backup Environment Variables | Yes                       |
| 📝 Log Rotation                 | Yes (14 days)             |
| 🧪 Test Backup                  | No (skip)                 |

**Re-running Guided Setup:**

When you re-run the guided installer, it will:

- 📋 Detect and show your current configuration
- ✅ Default to keeping existing settings (just press Enter)
- ✏️ Allow you to update any setting by typing a new value
- 🔄 Update the script to the latest version

```bash
sudo ./install.sh -i
# Shows: "📋 Existing configuration detected"
# Current backup directory: /mnt/storage/docker/backups/portainer
# Existing cron job found:
#   Schedule: 0 3 * * *
# Update existing cron schedule? [y/N]: ⏎  (press Enter to keep)
# ✅ Kept existing cron job
```

### Option 2: Simple Install (Script Only, Manual Config)

```bash
sudo ./install.sh -s
# Or: sudo ./install.sh  (then choose option 2)

# Or install to custom directory
sudo ./install.sh -s /opt/scripts
```

This only installs the script. You'll need to manually:

- Create backup directory
- Set up cron job
- Configure log rotation

### Option 3: Update Mode (Update Script, Keep Config)

Perfect for updating to the latest version without reconfiguring:

```bash
sudo ./install.sh -u
# Or: sudo ./install.sh  (then choose option 3)
```

This will:

- ✅ Update the script to the latest version
- ✅ Preserve existing cron jobs
- ✅ Preserve logrotate configuration
- ✅ No prompts or dependency checks

### Option 4: Manual Install

```bash
# Just copy the script anywhere you want
sudo cp backup_stacks.sh /usr/local/bin/
sudo chmod 755 /usr/local/bin/backup_stacks.sh

# Or run directly from current directory (no installation)
./backup_stacks.sh -d /mnt/nas/backups --backup-envs
```

## Uninstallation

To remove the backup script and configuration:

```bash
cd Scripts/portainer_backups
sudo ./uninstall.sh
```

The uninstaller will:

1. 🔍 **Detect all components** (current and old):
   - Current script at `/usr/local/bin/backup_stacks.sh`
   - Old scripts in different locations (`/opt/`, `$HOME/`)
   - Current logrotate config at `/etc/logrotate.d/portainer-backup`
   - Old logrotate configs with different naming
   - All cron jobs containing `backup_stacks.sh` (handles duplicates)
   - Log files in various locations
2. 📋 **Show everything found** with status indicators (✓ current, ⚠️ old)
3. ⚠️ **Ask for confirmation** before removing anything
4. ✅ **Remove all components** in one go:
   - Current and old script files
   - Current and old logrotate configurations
   - All cron jobs (automatically cleans up duplicates)
   - Optionally all log files
5. ℹ️ **Keep installed packages** (jq, logrotate, cron) - they're useful system utilities
6. ℹ️ **Keep backup directories** (contain your data)

**Note:** The uninstaller automatically detects and removes old configurations from previous versions, so you don't need to run any cleanup separately.

**Manual uninstall:**

```bash
# Remove script
sudo rm -f /usr/local/bin/backup_stacks.sh

# Remove logrotate config
sudo rm -f /etc/logrotate.d/portainer-backup

# Remove cron job
sudo crontab -l | grep -v backup_stacks.sh | sudo crontab -

# Optionally remove backup directories
sudo rm -rf /var/backups/portainer
```

## Quick Start

**Note: You must specify a backup destination with `-d`**

<details>
<summary>📋 Basic Usage Examples (click to expand)</summary>

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

</details>

## Scheduling with Cron

<details>
<summary>⏰ Cron Job Examples (click to expand)</summary>

Run backups automatically at 3 AM daily:

```bash
# Run daily at 3 AM, backup to local directory
0 3 * * * /usr/local/bin/backup_stacks.sh -d /backup/portainer -e >> /var/log/portainer_backup.log 2>&1

# Or backup to network location
0 3 * * * /usr/local/bin/backup_stacks.sh -d /mnt/nas/portainer-backups -e >> /var/log/portainer_backup.log 2>&1
```

</details>

<details>
<summary>📝 Log Rotation Setup (Important - Prevents Disk Fill)</summary>

### Why Log Rotation Matters

Without rotation, logs will grow indefinitely and fill your disk. The interactive installer sets this up automatically.

### Option 1: Use logrotate (Recommended)

Create `/etc/logrotate.d/portainer-backup`:

```bash
sudo tee /etc/logrotate.d/portainer-backup > /dev/null << 'EOF'
/var/log/portainer_backup.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
EOF
```

This rotates logs daily and keeps 14 days of compressed history.

### Option 2: Redirect to /dev/null (no logs)

```bash
# If you don't need logs
0 3 * * * /usr/local/bin/backup_stacks.sh -d /backup/portainer -e > /dev/null 2>&1
```

### Option 3: Use systemd journal (systemd systems)

```bash
# Logs go to systemd journal automatically
0 3 * * * systemd-cat -t portainer-backup /usr/local/bin/backup_stacks.sh -d /backup/portainer -e
```

</details>

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

<details>
<summary>🌐 Network Backup Setup (click to expand)</summary>

The script works perfectly with network-mounted storage:

### Direct Network Backup

```bash
# Mount your NAS/network share
sudo mkdir -p /mnt/nas
sudo mount -t cifs //nas.local/backups /mnt/nas -o credentials=/root/.smbcredentials

# Backup directly to network location
backup_stacks.sh -d /mnt/nas/portainer-backups --backup-envs

# Add to cron for automatic backups
0 3 * * * /usr/local/bin/backup_stacks.sh -d /mnt/nas/portainer-backups -e >> /var/log/portainer_backup.log 2>&1
```

### Two-Stage Backup (Recommended for Reliability)

Faster and more reliable - backup locally first, then sync to network:

```bash
# Backup to local first (fast), then sync to network (resilient)
backup_stacks.sh -d /var/backups/portainer -e && rsync -av /var/backups/portainer/ /mnt/nas/portainer-backups/
```

This approach ensures backups complete even if network is temporarily unavailable.

</details>

## File Structure

All backup files include timestamps for proper rotation:

```text
/backup/portainer/
├── my-app/
│   ├── my-app_2025-10-23_030000.yml
│   ├── my-app_2025-10-23_030000.env
│   └── my-app_2025-10-23_030000.stack.json
└── web-frontend/
    ├── web-frontend_2025-10-23_030000.yml
    ├── web-frontend_2025-10-23_030000.env
    └── web-frontend_2025-10-23_030000.stack.json
```

Simple mode (`--simple`) uses stack IDs as folder names:

```text
/backup/portainer/
├── stack_1/
│   ├── stack_1_2025-10-23_030000.yml
│   ├── stack_1_2025-10-23_030000.env
│   └── stack_1_2025-10-23_030000.stack.json
└── stack_2/
    ├── stack_2_2025-10-23_030000.yml
    ├── stack_2_2025-10-23_030000.env
    └── stack_2_2025-10-23_030000.stack.json
```

## Requirements

**Automatically installed by the installer:**

- `jq` - JSON parsing (installer detects and installs via apt/yum/dnf/pacman)
- `logrotate` - Log rotation (optional, installer can install it)

**Required (must be pre-installed):**

- `docker` - Docker CLI access (required to read Portainer data)
- Access to Portainer data volume (usually `portainer_data`)

**Supported Package Managers:**

- Debian/Ubuntu: `apt-get`
- RHEL/CentOS: `yum`
- Fedora: `dnf`
- Arch Linux: `pacman`

## Notes

- Stack names are taken from the Portainer database (what you see in the UI)
- Filenames are sanitized by replacing non-alphanumeric characters with underscores
- All backup files include timestamps for history tracking and rotation
- Checksums verify file integrity after copying
- Retries automatically handle temporary failures

## How It Works

<details>
<summary>🔧 Technical Details (click to expand)</summary>

### Database Reading Process

The script reads directly from Portainer's BoltDB database (`/data/portainer.db`) to extract:

1. **Stack information**: ID, name, project path
2. **Environment variables**: Stored in the `Env` array for each stack
3. **Stack metadata**: Creation date, update info, etc.

### Backup Process

It then:

- Copies compose files from `/data/compose/<stack-id>/` using Docker containers
- Extracts environment variables from the database JSON
- Organizes everything in per-stack folders with timestamps
- Automatically rotates old backups based on timestamp grouping
- Verifies file integrity with SHA-256 checksums
- Retries failed operations with exponential backoff

### What Gets Backed Up

For each stack, the script creates:

```text
/backup/portainer/
└── stack-name/
    ├── stack-name_2025-10-23_030000.yml           # Compose file
    ├── stack-name_2025-10-23_030000.env           # Environment variables (if --backup-envs)
    └── stack-name_2025-10-23_030000.stack.json    # Full stack metadata from database
```

</details>

## Security Notes

<details>
<summary>🔐 Security Considerations (click to expand)</summary>

### ⚠️ Environment Variables Contain Sensitive Data

The `.env` files typically contain:

- Database passwords
- API keys and tokens
- Secret keys
- Private credentials

### Security Measures

This script implements several security measures:

- ✅ `.env` files created with `600` permissions (owner read/write only)
- ✅ Checksums verify file integrity
- ✅ No network transmission of credentials (local file operations)

### Best Practices

- 🔒 Store backups in a secure location
- 🔒 Consider encrypting backup directories (e.g., with `encfs` or LUKS)
- 🔒 Restrict access to backup directory (chmod 700)
- 🔒 Never commit `.env` files to version control
- 🔒 Regularly audit who has access to backups
- 🔒 Use network share credentials files (not passwords in cron)

</details>

## Advanced Options

<details>
<summary>⚙️ Advanced Configuration (click to expand)</summary>

### Simple Mode

Use stack IDs instead of names for folder structure:

```bash
backup_stacks.sh -d /backup/portainer --simple
```

Creates folders like `stack_1`, `stack_2` instead of human-readable names.

### Custom Rotation

Adjust how many backup runs to keep per stack:

```bash
# Keep 30 days of backups
backup_stacks.sh -d /backup/portainer --keep-count 30

# Keep only last 3 backups (minimal storage)
backup_stacks.sh -d /backup/portainer --keep-count 3
```

### Dry Run Mode

Test the backup process without making changes:

```bash
backup_stacks.sh -d /backup/portainer --backup-envs --dry-run
```

Shows exactly what would happen without creating any files.

### Custom Portainer Volume

If using a non-standard volume name:

```bash
backup_stacks.sh -d /backup/portainer --volume my_portainer_data
```

</details>
