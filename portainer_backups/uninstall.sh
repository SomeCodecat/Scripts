#!/usr/bin/env bash
set -euo pipefail

echo "═══════════════════════════════════════════════════════════"
echo "Portainer Backup Script - Uninstall"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "This will remove the backup script and its configuration."
echo ""

# Show what will be removed
echo "Checking installed components..."
echo ""

FOUND_COMPONENTS=false

if [ -f "/usr/local/bin/backup_stacks.sh" ]; then
  echo "  ✓ Script found: /usr/local/bin/backup_stacks.sh"
  FOUND_COMPONENTS=true
fi

if [ -f "/etc/logrotate.d/portainer-backup" ]; then
  echo "  ✓ Logrotate config found: /etc/logrotate.d/portainer-backup"
  FOUND_COMPONENTS=true
fi

if command -v crontab >/dev/null 2>&1; then
  if sudo crontab -l 2>/dev/null | grep -q backup_stacks.sh; then
    CRON_JOB=$(sudo crontab -l 2>/dev/null | grep backup_stacks.sh)
    echo "  ✓ Cron job found:"
    echo "    $CRON_JOB"
    FOUND_COMPONENTS=true
  fi
fi

if [ -f "/var/log/portainer_backup.log" ]; then
  echo "  ✓ Log file found: /var/log/portainer_backup.log"
  FOUND_COMPONENTS=true
fi

if [ "$FOUND_COMPONENTS" = false ]; then
  echo "  No installed components found."
  echo ""
  echo "The backup script does not appear to be installed."
  exit 0
fi

echo ""
read -p "Proceed with uninstall? [y/N]: " CONFIRM
CONFIRM="${CONFIRM:-N}"

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "Uninstall cancelled."
  exit 0
fi

echo ""
echo "Uninstalling..."
echo ""

# Remove installed script
if [ -f "/usr/local/bin/backup_stacks.sh" ]; then
  sudo rm -f /usr/local/bin/backup_stacks.sh
  echo "✓ Removed /usr/local/bin/backup_stacks.sh"
fi

# Remove logrotate config
if [ -f "/etc/logrotate.d/portainer-backup" ]; then
  sudo rm -f /etc/logrotate.d/portainer-backup
  echo "✓ Removed logrotate config"
fi

# Remove cron job (if cron is available)
if command -v crontab >/dev/null 2>&1; then
  if sudo crontab -l 2>/dev/null | grep -q backup_stacks.sh; then
    TEMP_CRON=$(mktemp)
    sudo crontab -l 2>/dev/null | grep -v backup_stacks.sh > "$TEMP_CRON" || true
    sudo crontab "$TEMP_CRON"
    rm -f "$TEMP_CRON"
    echo "✓ Removed cron job"
  fi
fi

# Ask about log file
if [ -f "/var/log/portainer_backup.log" ]; then
  echo ""
  read -p "Remove log file /var/log/portainer_backup.log? [y/N]: " REMOVE_LOG
  REMOVE_LOG="${REMOVE_LOG:-N}"
  if [[ "$REMOVE_LOG" =~ ^[Yy]$ ]]; then
    sudo rm -f /var/log/portainer_backup.log*
    echo "✓ Removed log files"
  else
    echo "○ Kept log file"
  fi
fi

# Note about installed packages
echo ""
echo "─────────────────────────────────────────────────────────────"
echo "Note: System packages (jq, logrotate, cron) were NOT removed"
echo "They are useful system utilities. To remove manually if needed:"
echo "  sudo apt-get remove jq logrotate cron"
echo ""

# Note about backup directory
echo "Note: Backup directories were NOT removed (contain your data)"
echo "To remove backup data manually if needed:"
echo "  sudo rm -rf /var/backups/portainer"
echo "  or check your configured backup location"
echo "─────────────────────────────────────────────────────────────"
echo ""
echo "✓ Uninstall complete"
echo ""
