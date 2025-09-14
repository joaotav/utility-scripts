#!/bin/bash
set -e

# Set variables
DATE=$(date +"%Y-%b-%d")
TMP_DIR="/tmp/system-backup-$DATE" 
BORG_REPO="${BORG_REPO:-$HOME/Desktop/backups}"
ARCHIVE_NAME="system-backup-$DATE"

# Initialize borg repo if it doesn't exist
if [ ! -d "$BORG_REPO" ]; then
    echo "Initializing Borg repository at $BORG_REPO..."
    mkdir -p "$BORG_REPO"
    borg init --encryption=none "$BORG_REPO"
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