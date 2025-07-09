#!/bin/bash
set -e

# Set variables
DATE=$(date +"%Y-%b-%d")
TMP_DIR="/tmp/system-backup-$DATE" 
BACKUP_FILE="$HOME/Desktop/system-backup-$DATE.tar.gz"

rm -rf "$TMP_DIR"
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
  --exclude="go/pkg/mod/"
  "$HOME/" "$TMP_DIR/home/" || [[ $? == 24 ]]

echo "Compressing backup data..."
tar -C "/tmp" -czf "$BACKUP_FILE" "system-backup-$DATE"

echo "Cleaning up temporary files..."
rm -rf "$TMP_DIR" 2>/dev/null || true

echo "Backup completed successfully: $BACKUP_FILE"
echo "Backup size: $(du -h "$BACKUP_FILE" | cut -f1)"
