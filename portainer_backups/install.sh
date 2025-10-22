#!/usr/bin/env bash
set -euo pipefail

DEST_DIR="/opt/portainer_backups"
BACKUP_DIR="$DEST_DIR/backups"

echo "Installing portainer backup scripts to $DEST_DIR"
sudo mkdir -p "$DEST_DIR"
sudo cp -a "$(dirname "$0")/backup_stacks.sh" "$DEST_DIR/backup_stacks.sh"
sudo chmod 755 "$DEST_DIR/backup_stacks.sh"
sudo mkdir -p "$BACKUP_DIR"
sudo chown root:root "$DEST_DIR" "$DEST_DIR/backup_stacks.sh" "$BACKUP_DIR"
sudo chmod 700 "$BACKUP_DIR"

echo "Installed. Edit $DEST_DIR/backup_stacks.sh and set PORTAINER_URL and PORTAINER_API_KEY." 
echo "To add the cron job for root, run:"
echo "  sudo crontab -e"
echo "and add the line:"
echo "  0 3 * * * $DEST_DIR/backup_stacks.sh >> /var/log/portainer_backup.log 2>&1"
