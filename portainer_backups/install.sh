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

echo "Installed. The script now uses command line arguments instead of a config file."
echo "Example usage:"
echo "  $DEST_DIR/backup_stacks.sh -u https://portainer.local:9443 -k your_api_key -e -t"
echo "To add the cron job for root, run:"
echo "  sudo crontab -e"
echo "and add a line like:"
echo "  0 3 * * * $DEST_DIR/backup_stacks.sh -u https://portainer.local:9443 -k your_api_key -e -t >> /var/log/portainer_backup.log 2>&1"
