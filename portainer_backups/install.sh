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
  -i, --interactive  Interactive/guided setup (creates backup dir, configures cron)
  -s, --simple       Simple install only (no configuration)
  -u, --update       Update existing installation (keeps current config)
  -h, --help         Show this help message

Examples:
  sudo ./install.sh                              # Show menu to choose mode
  sudo ./install.sh -i                           # Full guided setup
  sudo ./install.sh -s                           # Simple install only
  sudo ./install.sh -u                           # Update script only
  sudo ./install.sh /opt/scripts                 # Install to custom directory
  sudo ./install.sh -i /opt/scripts              # Interactive with custom install dir

Installation modes:
  Interactive (-i):
    1. Check and install dependencies (jq, cron, logrotate)
    2. Install the script
    3. Collect configuration (backup dir, schedule, etc.)
    4. Show review of all changes
    5. Apply changes after confirmation
    6. Optionally test the backup

  Simple (-s):
    1. Checks and installs dependencies
    2. Installs the script only
    3. Shows usage examples for manual configuration

  Update (-u):
    1. Updates the script to latest version
    2. Preserves existing cron jobs and configuration
    3. No dependency checks or configuration changes
EOF
  exit 0
fi

# Parse options
INTERACTIVE=""
INSTALL_DIR="/usr/local/bin"

while [[ $# -gt 0 ]]; do
  case $1 in
    -i|--interactive)
      INTERACTIVE="guided"
      shift
      ;;
    -s|--simple)
      INTERACTIVE="simple"
      shift
      ;;
    -u|--update)
      INTERACTIVE="update"
      shift
      ;;
    -h|--help)
      shift
      ;;
    *)
      INSTALL_DIR="$1"
      shift
      ;;
  esac
done

# If no mode specified, show menu
if [ -z "$INTERACTIVE" ]; then
  echo "═══════════════════════════════════════════════════════════"
  echo "Portainer Backup Script Installer"
  echo "═══════════════════════════════════════════════════════════"
  echo ""
  echo "Choose installation mode:"
  echo ""
  echo "  1) Guided Setup"
  echo "     Full interactive setup with configuration, cron, and testing"
  echo ""
  echo "  2) Simple Install"
  echo "     Install script only, configure manually later"
  echo ""
  echo "  3) Update"
  echo "     Update script to latest version (keeps existing config)"
  echo ""
  echo "  4) Cancel"
  echo ""
  read -p "Enter choice [1-4]: " choice
  
  case $choice in
    1)
      INTERACTIVE="guided"
      ;;
    2)
      INTERACTIVE="simple"
      ;;
    3)
      INTERACTIVE="update"
      ;;
    4|*)
      echo "Installation cancelled."
      exit 0
      ;;
  esac
  echo ""
fi

DEST_DIR="$INSTALL_DIR"

# ============================================================================
# UPDATE MODE - Just update the script and exit
# ============================================================================

if [ "$INTERACTIVE" = "update" ]; then
  echo "═══════════════════════════════════════════════════════════"
  echo "Update Mode - Updating script only"
  echo "═══════════════════════════════════════════════════════════"
  echo ""
  
  if [ ! -f "$DEST_DIR/backup_stacks.sh" ]; then
    echo "❌ No existing installation found at $DEST_DIR/backup_stacks.sh"
    echo "   Please use guided setup or simple install instead."
    exit 1
  fi
  
  echo "Updating script at $DEST_DIR/backup_stacks.sh..."
  
  if [ "$DEST_DIR" = "/usr/local/bin" ]; then
    sudo cp -a "$(dirname "$0")/backup_stacks.sh" "$DEST_DIR/backup_stacks.sh"
    sudo chmod 755 "$DEST_DIR/backup_stacks.sh"
    sudo chown root:root "$DEST_DIR/backup_stacks.sh"
  else
    sudo mkdir -p "$DEST_DIR"
    sudo cp -a "$(dirname "$0")/backup_stacks.sh" "$DEST_DIR/backup_stacks.sh"
    sudo chmod 755 "$DEST_DIR/backup_stacks.sh"
    sudo chown root:root "$DEST_DIR" "$DEST_DIR/backup_stacks.sh"
  fi
  
  echo "✓ Script updated successfully!"
  echo ""
  echo "Existing configuration (cron, logrotate) has been preserved."
  echo ""
  exit 0
fi

echo "Installing portainer backup script to $DEST_DIR"
echo ""

# ============================================================================
# DEPENDENCY CHECKS
# ============================================================================

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
      echo "❌ Could not detect package manager. Please install jq manually."
      exit 1
    fi
    echo "✓ jq installed successfully"
  else
    echo "❌ jq is required. Please install it and run this script again."
    exit 1
  fi
else
  echo "✓ jq is installed"
fi

# Check for docker
if ! command -v docker >/dev/null 2>&1; then
  echo "❌ docker is not installed or not in PATH"
  echo "   This script requires Docker. Install from: https://docs.docker.com/engine/install/"
  exit 1
else
  echo "✓ docker is installed"
fi

# Check for cron/crontab (needed for scheduling)
CRON_AVAILABLE=false
if command -v crontab >/dev/null 2>&1; then
  echo "✓ cron is installed"
  CRON_AVAILABLE=true
else
  echo "⚠ cron is not installed (needed for scheduling)"
  read -p "Install cron now? [Y/n]: " INSTALL_CRON
  INSTALL_CRON="${INSTALL_CRON:-Y}"
  if [[ "$INSTALL_CRON" =~ ^[Yy]$ ]] || [[ -z "$INSTALL_CRON" ]]; then
    echo "Installing cron..."
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get install -y cron
      sudo systemctl enable cron 2>/dev/null || true
      sudo systemctl start cron 2>/dev/null || true
    elif command -v yum >/dev/null 2>&1; then
      sudo yum install -y cronie
      sudo systemctl enable crond 2>/dev/null || true
      sudo systemctl start crond 2>/dev/null || true
    elif command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y cronie
      sudo systemctl enable crond 2>/dev/null || true
      sudo systemctl start crond 2>/dev/null || true
    elif command -v pacman >/dev/null 2>&1; then
      sudo pacman -S --noconfirm cronie
      sudo systemctl enable cronie 2>/dev/null || true
      sudo systemctl start cronie 2>/dev/null || true
    else
      echo "⚠ Could not install cron. Scheduling will not be available."
      CRON_AVAILABLE=false
    fi
    if command -v crontab >/dev/null 2>&1; then
      echo "✓ cron installed successfully"
      CRON_AVAILABLE=true
    fi
  else
    echo "⚠ Skipping cron (automatic scheduling won't be available)"
  fi
fi

# Check for logrotate (optional but recommended)
LOGROTATE_AVAILABLE=false
if command -v logrotate >/dev/null 2>&1; then
  echo "✓ logrotate is installed"
  LOGROTATE_AVAILABLE=true
elif [ -x /usr/sbin/logrotate ]; then
  # logrotate might be in /usr/sbin which may not be in PATH for non-root users
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
      echo "⚠ Could not install logrotate. You can install it manually later."
      LOGROTATE_AVAILABLE=false
    fi
    # Check again in both PATH and /usr/sbin
    if command -v logrotate >/dev/null 2>&1 || [ -x /usr/sbin/logrotate ]; then
      echo "✓ logrotate installed successfully"
      LOGROTATE_AVAILABLE=true
    fi
  else
    echo "⚠ Skipping logrotate (you can set it up manually later)"
  fi
fi

echo ""

# ============================================================================
# INSTALL SCRIPT
# ============================================================================

if [ "$DEST_DIR" = "/usr/local/bin" ]; then
  sudo cp -a "$(dirname "$0")/backup_stacks.sh" "$DEST_DIR/backup_stacks.sh"
  sudo chmod 755 "$DEST_DIR/backup_stacks.sh"
  sudo chown root:root "$DEST_DIR/backup_stacks.sh"
  echo "✓ Script installed to $DEST_DIR/backup_stacks.sh"
else
  sudo mkdir -p "$DEST_DIR"
  sudo cp -a "$(dirname "$0")/backup_stacks.sh" "$DEST_DIR/backup_stacks.sh"
  sudo chmod 755 "$DEST_DIR/backup_stacks.sh"
  sudo chown root:root "$DEST_DIR" "$DEST_DIR/backup_stacks.sh"
  echo "✓ Script installed to $DEST_DIR/backup_stacks.sh"
fi

echo ""
echo "✓ Script installed successfully!"
echo ""

# ============================================================================
# INTERACTIVE SETUP MODE
# ============================================================================

if [ "$INTERACTIVE" = "guided" ]; then
  echo "═══════════════════════════════════════════════════════════"
  echo "Guided Setup - Configuration"
  echo "═══════════════════════════════════════════════════════════"
  echo ""
  echo "💡 Tip: Press Enter to accept defaults shown in [brackets]"
  echo ""
  
  # === DETECT EXISTING CONFIGURATION ===
  
  # Check for existing cron job to extract current settings
  EXISTING_CRON=$(crontab -l 2>/dev/null | grep "backup_stacks.sh" || true)
  CURRENT_BACKUP_DIR=""
  CURRENT_BACKUP_ENVS=""
  
  if [ -n "$EXISTING_CRON" ]; then
    echo "📋 Existing configuration detected"
    # Extract backup directory from cron command
    CURRENT_BACKUP_DIR=$(echo "$EXISTING_CRON" | grep -oP '\-d\s+\K[^\s]+' || true)
    # Check if --backup-envs flag is present
    if echo "$EXISTING_CRON" | grep -q '\-\-backup-envs'; then
      CURRENT_BACKUP_ENVS="yes"
    fi
    echo ""
  fi
  
  # === COLLECT CONFIGURATION (don't execute yet) ===
  
  # Backup directory
  if [ -n "$CURRENT_BACKUP_DIR" ]; then
    DEFAULT_BACKUP_DIR="$CURRENT_BACKUP_DIR"
    echo "Current backup directory: $CURRENT_BACKUP_DIR"
  else
    DEFAULT_BACKUP_DIR="/var/backups/portainer"
  fi
  read -p "Enter backup directory path [$DEFAULT_BACKUP_DIR]: " BACKUP_DIR
  BACKUP_DIR="${BACKUP_DIR:-$DEFAULT_BACKUP_DIR}"
  
  WILL_CREATE_DIR=false
  if [ -n "$BACKUP_DIR" ] && [ ! -d "$BACKUP_DIR" ]; then
    read -p "Create directory $BACKUP_DIR? [Y/n]: " CREATE_DIR
    CREATE_DIR="${CREATE_DIR:-Y}"
    if [[ "$CREATE_DIR" =~ ^[Yy]$ ]] || [[ -z "$CREATE_DIR" ]]; then
      WILL_CREATE_DIR=true
    fi
  fi
  
  # Cron schedule
  echo ""
  CRON_SCHEDULE=""
  EXISTING_CRON=""
  CURRENT_CRON_SCHEDULE=""
  if [ "$CRON_AVAILABLE" = false ]; then
    echo "⚠ cron is not available, skipping schedule setup"
  else
    # Check for existing cron job
    EXISTING_CRON=$(crontab -l 2>/dev/null | grep "backup_stacks.sh" || true)
    
    if [ -n "$EXISTING_CRON" ]; then
      # Extract the schedule part (first 5 fields)
      CURRENT_CRON_SCHEDULE=$(echo "$EXISTING_CRON" | awk '{print $1" "$2" "$3" "$4" "$5}')
      echo "Existing cron job found:"
      echo "  Schedule: $CURRENT_CRON_SCHEDULE"
      echo "  Full: $EXISTING_CRON"
      echo ""
      read -p "Update existing cron schedule? [y/N]: " UPDATE_CRON
      UPDATE_CRON="${UPDATE_CRON:-N}"
      
      if [[ ! "$UPDATE_CRON" =~ ^[Yy]$ ]]; then
        echo "Keeping existing cron schedule"
        CRON_SCHEDULE="KEEP_EXISTING"
      fi
    fi
    
    if [ "$CRON_SCHEDULE" != "KEEP_EXISTING" ]; then
      if [ -n "$CURRENT_CRON_SCHEDULE" ]; then
        echo "Current schedule: $CURRENT_CRON_SCHEDULE"
        echo ""
      fi
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
          CRON_SCHEDULE=""
          ;;
        *)
          echo "⚠ Invalid choice, skipping cron setup"
          CRON_SCHEDULE=""
          ;;
      esac
    fi
  fi
  
  # Environment variables
  ENVS_FLAG=""
  if [ -n "$CRON_SCHEDULE" ] && [ "$CRON_SCHEDULE" != "KEEP_EXISTING" ]; then
    echo ""
    if [ "$CURRENT_BACKUP_ENVS" = "yes" ]; then
      echo "Current setting: Backup environment variables enabled"
      read -p "Backup environment variables too? [Y/n]: " BACKUP_ENVS
      BACKUP_ENVS="${BACKUP_ENVS:-Y}"
    else
      read -p "Backup environment variables too? [Y/n]: " BACKUP_ENVS
      BACKUP_ENVS="${BACKUP_ENVS:-Y}"
    fi
    if [[ "$BACKUP_ENVS" =~ ^[Yy]$ ]] || [[ -z "$BACKUP_ENVS" ]]; then
      ENVS_FLAG=" --backup-envs"
    fi
  elif [ "$CRON_SCHEDULE" = "KEEP_EXISTING" ] && [ "$CURRENT_BACKUP_ENVS" = "yes" ]; then
    ENVS_FLAG=" --backup-envs"
  fi
  
  # Log rotation
  SETUP_LOGROTATE="N"
  if [ "$LOGROTATE_AVAILABLE" = true ] && [ -n "$CRON_SCHEDULE" ]; then
    # Check if logrotate config already exists
    if [ -f "/etc/logrotate.d/portainer-backup" ]; then
      echo ""
      echo "Note: logrotate configuration already exists at /etc/logrotate.d/portainer-backup"
      read -p "Overwrite existing log rotation config? [y/N]: " SETUP_LOGROTATE
      SETUP_LOGROTATE="${SETUP_LOGROTATE:-N}"
    else
      echo ""
      read -p "Set up automatic log rotation? [Y/n]: " SETUP_LOGROTATE
      SETUP_LOGROTATE="${SETUP_LOGROTATE:-Y}"
    fi
  fi
  
  # Test backup
  echo ""
  read -p "Run a test backup after setup? [y/N]: " RUN_TEST
  RUN_TEST="${RUN_TEST:-N}"
  
  # === SHOW REVIEW ===
  echo ""
  echo "═══════════════════════════════════════════════════════════"
  echo "Review Configuration"
  echo "═══════════════════════════════════════════════════════════"
  echo ""
  echo "The following changes will be made:"
  echo ""
  
  STEP_NUM=1
  
  # Show what will be created/configured
  if [ "$WILL_CREATE_DIR" = true ]; then
    echo "  $STEP_NUM. Create backup directory:"
    echo "     sudo mkdir -p $BACKUP_DIR"
    echo "     sudo chmod 755 $BACKUP_DIR"
    STEP_NUM=$((STEP_NUM + 1))
  elif [ -d "$BACKUP_DIR" ]; then
    echo "  $STEP_NUM. Use existing backup directory:"
    echo "     $BACKUP_DIR"
    STEP_NUM=$((STEP_NUM + 1))
  fi
  
  if [ -n "$CRON_SCHEDULE" ] && [ "$CRON_SCHEDULE" != "KEEP_EXISTING" ]; then
    LOG_FILE="/var/log/portainer_backup.log"
    CRON_COMMAND="$CRON_SCHEDULE $DEST_DIR/backup_stacks.sh -d $BACKUP_DIR$ENVS_FLAG >> $LOG_FILE 2>&1"
    if [ -n "$EXISTING_CRON" ]; then
      echo "  $STEP_NUM. Update cron job in root's crontab:"
    else
      echo "  $STEP_NUM. Add cron job to root's crontab:"
    fi
    echo "     $CRON_COMMAND"
    STEP_NUM=$((STEP_NUM + 1))
  elif [ "$CRON_SCHEDULE" = "KEEP_EXISTING" ]; then
    # Extract log file from existing cron or use default
    LOG_FILE=$(echo "$EXISTING_CRON" | grep -oP '>> \K[^ ]+' || echo "/var/log/portainer_backup.log")
    echo "  $STEP_NUM. Keep existing cron job:"
    echo "     $EXISTING_CRON"
    STEP_NUM=$((STEP_NUM + 1))
  fi
  
  if [[ "$SETUP_LOGROTATE" =~ ^[Yy]$ ]]; then
    echo "  $STEP_NUM. Create logrotate configuration:"
    echo "     /etc/logrotate.d/portainer-backup"
    echo "     (rotates daily, keeps 14 days, compresses old logs)"
    STEP_NUM=$((STEP_NUM + 1))
  fi
  
  if [[ "$RUN_TEST" =~ ^[Yy]$ ]]; then
    echo "  $STEP_NUM. Run test backup:"
    echo "     $DEST_DIR/backup_stacks.sh -d $BACKUP_DIR$ENVS_FLAG"
    STEP_NUM=$((STEP_NUM + 1))
  fi
  
  if [ $STEP_NUM -eq 1 ]; then
    echo "  (No additional changes)"
  fi
  
  echo ""
  echo "═══════════════════════════════════════════════════════════"
  read -p "Apply these changes? [Y/n]: " CONFIRM
  CONFIRM="${CONFIRM:-Y}"
  
  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]] && [[ -n "$CONFIRM" ]]; then
    echo ""
    echo "❌ Installation cancelled. No changes were made."
    echo "   The script is installed but not configured."
    echo "   You can run './install.sh -i' again to configure it."
    exit 0
  fi
  
  # === EXECUTE CHANGES ===
  echo ""
  echo "───────────────────────────────────────────────────────────"
  echo "Applying changes..."
  echo "───────────────────────────────────────────────────────────"
  echo ""
  
  # Create directory
  if [ "$WILL_CREATE_DIR" = true ]; then
    sudo mkdir -p "$BACKUP_DIR"
    sudo chmod 755 "$BACKUP_DIR"
    echo "✓ Created backup directory: $BACKUP_DIR"
  fi
  
  # Add or update cron job
  if [ -n "$CRON_SCHEDULE" ] && [ "$CRON_SCHEDULE" != "KEEP_EXISTING" ]; then
    # Create temp file with new crontab
    TEMP_CRON=$(mktemp)
    crontab -l 2>/dev/null | grep -v "backup_stacks.sh" > "$TEMP_CRON" || true
    echo "$CRON_COMMAND" >> "$TEMP_CRON"
    crontab "$TEMP_CRON"
    rm -f "$TEMP_CRON"
    
    if [ -n "$EXISTING_CRON" ]; then
      echo "✓ Updated cron job"
    else
      echo "✓ Added cron job"
    fi
    echo "  View with: sudo crontab -l"
    echo "  Logs: $LOG_FILE"
  elif [ "$CRON_SCHEDULE" = "KEEP_EXISTING" ]; then
    echo "✓ Kept existing cron job"
  fi
  
  # Setup logrotate
  if [[ "$SETUP_LOGROTATE" =~ ^[Yy]$ ]]; then
    LOGROTATE_CONF="/etc/logrotate.d/portainer-backup"
    sudo tee "$LOGROTATE_CONF" > /dev/null << 'LOGROTATE_EOF'
/var/log/portainer_backup.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
LOGROTATE_EOF
    echo "✓ Configured logrotate: $LOGROTATE_CONF"
  fi
  
  # Run test backup
  if [[ "$RUN_TEST" =~ ^[Yy]$ ]]; then
    echo ""
    echo "───────────────────────────────────────────────────────────"
    echo "Running test backup..."
    echo "───────────────────────────────────────────────────────────"
    BACKUP_CMD="$DEST_DIR/backup_stacks.sh -d $BACKUP_DIR$ENVS_FLAG"
    echo "Command: $BACKUP_CMD"
    echo ""
    sudo $BACKUP_CMD
  fi
  
  echo ""
  echo "═══════════════════════════════════════════════════════════"
  echo "Setup Complete!"
  echo "═══════════════════════════════════════════════════════════"
  echo ""
  if [ -n "$CRON_SCHEDULE" ]; then
    echo "✓ Automatic backups configured"
    echo "  Schedule: $CRON_SCHEDULE"
    echo "  Destination: $BACKUP_DIR"
    if [ -n "$LOG_FILE" ]; then
      echo "  Logs: $LOG_FILE"
    fi
  fi
  
  
else
  # Non-interactive mode - show examples
  echo "═══════════════════════════════════════════════════════════"
  echo "Installation complete!"
  echo "═══════════════════════════════════════════════════════════"
  echo ""
  echo "The script reads directly from Portainer database - no API needed!"
  echo ""
  echo "Quick start examples:"
  echo ""
  echo "  # Backup to local directory with environment variables"
  echo "  backup_stacks.sh -d /backup/portainer --backup-envs"
  echo ""
  echo "  # Backup to network location"
  echo "  backup_stacks.sh -d /mnt/nas/portainer-backups --backup-envs"
  echo ""
  echo "  # Test first with dry run"
  echo "  backup_stacks.sh -d /backup/portainer --backup-envs --dry-run"
  echo ""
  echo "For all options: backup_stacks.sh --help"
  echo ""
  echo "───────────────────────────────────────────────────────────"
  echo "To configure automatically with guided setup:"
  echo "  sudo ./install.sh -i"
  echo "───────────────────────────────────────────────────────────"
fi

echo ""
