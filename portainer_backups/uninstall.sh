#!/usr/bin/env bash
set -euo pipefail

echo "═══════════════════════════════════════════════════════════"
echo "Portainer Backup Script - Uninstall"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Remove installed script
if [ -f "/usr/local/bin/backup_stacks.sh" ]; then
  read -p "Remove /usr/local/bin/backup_stacks.sh? [Y/n]: " REMOVE_SCRIPT
  REMOVE_SCRIPT="${REMOVE_SCRIPT:-Y}"
  if [[ "$REMOVE_SCRIPT" =~ ^[Yy]$ ]] || [[ -z "$REMOVE_SCRIPT" ]]; then
    sudo rm -f /usr/local/bin/backup_stacks.sh
    echo "✓ Removed /usr/local/bin/backup_stacks.sh"
  fi
fi

# Remove logrotate config
if [ -f "/etc/logrotate.d/portainer-backup" ]; then
  read -p "Remove /etc/logrotate.d/portainer-backup? [Y/n]: " REMOVE_LOGROTATE
  REMOVE_LOGROTATE="${REMOVE_LOGROTATE:-Y}"
  if [[ "$REMOVE_LOGROTATE" =~ ^[Yy]$ ]] || [[ -z "$REMOVE_LOGROTATE" ]]; then
    sudo rm -f /etc/logrotate.d/portainer-backup
    echo "✓ Removed logrotate config"
  fi
fi

# Remove cron job (if cron is available)
if command -v crontab >/dev/null 2>&1; then
  if sudo crontab -l 2>/dev/null | grep -q backup_stacks.sh; then
    read -p "Remove cron job for backup_stacks.sh? [Y/n]: " REMOVE_CRON
    REMOVE_CRON="${REMOVE_CRON:-Y}"
    if [[ "$REMOVE_CRON" =~ ^[Yy]$ ]] || [[ -z "$REMOVE_CRON" ]]; then
      sudo crontab -l 2>/dev/null | grep -v backup_stacks.sh | sudo crontab -
      echo "✓ Removed cron job"
    fi
  fi
fi

# Note about installed packages
echo ""
echo "Note: jq and logrotate packages were installed but NOT removed"
echo "They are useful system utilities. To remove them manually:"
echo "  sudo apt-get remove jq logrotate"
echo ""

# Note about backup directory
echo "Note: Backup directories were NOT removed (contain your data)"
echo "To remove manually if needed:"
echo "  sudo rm -rf /var/backups/portainer"
echo "  sudo rm -rf /mnt/storage/docker/backups/portainer"
echo ""
echo "✓ Uninstall complete"
