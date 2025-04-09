# n8n Deployment Quick Reference

This document provides a quick reference for deploying and managing n8n using this Docker deployment solution.

## 📑 Navigation

[![README](https://img.shields.io/badge/📘-Main%20README-blue)](README.md)
[![Home](https://img.shields.io/badge/📖-Documentation%20Home-blueviolet)](index.md)
[![Troubleshooting](https://img.shields.io/badge/🛠️-Troubleshooting-red)](troubleshooting-guide.md)
[![Diagrams](https://img.shields.io/badge/📊-Deployment%20Diagrams-orange)](deployment-diagrams.md)
[![Layman's Guide](https://img.shields.io/badge/🧩-Layman's%20Guide-purple)](layman-guide.md)
[![Remove n8n](https://img.shields.io/badge/🗑️-Removal%20Guide-lightgrey)](remove-n8n.md)

## Deployment Options

| Deployment Type | Command                                                                                                                | Description                                         |
| --------------- | ---------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| Local           | `sudo ./setup.sh --type local`                                                                                         | Basic deployment with local storage                 |
| S3 Backup       | `sudo ./setup.sh --type s3 --s3-bucket BUCKET --aws-key KEY --aws-secret SECRET`                                       | Adds S3 backups                                     |
| Traefik HTTPS   | `sudo ./setup.sh --type traefik --domain DOMAIN --email EMAIL`                                                         | Adds HTTPS with automatic SSL                       |
| Production      | `sudo ./setup.sh --type production --domain DOMAIN --email EMAIL --s3-bucket BUCKET --aws-key KEY --aws-secret SECRET` | Complete production setup with HTTPS and S3 backups |

## Interactive Setup

For a guided setup experience:

```bash
sudo ./setup.sh
```

## Environment Variables

| Variable                       | Description              | Default        | Required For        |
| ------------------------------ | ------------------------ | -------------- | ------------------- |
| DEPLOYMENT_TYPE                | Deployment type          | local          | All                 |
| POSTGRES_USER                  | PostgreSQL username      | n8n            | All                 |
| POSTGRES_PASSWORD              | PostgreSQL password      | auto-generated | All                 |
| POSTGRES_DB                    | PostgreSQL database name | n8n            | All                 |
| N8N_ENCRYPTION_KEY             | Encryption key for n8n   | auto-generated | All                 |
| N8N_USER_MANAGEMENT_JWT_SECRET | JWT secret for n8n       | auto-generated | All                 |
| BACKUP_RETENTION_DAYS          | Days to keep backups     | 7              | All                 |
| S3_BUCKET_NAME                 | S3 bucket name           | -              | S3, Production      |
| AWS_ACCESS_KEY_ID              | AWS access key           | -              | S3, Production      |
| AWS_SECRET_ACCESS_KEY          | AWS secret key           | -              | S3, Production      |
| AWS_REGION                     | AWS region               | us-east-1      | S3, Production      |
| DOMAIN_NAME                    | Domain name for n8n      | -              | Traefik, Production |
| ACME_EMAIL                     | Email for Let's Encrypt  | -              | Traefik, Production |

## Common Commands

### Start/Stop Services

```bash
# Start services
cd /path/to/n8n-deployment-docker
docker-compose up -d

# Stop services
docker-compose down

# Restart services
docker-compose restart
```

### View Logs

```bash
# View n8n logs
docker logs n8n

# View PostgreSQL logs
docker logs n8n-postgres

# View Traefik logs
docker logs n8n-traefik

# Follow logs (add -f flag)
docker logs -f n8n
```

### Backup and Restore

```bash
# Manual backup (local deployment)
sudo /opt/n8n-data/backup.sh

# Manual backup (S3 deployment)
sudo /opt/n8n-data/backup-s3.sh

# Restore from local backup
sudo /opt/n8n-data/restore.sh --backup-id YYYYMMDD_HHMMSS

# Restore from S3 backup
sudo /opt/n8n-data/restore-s3.sh --backup-id YYYYMMDD_HHMMSS
```

### Update n8n

```bash
# Pull the latest n8n image
docker pull n8nio/n8n:latest

# Restart the services
docker-compose down
docker-compose up -d
```

### Check Service Status

```bash
# Check all containers
docker ps

# Check container health
docker inspect --format='{{.State.Health.Status}}' n8n
```

## Accessing n8n

- **Local/S3 Deployment**: http://your-server-ip:5678
- **Traefik/Production Deployment**: https://your-domain.com

## Accessing Traefik Dashboard

For Traefik and Production deployments:

- URL: https://traefik.your-domain.com
- Username: admin
- Password: (Generated during setup - check console output)

## Troubleshooting

### Common Issues

1. **n8n fails to start**:

   - Check logs: `docker logs n8n`
   - Verify PostgreSQL is running: `docker ps | grep postgres`
   - Check environment variables in `.env`

2. **Backup fails**:

   - Check disk space: `df -h /opt/n8n-data`
   - For S3 backups, verify AWS credentials and bucket permissions
   - Check backup logs: `cat /opt/n8n-data/backup.log`

3. **Traefik SSL certificate issues**:

   - Ensure your domain points to the server's IP
   - Check Traefik logs: `docker logs n8n-traefik`
   - Verify that ports 80 and 443 are open in your firewall

4. **Database connection issues**:
   - Check PostgreSQL logs: `docker logs n8n-postgres`
   - Verify database credentials in `.env`
   - Check if PostgreSQL container is running: `docker ps | grep postgres`

### Viewing Logs

```bash
# View deployment log
cat /opt/n8n-data/deployment.log

# View backup log
cat /opt/n8n-data/backup.log
```

### Removing n8n

```bash
# Interactive removal
sudo ./utils/remove-n8n.sh

# Remove everything
sudo ./utils/remove-n8n.sh --all

# Remove only containers
sudo ./utils/remove-n8n.sh --containers
```

## Additional Resources

- [Deployment Diagrams](deployment-diagrams.md) - Visual explanation of deployment options
- [Troubleshooting Guide](troubleshooting-guide.md) - Detailed troubleshooting information
- [n8n Documentation](https://docs.n8n.io/) - Official n8n documentation

## 📑 Navigation

[![README](https://img.shields.io/badge/📘-Main%20README-blue)](README.md)
[![Home](https://img.shields.io/badge/📖-Documentation%20Home-blueviolet)](index.md)
[![Troubleshooting](https://img.shields.io/badge/🛠️-Troubleshooting-red)](troubleshooting-guide.md)
[![Diagrams](https://img.shields.io/badge/📊-Deployment%20Diagrams-orange)](deployment-diagrams.md)
[![Layman's Guide](https://img.shields.io/badge/🧩-Layman's%20Guide-purple)](layman-guide.md)
[![Remove n8n](https://img.shields.io/badge/🗑️-Removal%20Guide-lightgrey)](remove-n8n.md)
