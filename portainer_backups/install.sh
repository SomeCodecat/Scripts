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
  1. Check and install dependencies (jq, logrotate)
  2. Install the script
  3. Create the backup directory [default: /var/backups/portainer]
  4. Set up a cron schedule [default: Daily at 3 AM]
  5. Configure log rotation [default: Yes]
  6. Optionally test the backup immediately [default: No]
  
  Tip: Press Enter to accept defaults (shown in [brackets])

Quick mode (no -i):
  1. Checks and installs dependencies
  2. Installs the script only
  3. Shows usage examples for manual configuration
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
echo ""

# Check and install dependencies
echo "Checking dependencies..."

# Check for jq
if ! command -v jq >/dev/null 2>&1; then
  echo "⚠ jq is not installed (required for JSON parsing)"
  read -p "Install jq now? [Y/n]: " INSTALL_JQ
  INSTALL_JQ="${INSTALL_JQ:-Y}"
  if [[ "$INSTALL_JQ" =~ ^[Yy]$ ]] || [[ -z "$INSTALL_JQ" ]]; then
    echo "Installing jq..."
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update && sudo apt-get install -y jq
    elif command -v yum >/dev/null 2>&1; then
      sudo yum install -y jq
    elif command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y jq
    elif command -v pacman >/dev/null 2>&1; then
      sudo pacman -S --noconfirm jq
    else
      echo "❌ Could not detect package manager. Please install jq manually:"
      echo "   Debian/Ubuntu: sudo apt-get install jq"
      echo "   RHEL/CentOS:   sudo yum install jq"
      echo "   Fedora:        sudo dnf install jq"
      echo "   Arch:          sudo pacman -S jq"
      exit 1
    fi
    echo "✓ jq installed successfully"
  else
    echo "❌ jq is required. Please install it manually and run this script again."
    exit 1
  fi
else
  echo "✓ jq is installed"
fi

# Check for docker
if ! command -v docker >/dev/null 2>&1; then
  echo "❌ docker is not installed or not in PATH"
  echo "   This script requires Docker to access Portainer data."
  echo "   Please install Docker first: https://docs.docker.com/engine/install/"
  exit 1
else
  echo "✓ docker is installed"
fi

# Check for logrotate (optional but recommended)
LOGROTATE_AVAILABLE=false
if command -v logrotate >/dev/null 2>&1; then
  echo "✓ logrotate is installed"
  LOGROTATE_AVAILABLE=true
else
  echo "⚠ logrotate is not installed (optional, for log rotation)"
  read -p "Install logrotate now? [Y/n]: " INSTALL_LOGROTATE
  INSTALL_LOGROTATE="${INSTALL_LOGROTATE:-Y}"
  if [[ "$INSTALL_LOGROTATE" =~ ^[Yy]$ ]] || [[ -z "$INSTALL_LOGROTATE" ]]; then
    echo "Installing logrotate..."
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get install -y logrotate
    elif command -v yum >/dev/null 2>&1; then
      sudo yum install -y logrotate
    elif command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y logrotate
    elif command -v pacman >/dev/null 2>&1; then
      sudo pacman -S --noconfirm logrotate
    else
      echo "⚠ Could not detect package manager. Skipping logrotate installation."
      echo "   You can install it manually later if needed."
      LOGROTATE_AVAILABLE=false
    fi
    if command -v logrotate >/dev/null 2>&1; then
      echo "✓ logrotate installed successfully"
      LOGROTATE_AVAILABLE=true
    fi
  else
    echo "⚠ Skipping logrotate installation (you can set it up manually later)"
  fi
fi

echo ""

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
  echo "💡 Tip: Press Enter to accept defaults shown in [brackets]"
  echo ""
  echo "Defaults:"
  echo "  • Dependencies: Install jq and logrotate automatically"
  echo "  • Backup directory: /var/backups/portainer"
  echo "  • Cron schedule: Daily at 3:00 AM"
  echo "  • Environment variables: Yes"
  echo "  • Log rotation: Yes (14 days)"
  echo "  • Test backup: No"
  echo ""
  echo "───────────────────────────────────────────────────────────"
  echo ""
  
  # Step 1: Create backup directory
  echo "Script will be installed to: $DEST_DIR/backup_stacks.sh"
  echo ""
  
  DEFAULT_BACKUP_DIR="/var/backups/portainer"
  read -p "Enter backup directory path [$DEFAULT_BACKUP_DIR]: " BACKUP_DIR
  BACKUP_DIR="${BACKUP_DIR:-$DEFAULT_BACKUP_DIR}"
  
  if [ -z "$BACKUP_DIR" ]; then
    echo "⚠ No backup directory specified, skipping..."
  else
    if [ -d "$BACKUP_DIR" ]; then
      echo "✓ Directory already exists: $BACKUP_DIR"
    else
      read -p "Create directory $BACKUP_DIR? [Y/n]: " CREATE_DIR
      CREATE_DIR="${CREATE_DIR:-Y}"
      if [[ "$CREATE_DIR" =~ ^[Yy]$ ]] || [[ -z "$CREATE_DIR" ]]; then
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
    echo "  1) Daily at 3:00 AM       - 0 3 * * *  [default]"
    echo "  2) Every 6 hours          - 0 */6 * * *"
    echo "  3) Every 12 hours         - 0 */12 * * *"
    echo "  4) Weekly (Sunday 2 AM)   - 0 2 * * 0"
    echo "  5) Custom cron expression"
    echo "  6) Skip (configure manually later)"
    echo ""
    read -p "Choose schedule [1-6] (default: 1): " SCHEDULE_CHOICE
    SCHEDULE_CHOICE="${SCHEDULE_CHOICE:-1}"
    
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
      read -p "Backup environment variables too? [Y/n]: " BACKUP_ENVS
      BACKUP_ENVS="${BACKUP_ENVS:-Y}"
      ENVS_FLAG=""
      if [[ "$BACKUP_ENVS" =~ ^[Yy]$ ]] || [[ -z "$BACKUP_ENVS" ]]; then
        ENVS_FLAG=" --backup-envs"
      fi
      
      # Create cron command
      LOG_FILE="/var/log/portainer_backup.log"
      CRON_COMMAND="$CRON_SCHEDULE $DEST_DIR/backup_stacks.sh -d $BACKUP_DIR$ENVS_FLAG >> $LOG_FILE 2>&1"
      
      echo ""
      echo "Cron job to be added:"
      echo "  $CRON_COMMAND"
      echo ""
      read -p "Add this to root's crontab? [Y/n]: " ADD_CRON
      ADD_CRON="${ADD_CRON:-Y}"
      
      if [[ "$ADD_CRON" =~ ^[Yy]$ ]] || [[ -z "$ADD_CRON" ]]; then
        # Add to crontab
        (sudo crontab -l 2>/dev/null | grep -v "backup_stacks.sh"; echo "$CRON_COMMAND") | sudo crontab -
        echo "✓ Cron job added successfully!"
        echo ""
        echo "View with: sudo crontab -l"
        echo "Logs will be written to: $LOG_FILE"
        
        # Offer to set up logrotate
        echo ""
        if [ "$LOGROTATE_AVAILABLE" = true ]; then
          read -p "Set up automatic log rotation? [Y/n]: " SETUP_LOGROTATE
          SETUP_LOGROTATE="${SETUP_LOGROTATE:-Y}"
          if [[ "$SETUP_LOGROTATE" =~ ^[Yy]$ ]] || [[ -z "$SETUP_LOGROTATE" ]]; then
            LOGROTATE_CONF="/etc/logrotate.d/portainer-backup"
            sudo tee "$LOGROTATE_CONF" > /dev/null << LOGROTATE_EOF
$LOG_FILE {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
LOGROTATE_EOF
            echo "✓ Logrotate configured at $LOGROTATE_CONF"
            echo "  - Rotates daily, keeps 14 days of logs"
            echo "  - Old logs are compressed to save space"
          else
            echo "⚠ Warning: Log file will grow indefinitely without rotation!"
            echo "  Consider setting up logrotate manually or redirecting to /dev/null"
          fi
        else
          echo "⚠ logrotate is not installed, skipping log rotation setup"
          echo "  Install logrotate and run: sudo logrotate /etc/logrotate.d/portainer-backup"
          echo "  Or redirect logs to /dev/null in your cron job"
        fi
      else
        echo "⚠ Cron job not added. To add manually:"
        echo "  sudo crontab -e"
        echo "  Then add: $CRON_COMMAND"
      fi
    fi
    
    # Step 3: Test backup
    echo ""
    echo "───────────────────────────────────────────────────────────"
    read -p "Run a test backup now? [y/N]: " RUN_TEST
    RUN_TEST="${RUN_TEST:-N}"
    
    if [[ "$RUN_TEST" =~ ^[Yy]$ ]]; then
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
