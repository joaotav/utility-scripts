#!/bin/bash
set -e

# Check for required argument
if [ $# -eq 0 ]; then
    echo "Usage: $0 <external_drive_path>"
    echo "Example: $0 /media/$USER/MyBackupDrive"
    echo "Example: $0 /mnt/backup-usb"
    echo ""
    echo "Available mounted drives:"
    ls -la "/media/$USER/" 2>/dev/null || echo "No drives found in /media/$USER/"
    exit 1
fi

# Set variables
DATE=$(date +"%Y-%b-%d")
TMP_DIR="/tmp/system-backup-$DATE"
EXTERNAL_DRIVE="$1"
BORG_REPO="$EXTERNAL_DRIVE/system-backups"
ARCHIVE_NAME="system-backup-$DATE"

# Check if external drive path exists
echo "Checking backup drive: $EXTERNAL_DRIVE"
if [ ! -d "$EXTERNAL_DRIVE" ]; then
    echo "Error: Drive path '$EXTERNAL_DRIVE' not found or not mounted."
    echo ""
    echo "Available mounted drives:"
    ls -la "/media/$USER/" 2>/dev/null || echo "No drives found in /media/$USER/"
    exit 1
fi

echo "Using backup drive: $EXTERNAL_DRIVE"
echo "Borg repository: $BORG_REPO"

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
    # For existing repo, prompt for passphrase
    if [ -z "$BORG_PASSPHRASE" ]; then
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
sudo apt-clone clone "$TMP_DIR/apt-clone.tar.gz" >/dev/null 2>&1

echo "Saving list of installed APT packages..."
dpkg --get-selections > "$TMP_DIR/dpkg-selections.txt"

echo "Saving list of installed Snap packages..."
snap list > "$TMP_DIR/snap-packages.txt"

echo "Backing up home directory (excluding temp/cache folders)..."
rsync -a --numeric-ids --info=progress2 \
  --exclude=".cache/" --exclude=".dbus/" --exclude=".dropbox/" \
  --exclude=".docker/" --exclude="node_modules/" \
  --exclude="go/pkg/mod/" \
  "$HOME/" "$TMP_DIR/home/" || [[ $? == 24 ]]

echo "Creating Borg archive..."
borg create --stats --progress "$BORG_REPO::$ARCHIVE_NAME" "$TMP_DIR"

echo "Cleaning up temporary files..."
rm -rf "$TMP_DIR" 2>/dev/null || true

echo "Backup completed successfully: $BORG_REPO::$ARCHIVE_NAME"
echo "Archive info:"
borg info "$BORG_REPO::$ARCHIVE_NAME"