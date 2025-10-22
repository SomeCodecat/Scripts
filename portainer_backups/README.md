# Portainer stacks backup

This directory contains a script to back up Portainer stack compose files into a readable backup directory.

Files

- `backup_stacks.sh` - main backup script. Edit the variables at the top (PORTAINER_URL, PORTAINER_API_KEY, BACKUP_DIR) before use.
- `install.sh` - helper to install the script into `/opt/portainer_backups/`, create the backups dir, and set permissions.
- `backup_stacks.conf` - configuration file. Edit this file to change behavior; no need to modify `backup_stacks.sh`.

The `install.sh` helper copies `backup_stacks.conf` to `/opt/portainer_backups/` and sets secure permissions.

Cron
Use the following crontab line to run the backup daily at 03:00 and append logs to `/var/log/portainer_backup.log`:

```
0 3 * * * /opt/portainer_backups/backup_stacks.sh >> /var/log/portainer_backup.log 2>&1
```

Notes & assumptions

- The script uses `jq` and `docker` and expects a Docker volume named `portainer_data` containing Portainer's data.
- It expects compose files under `/data/compose/<STACK_ID>/docker-compose.yml` or `.yaml` inside the volume. If your Portainer layout differs, adjust the paths in the script.
- Filenames are sanitized by replacing non-alphanumeric characters with underscores.

Checksum verification
- After copying each compose file the script attempts to verify integrity by comparing a checksum calculated inside the helper container with the copied file on the host. If the container-side checksum cannot be computed (older base images), the script falls back to a host-side size/exists check. If verification fails the copy is retried up to the configured DOCKER_RETRIES.

Enhancements

- Add timestamping or rotation to keep historical backups.
- Compress backups to save space.
