#!/usr/bin/env bash
set -euo pipefail

# Show help if requested
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
  cat << 'EOF'
Usage: ./install.sh [OPTIONS] [INSTALL_DIR]

Install the Portainer backup script with optional automated setup.

Arguments:
  INSTALL_DIR    Where to install the script (default: /usr/local/bin)

Options:
  -i, --interactive  Interactive setup (creates backup dir, configures cron)
  -h, --help         Show this help message

Examples:
  sudo ./install.sh                              # Quick install to /usr/local/bin
  sudo ./install.sh -i                           # Full guided setup
  sudo ./install.sh /opt/scripts                 # Install to custom directory
  sudo ./install.sh -i /opt/scripts              # Interactive with custom install dir

Interactive mode will:
  1. Install the script
  2. Create the backup directory (with your confirmation)
  3. Set up a cron schedule (with your confirmation)
  4. Optionally test the backup immediately

Quick mode (no --interactive):
  1. Installs the script only
  2. Shows usage examples for manual configuration
EOF
  exit 0
fi

# Parse options
INTERACTIVE=false
INSTALL_DIR="/usr/local/bin"

while [[ $# -gt 0 ]]; do
  case $1 in
    -i|--interactive)
      INTERACTIVE=true
      shift
      ;;
    -h|--help)
      # Already handled above
      shift
      ;;
    *)
      INSTALL_DIR="$1"
      shift
      ;;
  esac
done

DEST_DIR="$INSTALL_DIR"

echo "Installing portainer backup script to $DEST_DIR"

if [ "$DEST_DIR" = "/usr/local/bin" ]; then
  # Simple install - just copy the script to PATH
  sudo cp -a "$(dirname "$0")/backup_stacks.sh" "$DEST_DIR/backup_stacks.sh"
  sudo chmod 755 "$DEST_DIR/backup_stacks.sh"
  sudo chown root:root "$DEST_DIR/backup_stacks.sh"
  echo "✓ Script installed to $DEST_DIR/backup_stacks.sh"
else
  # Custom directory install - create structure
  sudo mkdir -p "$DEST_DIR"
  sudo cp -a "$(dirname "$0")/backup_stacks.sh" "$DEST_DIR/backup_stacks.sh"
  sudo chmod 755 "$DEST_DIR/backup_stacks.sh"
  sudo chown root:root "$DEST_DIR" "$DEST_DIR/backup_stacks.sh"
  echo "✓ Script installed to $DEST_DIR/backup_stacks.sh"
fi

echo ""
echo "✓ Script installed successfully!"
echo ""

# Interactive setup mode
if [ "$INTERACTIVE" = true ]; then
  echo "═══════════════════════════════════════════════════════════"
  echo "Interactive Setup - Backup Directory & Cron Schedule"
  echo "═══════════════════════════════════════════════════════════"
  echo ""
  
  # Step 1: Create backup directory
  read -p "Enter backup directory path (e.g., /mnt/nas/portainer-backups): " BACKUP_DIR
  
  if [ -z "$BACKUP_DIR" ]; then
    echo "⚠ No backup directory specified, skipping..."
  else
    if [ -d "$BACKUP_DIR" ]; then
      echo "✓ Directory already exists: $BACKUP_DIR"
    else
      read -p "Create directory $BACKUP_DIR? (y/n): " CREATE_DIR
      if [[ "$CREATE_DIR" =~ ^[Yy] ]]; then
        sudo mkdir -p "$BACKUP_DIR"
        sudo chmod 755 "$BACKUP_DIR"
        echo "✓ Created backup directory: $BACKUP_DIR"
      else
        echo "⚠ Directory not created, you'll need to create it manually"
      fi
    fi
    
    # Step 2: Configure cron
    echo ""
    echo "───────────────────────────────────────────────────────────"
    echo "Cron Schedule Setup"
    echo "───────────────────────────────────────────────────────────"
    echo ""
    echo "Common schedules:"
    echo "  1) Daily at 3:00 AM       - 0 3 * * *"
    echo "  2) Every 6 hours          - 0 */6 * * *"
    echo "  3) Every 12 hours         - 0 */12 * * *"
    echo "  4) Weekly (Sunday 2 AM)   - 0 2 * * 0"
    echo "  5) Custom cron expression"
    echo "  6) Skip (configure manually later)"
    echo ""
    read -p "Choose schedule (1-6): " SCHEDULE_CHOICE
    
    case $SCHEDULE_CHOICE in
      1) CRON_SCHEDULE="0 3 * * *" ;;
      2) CRON_SCHEDULE="0 */6 * * *" ;;
      3) CRON_SCHEDULE="0 */12 * * *" ;;
      4) CRON_SCHEDULE="0 2 * * 0" ;;
      5)
        read -p "Enter custom cron expression: " CRON_SCHEDULE
        ;;
      6)
        echo "⚠ Skipping cron setup"
        CRON_SCHEDULE=""
        ;;
      *)
        echo "⚠ Invalid choice, skipping cron setup"
        CRON_SCHEDULE=""
        ;;
    esac
    
    if [ -n "$CRON_SCHEDULE" ]; then
      # Ask about options
      echo ""
      read -p "Backup environment variables too? (y/n): " BACKUP_ENVS
      ENVS_FLAG=""
      if [[ "$BACKUP_ENVS" =~ ^[Yy] ]]; then
        ENVS_FLAG=" --backup-envs"
      fi
      
      # Create cron command
      LOG_FILE="/var/log/portainer_backup.log"
      CRON_COMMAND="$CRON_SCHEDULE $DEST_DIR/backup_stacks.sh -d $BACKUP_DIR$ENVS_FLAG >> $LOG_FILE 2>&1"
      
      echo ""
      echo "Cron job to be added:"
      echo "  $CRON_COMMAND"
      echo ""
      read -p "Add this to root's crontab? (y/n): " ADD_CRON
      
      if [[ "$ADD_CRON" =~ ^[Yy] ]]; then
        # Add to crontab
        (sudo crontab -l 2>/dev/null | grep -v "backup_stacks.sh"; echo "$CRON_COMMAND") | sudo crontab -
        echo "✓ Cron job added successfully!"
        echo ""
        echo "View with: sudo crontab -l"
        echo "Logs will be written to: $LOG_FILE"
      else
        echo "⚠ Cron job not added. To add manually:"
        echo "  sudo crontab -e"
        echo "  Then add: $CRON_COMMAND"
      fi
    fi
    
    # Step 3: Test backup
    echo ""
    echo "───────────────────────────────────────────────────────────"
    read -p "Run a test backup now? (y/n): " RUN_TEST
    
    if [[ "$RUN_TEST" =~ ^[Yy] ]]; then
      echo ""
      echo "Running test backup..."
      BACKUP_CMD="$DEST_DIR/backup_stacks.sh -d $BACKUP_DIR"
      if [[ "$BACKUP_ENVS" =~ ^[Yy] ]]; then
        BACKUP_CMD="$BACKUP_CMD --backup-envs"
      fi
      echo "Command: $BACKUP_CMD"
      echo ""
      sudo $BACKUP_CMD
    fi
  fi
  
  echo ""
  echo "═══════════════════════════════════════════════════════════"
  echo "Setup complete!"
  echo "═══════════════════════════════════════════════════════════"
  
else
  # Non-interactive mode - show examples
  echo "═══════════════════════════════════════════════════════════"
  echo "The script reads directly from Portainer database - no API needed!"
  echo "═══════════════════════════════════════════════════════════"
  echo ""
  echo "Quick start examples:"
  echo ""
  echo "  # Backup to network location with environment variables"
  echo "  backup_stacks.sh -d /mnt/nas/portainer-backups --backup-envs"
  echo ""
  echo "  # Backup to local directory"
  echo "  backup_stacks.sh -d /backup/portainer --backup-envs"
  echo ""
  echo "  # Test with dry run first"
  echo "  backup_stacks.sh -d /mnt/nas/backups --backup-envs --dry-run"
  echo ""
  echo "For all options: backup_stacks.sh --help"
  echo ""
  echo "───────────────────────────────────────────────────────────"
  echo "To configure automatically, run:"
  echo "  sudo ./install.sh -i"
  echo "───────────────────────────────────────────────────────────"
fi

echo ""
