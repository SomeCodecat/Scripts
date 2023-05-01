#!/bin/bash

# Check if the script is running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root."
    exit
fi

# Check if the two USB devices are connected
if [ ! -d "/media/usb1" ] || [ ! -d "/media/usb2" ]; then
    echo "Could not find both USB devices. Please make sure they are connected and try again."
    exit
fi

# Set the folders to be backed up
FOLDERS_TO_BACKUP=(
    "/path/to/folder1/to/backup"
    "/path/to/folder2/to/backup"
    "/path/to/folder3/to/backup"
)

# Check if the folders to be backed up exist
for FOLDER_TO_BACKUP in "${FOLDERS_TO_BACKUP[@]}"; do
    if [ ! -d "$FOLDER_TO_BACKUP" ]; then
        echo "The folder '$FOLDER_TO_BACKUP' does not exist. Please make sure you have entered the correct paths and try again."
        exit
    fi
done

# Set the backup destination folders on the USB devices
USB1_BACKUP_FOLDER="/media/usb1/backup"
USB2_BACKUP_FOLDER="/media/usb2/backup"

# Create the backup destination folders on the USB devices if they don't already exist
mkdir -p $USB1_BACKUP_FOLDER
mkdir -p $USB2_BACKUP_FOLDER

# Generate the timestamp
TIMESTAMP=$(date +%d\.%m\.%Y\_\%H\_%M)

# Compress the folders to be backed up
for FOLDER_TO_BACKUP in "${FOLDERS_TO_BACKUP[@]}"; do
    zip -r $FOLDER_TO_BACKUP-$TIMESTAMP.zip $FOLDER_TO_BACKUP
done

# Perform the backup
for FOLDER_TO_BACKUP in "${FOLDERS_TO_BACKUP[@]}"; do
    rsync -a --delete $FOLDER_TO_BACKUP-$TIMESTAMP.zip $USB1_BACKUP_FOLDER
    rsync -a --delete $FOLDER_TO_BACKUP-$TIMESTAMP.zip $USB2_BACKUP_FOLDER
done

# Delete the compressed folders after the backup has completed
for FOLDER_TO_BACKUP in "${FOLDERS_TO_BACKUP[@]}"; do
    rm -f $FOLDER_TO_BACKUP-$TIMESTAMP.zip
done

echo "Backup completed successfully."
