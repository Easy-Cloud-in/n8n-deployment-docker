#!/bin/sh

# Make sure BASE_DIR is set, default if not (though it should be passed from compose)
BASE_DIR=${BASE_DIR:-/opt/n8n-data}

# Construct paths using BASE_DIR
BACKUP_SCRIPT_PATH="${BASE_DIR}/s3/backup-s3.sh"
BACKUP_LOG_PATH="${BASE_DIR}/backup.log"
CRON_FILE="/var/spool/cron/root"

# Set execute permissions for backup script if it exists
if [ -f "${BACKUP_SCRIPT_PATH}" ]; then
  chmod +x "${BACKUP_SCRIPT_PATH}"
fi

# Setup the cron job to run the backup script daily at midnight
# Ensure the cron directory exists
mkdir -p /var/spool/cron
echo "0 0 * * * ${BACKUP_SCRIPT_PATH} >> ${BACKUP_LOG_PATH} 2>&1" > "${CRON_FILE}"
chmod 0600 "${CRON_FILE}"

# Start cron in the foreground
exec crond -n -s 