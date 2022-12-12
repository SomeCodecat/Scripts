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

# Set the folder to be backed up
FOLDER_TO_BACKUP="/path/to/folder/to/backup"

# Check if the folder to be backed up exists
if [ ! -d "$FOLDER_TO_BACKUP" ]; then
    echo "The folder to be backed up does not exist. Please make sure you have entered the correct path and try again."
    exit
fi

# Set the backup destination folders on the USB devices
USB1_BACKUP_FOLDER="/media/usb1/backup"
USB2_BACKUP_FOLDER="/media/usb2/backup"

# Create the backup destination folders on the USB devices if they don't already exist
mkdir -p $USB1_BACKUP_FOLDER
mkdir -p $USB2_BACKUP_FOLDER

# Generate the timestamp
TIMESTAMP=$(date +%d\.%m\.%Y\ \-\ %H\:%M)

# Compress the folder to be backed up
zip -r $FOLDER_TO_BACKUP-$TIMESTAMP.zip $FOLDER_TO_BACKUP

# Perform the backup
rsync -a --delete $FOLDER_TO_BACKUP-$TIMESTAMP.zip $USB1_BACKUP_FOLDER
rsync -a --delete $FOLDER_TO_BACKUP-$TIMESTAMP.zip $USB2_BACKUP_FOLDER

# Delete the compressed folder after the backup has completed
rm -f $FOLDER_TO_BACKUP-$TIMESTAMP.zip

echo "Backup completed successfully."
