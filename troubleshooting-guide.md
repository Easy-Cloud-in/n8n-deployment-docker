# n8n Deployment Troubleshooting Guide

This guide helps you diagnose and fix common issues that might occur when deploying and running n8n.

## 📑 Navigation

[![README](https://img.shields.io/badge/📘-Main%20README-blue)](README.md)
[![Home](https://img.shields.io/badge/📖-Documentation%20Home-blueviolet)](index.md)
[![Quick Reference](https://img.shields.io/badge/🔍-Quick%20Reference-green)](quick-reference.md)
[![Diagrams](https://img.shields.io/badge/📊-Deployment%20Diagrams-orange)](deployment-diagrams.md)
[![Layman's Guide](https://img.shields.io/badge/🧩-Layman's%20Guide-purple)](layman-guide.md)
[![Remove n8n](https://img.shields.io/badge/🗑️-Removal%20Guide-lightgrey)](remove-n8n.md)

## Table of Contents

1. [Installation Issues](#installation-issues)
2. [Startup Problems](#startup-problems)
3. [Database Connection Issues](#database-connection-issues)
4. [Backup and Restore Problems](#backup-and-restore-problems)
5. [Traefik and HTTPS Issues](#traefik-and-https-issues)
6. [S3 Backup Issues](#s3-backup-issues)
7. [Performance Problems](#performance-problems)
8. [Checking Logs](#checking-logs)
9. [Removal Issues](#removal-issues)

## Installation Issues

### Docker or docker-compose Not Found

**Symptoms:**

- Error message: `command not found: docker` or `command not found: docker-compose`

**Solutions:**

1. Install Docker:

```bash
sudo apt-get update
sudo apt-get install -y docker.io
```

2. Install docker-compose:

```bash
sudo apt-get install -y docker-compose
```

If that doesn't work:

```bash
sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.3/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

### Permission Denied Errors

**Symptoms:**

- Error messages containing "Permission denied"

**Solutions:**

1. Make sure you're running commands with sudo:

```bash
sudo ./setup.sh
```

2. Check script permissions:

```bash
sudo chmod +x ./setup.sh
sudo chmod +x ./utils/remove-n8n.sh
sudo chmod +x ./utils/generate-secrets.sh
```

## Startup Problems

### n8n Container Fails to Start

**Symptoms:**

- n8n container is not listed when running `sudo docker ps`
- Error in logs about n8n failing to start

**Solutions:**

1. Check container logs:

```bash
sudo docker logs n8n
```

2. Verify PostgreSQL is running:

```bash
sudo docker ps | grep postgres
```

3. Check environment variables in .env file:

```bash
sudo cat .env
```

4. Restart the containers:

```bash
sudo docker-compose down
sudo docker-compose up -d
```

### Port Already in Use

**Symptoms:**

- Error message: "port is already allocated" or "address already in use"

**Solutions:**

1. Find what's using port 5678:

```bash
sudo lsof -i :5678
```

2. Stop the process using the port or modify the n8n port in the .env file:

```bash
# Add to .env file
N8N_PORT=5679
```

## Database Connection Issues

### n8n Can't Connect to PostgreSQL

**Symptoms:**

- Error messages about database connection in n8n logs
- Messages like "ECONNREFUSED" or "connection refused"

**Solutions:**

1. Check if PostgreSQL container is running:

```bash
sudo docker ps | grep postgres
```

2. Check PostgreSQL logs:

```bash
sudo docker logs n8n-postgres
```

3. Verify database credentials in .env file match what's in the docker-compose.yml:

```bash
sudo cat .env
sudo cat docker-compose.yml
```

4. Try restarting PostgreSQL:

```bash
sudo docker restart n8n-postgres
```

### Database Initialization Errors

**Symptoms:**

- PostgreSQL container starts but then stops
- Errors about database initialization

**Solutions:**

1. Check PostgreSQL logs:

```bash
sudo docker logs n8n-postgres
```

2. Remove PostgreSQL data directory and restart (this will delete all data!):

```bash
sudo rm -rf /opt/n8n-data/postgres/*
sudo docker-compose down
sudo docker-compose up -d
```

## Backup and Restore Problems

### Backup Script Fails

**Symptoms:**

- Backup script exits with error
- No backup files created

**Solutions:**

1. Check backup logs:

```bash
sudo cat /opt/n8n-data/backup.log
```

2. Verify disk space:

```bash
df -h /opt/n8n-data
```

3. Check permissions on backup directories:

```bash
ls -la /opt/n8n-data/n8n-backup
ls -la /opt/n8n-data/postgres-backup
```

4. Run backup script with debug output:

```bash
sudo DEBUG=true /opt/n8n-data/backup.sh
```

### Restore Script Fails

**Symptoms:**

- Restore script exits with error
- n8n data not restored

**Solutions:**

1. Verify backup files exist:

```bash
ls -la /opt/n8n-data/n8n-backup
ls -la /opt/n8n-data/postgres-backup
```

2. Check backup ID format (should be YYYYMMDD_HHMMSS):

```bash
sudo /opt/n8n-data/restore.sh --backup-id 20230101_120000
```

3. Stop n8n before restoring:

```bash
sudo docker-compose down
sudo /opt/n8n-data/restore.sh --backup-id 20230101_120000
sudo docker-compose up -d
```

## Traefik and HTTPS Issues

### SSL Certificate Not Issued

**Symptoms:**

- Browser shows "Your connection is not private" or similar
- Traefik logs show certificate errors

**Solutions:**

1. Verify your domain points to your server's IP:

```bash
ping your-domain.com
```

2. Check Traefik logs:

```bash
sudo docker logs n8n-traefik
```

3. Make sure ports 80 and 443 are open in your firewall:

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

### Traefik Dashboard Not Accessible

**Symptoms:**

- Cannot access Traefik dashboard at traefik.your-domain.com
- Authentication errors

**Solutions:**

1. Verify Traefik container is running:

```bash
sudo docker ps | grep traefik
```

2. Check Traefik logs:

```bash
sudo docker logs n8n-traefik
```

3. Check the Traefik dashboard credentials in your .env file

## S3 Backup Issues

### AWS Authentication Failures

**Symptoms:**

- S3 backup script fails with AWS authentication errors
- Messages about "InvalidAccessKeyId" or "SignatureDoesNotMatch"

**Solutions:**

1. Verify AWS credentials in .env:

```bash
sudo cat .env
```

2. Test AWS credentials:

```bash
sudo docker run --rm -it --env-file .env amazon/aws-cli s3 ls
```

3. Make sure region is correct in .env:

```bash
# Example for US East (N. Virginia)
AWS_DEFAULT_REGION=us-east-1
```

### S3 Bucket Issues

**Symptoms:**

- Errors about bucket not found or access denied
- Backup script fails when trying to upload to S3

**Solutions:**

1. Verify bucket exists and is accessible:

```bash
sudo docker run --rm -it --env-file .env amazon/aws-cli s3 ls s3://your-bucket-name
```

2. Check bucket permissions:

```bash
sudo docker run --rm -it --env-file .env amazon/aws-cli s3api get-bucket-policy --bucket your-bucket-name
```

3. Try creating the bucket if it doesn't exist:

```bash
sudo docker run --rm -it --env-file .env amazon/aws-cli s3 mb s3://your-bucket-name
```

## Performance Problems

### n8n Running Slowly

**Symptoms:**

- Workflows execute slowly
- Web interface is sluggish

**Solutions:**

1. Check system resources:

```bash
top
free -h
df -h
```

2. Increase container resource limits in docker-compose.yml:

```yaml
deploy:
  resources:
    limits:
      memory: 8G # Increase from 4G
    reservations:
      memory: 2G # Increase from 1G
```

3. Optimize PostgreSQL settings in .env:

```
POSTGRES_MAX_CONNECTIONS=200
POSTGRES_SHARED_BUFFERS=4GB
POSTGRES_EFFECTIVE_CACHE_SIZE=12GB
```

### High Disk Usage

**Symptoms:**

- Disk space warnings
- System running out of space

**Solutions:**

1. Check disk usage:

```bash
df -h
du -sh /opt/n8n-data/*
```

2. Reduce backup retention period in .env:

```
BACKUP_RETENTION_DAYS=3  # Reduce from 7
```

3. Clean up old backups manually:

```bash
# For local backups
find /opt/n8n-data/n8n-backup -name "n8n_*.tar.gz" -mtime +3 -delete
find /opt/n8n-data/postgres-backup -name "db_*.sql" -mtime +3 -delete

# For S3 backups
sudo docker run --rm -it --env-file .env amazon/aws-cli s3 ls s3://your-bucket-name/backups/ --recursive | grep "2023" | awk '{print $4}' | xargs -I {} sudo docker run --rm -it --env-file .env amazon/aws-cli s3 rm s3://your-bucket-name/{}
```

## Checking Logs

### n8n Logs

```bash
# View live logs
sudo docker logs -f n8n

# View last 100 lines
sudo docker logs --tail 100 n8n
```

### PostgreSQL Logs

```bash
sudo docker logs n8n-postgres
```

### Traefik Logs

```bash
sudo docker logs n8n-traefik
```

### Deployment Log

```bash
sudo cat /opt/n8n-data/deployment.log
```

### Backup Logs

```bash
sudo cat /opt/n8n-data/backup.log
```

## Removal Issues

### Removal Script Fails

**Symptoms:**

- Error messages when running the removal script
- Some components not properly removed

**Solutions:**

1. Make sure the script is executable:

```bash
sudo chmod +x ./utils/remove-n8n.sh
```

2. Run with sudo:

```bash
sudo ./utils/remove-n8n.sh
```

3. If volumes or networks can't be removed, stop all containers first:

```bash
sudo docker stop $(docker ps -a | grep 'n8n-' | awk '{print $1}')
```

### Can't Remove Data Directories

**Symptoms:**

- Error messages when trying to remove data directories
- Permission denied errors

**Solutions:**

1. Check ownership of directories:

```bash
ls -la /opt/n8n-data/
```

2. Use sudo to remove directories:

```bash
sudo rm -rf /opt/n8n-data/
```

3. If files are in use, stop all containers first:

```bash
sudo docker-compose down
```

### Accessing Container Shell

For advanced troubleshooting, you can access the shell of a running container:

```bash
# Access n8n container
sudo docker exec -it n8n /bin/sh

# Access PostgreSQL container
sudo docker exec -it n8n-postgres /bin/bash
```

### Checking Database Connectivity

```bash
# Check if n8n can connect to PostgreSQL
sudo docker exec -it n8n curl -v telnet://postgres:5432
```

### Manually Backing Up PostgreSQL

```bash
sudo docker exec -it n8n-postgres pg_dump -U n8n -d n8n > /tmp/manual_backup.sql
```

### Completely Resetting the Deployment

If you want to completely reset your deployment and start fresh:

```bash
# Stop all containers
sudo docker-compose down

# Remove all data
sudo rm -rf /opt/n8n-data/*

# Start fresh
sudo ./setup.sh
```

## 📑 Navigation

[![README](https://img.shields.io/badge/📘-Main%20README-blue)](README.md)
[![Home](https://img.shields.io/badge/📖-Documentation%20Home-blueviolet)](index.md)
[![Quick Reference](https://img.shields.io/badge/🔍-Quick%20Reference-green)](quick-reference.md)
[![Diagrams](https://img.shields.io/badge/📊-Deployment%20Diagrams-orange)](deployment-diagrams.md)
[![Layman's Guide](https://img.shields.io/badge/🧩-Layman's%20Guide-purple)](layman-guide.md)
[![Remove n8n](https://img.shields.io/badge/🗑️-Removal%20Guide-lightgrey)](remove-n8n.md)
