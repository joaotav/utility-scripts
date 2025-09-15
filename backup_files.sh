#!/bin/bash
set -euo pipefail

# =============================================================================
# MOUNT VALIDATION (single source of truth)
# =============================================================================
validate_mount_simple() {
  local mp="$1"
  echo "Checking backup drive: $mp"

  # 0) exists (good UX to show available drives if not)
  if [ ! -d "$mp" ]; then
    echo "Error: Path '$mp' does not exist."
    echo ""
    echo "Available mounted drives:"
    ls -la "/media/$USER/" 2>/dev/null || echo "No drives found in /media/$USER/"
    exit 1
  fi

  # 1) must really be a mount point
  if ! mountpoint -q -- "$mp"; then
    echo "Error: '$mp' is not a mounted filesystem."
    echo ""
    echo "Currently mounted under /media/$USER/:"
    findmnt -rn -o TARGET | grep -E "^/media/$USER" || echo "None"
    exit 2
  fi

  # 2) must be writable + mounted rw
  if ! test -w "$mp"; then
    echo "Error: '$mp' is not writable." >&2
    exit 3
  fi
  local opts
  opts="$(findmnt -rn -o OPTIONS --target "$mp")"
  if ! grep -q '\brw\b' <<<"$opts"; then
    echo "Error: '$mp' is mounted read-only (opts: $opts)." >&2
    exit 4
  fi
}

# =============================================================================
# BORG BACKUP CONFIGURATION
# Modify these settings to customize your backup behavior
# =============================================================================

# Compression options:
# - lz4: Fastest, low compression
# - zstd,1-22: Good balance (higher = better compression, slower)
# - zlib,1-9: Good compression
# - lzma,0-9: Best compression, slowest
COMPRESSION="zstd,3"

# Chunker parameters for deduplication (min_size,avg_size,max_size,hash_mask)
# Better for large files: 19,23,21,4095 (512KB-2MB chunks)
CHUNKER_PARAMS="19,23,21,4095"

# Create checkpoint every X seconds (useful for large backups)
CHECKPOINT_INTERVAL="1800"  # 30 minutes

# Archive retention policy - Weekly backup strategy
KEEP_WEEKLY="4"     # Keep 4 weekly backups (1 month)
KEEP_DAILY="1"      # Keep 1 daily (safety net)
KEEP_MONTHLY="0"    # No monthly retention
KEEP_YEARLY="0"     # No yearly retention

# Performance tuning
FILES_CACHE_TTL="20"          # File stat cache TTL in seconds
CACHE_QUOTA_WARNING="75"      # Warn when cache hits this % of disk

# Backup exclusion patterns (add more as needed)
EXCLUDE_PATTERNS=(
    "$HOME/.cache"
    "$HOME/.dbus"
    "$HOME/.dropbox"
    "$HOME/.docker"
    "$HOME/node_modules"
    "$HOME/go/pkg/mod"
    "$HOME/.local/share/Trash"
    "$HOME/.gvfs"
    "$HOME/.xsession-errors*"
    "$HOME/.mozilla/firefox/*/storage"
    "$HOME/.config/google-chrome/*/Service Worker"
    "$HOME/.config/chromium/*/Service Worker"
    "$HOME/.cargo/registry"
    "$HOME/.cargo/git"
    "$HOME/.rustup/toolchains/*/share"
    # Add your custom exclusions here:
    # "$HOME/Downloads"
    # "$HOME/Videos"
    # "$HOME/Music"
)

# Borg environment variables for security and behavior
export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes           # Allow moved repositories
export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=no  # Prevent unencrypted access
export BORG_DELETE_I_KNOW_WHAT_I_AM_DOING=no          # Prevent accidental deletions
export BORG_SHOW_SYSINFO=yes                          # Show system info in logs
export BORG_FILES_CACHE_TTL="$FILES_CACHE_TTL"
export BORG_CACHE_QUOTA_WARNING="$CACHE_QUOTA_WARNING"

# =============================================================================
# END CONFIGURATION - Script logic begins below
# =============================================================================

# Check for required argument
if [ $# -eq 0 ]; then
    echo "Usage: $0 <external_drive_path>"
    echo "Example: $0 /media/\$USER/MyBackupDrive"
    echo "Example: $0 /mnt/backup-usb"
    echo ""
    echo "Available mounted drives:"
    ls -la "/media/$USER/" 2>/dev/null || echo "No drives found in /media/$USER/"
    exit 1
fi

# Set variables
DATE="$(date +'%Y-%m-%d_%H%M')"                  # finer-grained to avoid collisions
HOST="$(hostname -s)"
TMP_DIR="/tmp/system-backup-$DATE"
EXTERNAL_DRIVE="$1"

# Single, unified validation (replaces redundant checks)
validate_mount_simple "$EXTERNAL_DRIVE"

BORG_REPO="$EXTERNAL_DRIVE/system-backups"
ARCHIVE_PREFIX="system-backup-"
ARCHIVE_NAME="${ARCHIVE_PREFIX}${HOST}-${DATE}"

echo "Using backup drive: $EXTERNAL_DRIVE"
echo "Borg repository: $BORG_REPO"
echo "Archive name: $ARCHIVE_NAME"

# Function to prompt for encryption passphrase
prompt_for_passphrase() {
    local pass1 pass2
    while true; do
        echo -n "Enter encryption passphrase: "
        read -s pass1
        echo
        echo -n "Confirm encryption passphrase: "
        read -s pass2
        echo
        if [ "$pass1" = "$pass2" ]; then
            if [ -z "$pass1" ]; then
                echo "Error: Passphrase cannot be empty. Please try again."
                continue
            fi
            export BORG_PASSPHRASE="$pass1"
            echo "Passphrases match. Repository will be encrypted."
            break
        else
            echo "Error: Passphrases do not match. Please try again."
        fi
    done
}

# Initialize borg repo if it doesn't exist
if [ ! -d "$BORG_REPO" ]; then
    echo "Initializing new encrypted Borg repository at $BORG_REPO..."
    prompt_for_passphrase
    mkdir -p "$BORG_REPO"
    borg init --encryption=repokey "$BORG_REPO"
    echo "Repository initialized successfully!"
    echo "Your encryption key is stored in the repository (encrypted with your passphrase)."
else
    # For existing repo, prompt for passphrase if not provided
    if [ -z "${BORG_PASSPHRASE:-}" ]; then
        echo -n "Enter repository passphrase: "
        read -s BORG_PASSPHRASE
        echo
        export BORG_PASSPHRASE
    fi
fi

if [ -d "$TMP_DIR" ]; then
    echo "Previous backup directory exists. Attempting cleanup..."
    sudo rm -rf "$TMP_DIR" 2>/dev/null || {
        echo "Cannot remove previous backup data at: $TMP_DIR. Quitting"
        exit 1
    }
fi
mkdir -p "$TMP_DIR"

echo "Backing up apt-clone data..."
sudo apt-clone clone "$TMP_DIR/apt-clone.tar.gz" >/dev/null 2>&1 || true

echo "Saving list of installed APT packages..."
dpkg --get-selections > "$TMP_DIR/dpkg-selections.txt" || true

echo "Saving list of installed Snap packages..."
snap list > "$TMP_DIR/snap-packages.txt" || true

echo "Creating Borg archive with optimized settings..."
echo "Compression: $COMPRESSION"
echo "Chunker parameters: $CHUNKER_PARAMS"
echo "Exclusions: ${#EXCLUDE_PATTERNS[@]} patterns"

# Build exclude arguments from the patterns array
EXCLUDE_ARGS=()
for pattern in "${EXCLUDE_PATTERNS[@]}"; do
    EXCLUDE_ARGS+=("--exclude" "$pattern")
done

borg create \
  --stats \
  --progress \
  --verbose \
  --filter AME \
  --list \
  --show-rc \
  --lock-wait 120 \
  --compression "$COMPRESSION" \
  --chunker-params "$CHUNKER_PARAMS" \
  --checkpoint-interval "$CHECKPOINT_INTERVAL" \
  --one-file-system \
  --numeric-owner \
  --exclude-caches \
  --keep-exclude-tags \
  "${EXCLUDE_ARGS[@]}" \
  "$BORG_REPO::$ARCHIVE_NAME" \
  "$HOME" \
  "$TMP_DIR"

echo "Cleaning up temporary files..."
rm -rf "$TMP_DIR" 2>/dev/null || true

echo "Pruning old archives..."
borg prune \
  --list \
  --show-rc \
  --lock-wait 120 \
  --prefix "$ARCHIVE_PREFIX" \
  --keep-daily "$KEEP_DAILY" \
  --keep-weekly "$KEEP_WEEKLY" \
  --keep-monthly "$KEEP_MONTHLY" \
  --keep-yearly "$KEEP_YEARLY" \
  "$BORG_REPO"

echo "Running repository maintenance..."
borg compact "$BORG_REPO"

echo "Backup completed successfully: $BORG_REPO::$ARCHIVE_NAME"
echo ""
echo "=== Archive Information ==="
borg info "$BORG_REPO::$ARCHIVE_NAME" || true

echo ""
echo "=== Repository Summary ==="
borg info "$BORG_REPO" || true
