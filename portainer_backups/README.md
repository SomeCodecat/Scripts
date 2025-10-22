# Portainer stacks backup

This directory contains a script to back up Portainer stack compose files into a readable backup directory.

Files

- `backup_stacks.sh` - main backup script. Edit the variables at the top (PORTAINER_URL, PORTAINER_API_KEY, BACKUP_DIR) before use.
- `install.sh` - helper to install the script into `/opt/portainer_backups/`, create the backups dir, and set permissions.

Cron
Use the following crontab line to run the backup daily at 03:00 and append logs to `/var/log/portainer_backup.log`:

```
0 3 * * * /opt/portainer_backups/backup_stacks.sh >> /var/log/portainer_backup.log 2>&1
```

Notes & assumptions

- The script uses `jq` and `docker` and expects a Docker volume named `portainer_data` containing Portainer's data.
- It expects compose files under `/data/compose/<STACK_ID>/docker-compose.yml` or `.yaml` inside the volume. If your Portainer layout differs, adjust the paths in the script.
- Filenames are sanitized by replacing non-alphanumeric characters with underscores.

Enhancements

- Add timestamping or rotation to keep historical backups.
- Compress backups to save space.
