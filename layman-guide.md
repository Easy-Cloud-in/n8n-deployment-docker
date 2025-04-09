# n8n Deployment Guide for Non-Technical Users

This guide provides simple instructions for deploying n8n using Docker, designed for users with minimal technical experience.

## What is n8n?

n8n is a workflow automation tool that allows you to connect different services and automate tasks without writing code. Think of it as a way to make your apps talk to each other and perform actions automatically.

## What You'll Need

- A server or VPS (Virtual Private Server) running Linux
- Basic knowledge of how to connect to your server using SSH
- Domain name (optional but recommended)

## Deployment Options

This guide offers two deployment methods:

1. **Local Deployment**: Simplest option, stores data on your server
2. **S3 Deployment**: More advanced, stores data in Amazon S3 for better backup capabilities

## Simple Setup Instructions

### Interactive Setup (Recommended for Beginners)

1. Log in to your server
2. Run this command:

   ```
   sudo ./setup.sh
   ```

3. Follow the on-screen prompts to select your deployment type and enter the required information

The interactive setup will guide you through the process with clear explanations at each step.

## After Setup: How to Access n8n

Once the setup is complete, you can access n8n through your web browser:

- If you used a domain name: https://your-domain.com
- If you didn't use a domain: http://your-server-ip:5678

## Basic Maintenance Commands

### Stopping n8n

```
cd ~/n8n-deployment-docker
docker-compose down
```

### Starting n8n

```
cd ~/n8n-deployment-docker
docker-compose up -d
```

### Viewing Logs

```
cd ~/n8n-deployment-docker
docker-compose logs -f
```

## Backup and Restore

### Creating a Backup

For local deployment:

```
cd ~/n8n-deployment-docker
./local/backup.sh
```

For S3 deployment:

```
cd ~/n8n-deployment-docker
./s3/backup-s3.sh
```

### Restoring from Backup

For local deployment:

```
cd ~/n8n-deployment-docker
./local/restore.sh your-backup-file.tar.gz
```

For S3 deployment:

```
cd ~/n8n-deployment-docker
./s3/restore-s3.sh your-backup-file.tar.gz
```

## Troubleshooting

If you encounter issues, please refer to the [troubleshooting guide](troubleshooting-guide.md) for common problems and solutions.

## Getting Help

If you need additional assistance, please:

1. Check the [official n8n documentation](https://docs.n8n.io/)
2. Visit the [n8n community forum](https://community.n8n.io/)
3. Contact your system administrator
