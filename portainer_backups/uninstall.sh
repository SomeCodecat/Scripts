#!/usr/bin/env bash
set -euo pipefail

echo "═══════════════════════════════════════════════════════════"
echo "Portainer Backup Script - Uninstall & Cleanup"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "This will remove the backup script and its configuration."
echo ""

# Show what will be removed
echo "Checking installed components..."
echo ""

FOUND_COMPONENTS=false
FOUND_OLD_CONFIGS=false

# Check current installation
if [ -f "/usr/local/bin/backup_stacks.sh" ]; then
  echo "  ✓ Script found: /usr/local/bin/backup_stacks.sh"
  FOUND_COMPONENTS=true
fi

if [ -f "/etc/logrotate.d/portainer-backup" ]; then
  echo "  ✓ Logrotate config found: /etc/logrotate.d/portainer-backup"
  FOUND_COMPONENTS=true
fi

if command -v crontab >/dev/null 2>&1; then
  CRON_COUNT=$(sudo crontab -l 2>/dev/null | grep -c backup_stacks.sh || echo 0)
  if [ "$CRON_COUNT" -gt 0 ]; then
    echo "  ✓ Cron job(s) found ($CRON_COUNT):"
    sudo crontab -l 2>/dev/null | grep backup_stacks.sh | while read -r line; do
      echo "    $line"
    done
    FOUND_COMPONENTS=true
    
    if [ "$CRON_COUNT" -gt 1 ]; then
      echo "    ⚠️  Multiple cron jobs detected (will clean up duplicates)"
      FOUND_OLD_CONFIGS=true
    fi
  fi
fi

if [ -f "/var/log/portainer_backup.log" ]; then
  echo "  ✓ Log file found: /var/log/portainer_backup.log"
  FOUND_COMPONENTS=true
fi

# Check for old configurations from previous versions
echo ""
echo "Checking for old configurations from previous versions..."
echo ""

if [ -f "/opt/backup_stacks.sh" ]; then
  echo "  ⚠️  Old script found: /opt/backup_stacks.sh"
  FOUND_OLD_CONFIGS=true
fi

if [ -f "$HOME/backup_stacks.sh" ]; then
  echo "  ⚠️  Old script found: $HOME/backup_stacks.sh"
  FOUND_OLD_CONFIGS=true
fi

if [ -f "/etc/logrotate.d/portainer_backup" ]; then
  echo "  ⚠️  Old logrotate config found: /etc/logrotate.d/portainer_backup"
  echo "      (Note: current version uses portainer-backup)"
  FOUND_OLD_CONFIGS=true
fi

if [ -f "/var/log/portainer-backup.log" ]; then
  echo "  ⚠️  Old log file found: /var/log/portainer-backup.log"
  FOUND_OLD_CONFIGS=true
fi

if [ -f "$HOME/portainer_backup.log" ]; then
  echo "  ⚠️  Old log file found: $HOME/portainer_backup.log"
  FOUND_OLD_CONFIGS=true
fi

if [ "$FOUND_COMPONENTS" = false ] && [ "$FOUND_OLD_CONFIGS" = false ]; then
  echo "  No installed components or old configurations found."
  echo ""
  echo "The backup script does not appear to be installed."
  exit 0
fi

echo ""
read -p "Proceed with uninstall/cleanup? [y/N]: " CONFIRM
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

# Remove old script locations
if [ -f "/opt/backup_stacks.sh" ]; then
  sudo rm -f /opt/backup_stacks.sh
  echo "✓ Removed old script: /opt/backup_stacks.sh"
fi

if [ -f "$HOME/backup_stacks.sh" ]; then
  rm -f "$HOME/backup_stacks.sh"
  echo "✓ Removed old script: $HOME/backup_stacks.sh"
fi

# Remove logrotate configs (current and old)
if [ -f "/etc/logrotate.d/portainer-backup" ]; then
  sudo rm -f /etc/logrotate.d/portainer-backup
  echo "✓ Removed logrotate config"
fi

if [ -f "/etc/logrotate.d/portainer_backup" ]; then
  sudo rm -f /etc/logrotate.d/portainer_backup
  echo "✓ Removed old logrotate config"
fi

# Remove all cron jobs (handles duplicates automatically)
if command -v crontab >/dev/null 2>&1; then
  if sudo crontab -l 2>/dev/null | grep -q backup_stacks.sh; then
    TEMP_CRON=$(mktemp)
    sudo crontab -l 2>/dev/null | grep -v backup_stacks.sh > "$TEMP_CRON" || true
    sudo crontab "$TEMP_CRON"
    rm -f "$TEMP_CRON"
    echo "✓ Removed all cron jobs"
  fi
fi

# Ask about log files
if [ -f "/var/log/portainer_backup.log" ] || [ -f "/var/log/portainer-backup.log" ] || [ -f "$HOME/portainer_backup.log" ]; then
  echo ""
  read -p "Remove log files? [y/N]: " REMOVE_LOG
  REMOVE_LOG="${REMOVE_LOG:-N}"
  if [[ "$REMOVE_LOG" =~ ^[Yy]$ ]]; then
    sudo rm -f /var/log/portainer_backup.log* 2>/dev/null || true
    sudo rm -f /var/log/portainer-backup.log* 2>/dev/null || true
    rm -f "$HOME/portainer_backup.log"* 2>/dev/null || true
    echo "✓ Removed log files"
  else
    echo "○ Kept log files"
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
