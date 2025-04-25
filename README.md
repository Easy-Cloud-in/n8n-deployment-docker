# n8n Docker Deployment

This repository provides a simplified, user-friendly way to deploy n8n using Docker. It supports multiple deployment options through a single unified setup script.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## 📑 Navigation

[![Home](https://img.shields.io/badge/📖-Documentation%20Home-blue)](index.md)
[![Quick Reference](https://img.shields.io/badge/🔍-Quick%20Reference-green)](quick-reference.md)
[![Troubleshooting](https://img.shields.io/badge/🛠️-Troubleshooting-red)](troubleshooting-guide.md)
[![Diagrams](https://img.shields.io/badge/📊-Deployment%20Diagrams-orange)](deployment-diagrams.md)
[![Layman's Guide](https://img.shields.io/badge/🧩-Layman's%20Guide-purple)](layman-guide.md)
[![Remove n8n](https://img.shields.io/badge/🗑️-Removal%20Guide-lightgrey)](remove-n8n.md)

## 📑 Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Deployment Options](#deployment-options)
- [Configuration](#configuration)
- [Backup and Restore](#backup-and-restore)
- [Troubleshooting](#troubleshooting)
- [Removing n8n](#removing-n8n)
- [License](#license)
- [Acknowledgements](#acknowledgements)

## Overview

This deployment solution offers:

- **Simple Setup**: A single script handles all deployment types
- **Multiple Options**: Support for local, S3 backup, HTTPS with Traefik, and Production-ready deployment
- **User-Friendly**: Interactive setup with clear prompts
- **Secure**: Automatic generation of strong credentials
- **Flexible**: Customizable through environment variables
- **Monitoring**: Optional Prometheus and Grafana integration for production deployments

## Prerequisites

Before you begin, ensure you have the following installed on your system:

1. **Docker**: Container management tool
2. **docker-compose**: Tool for defining and running multi-container applications with Docker

To install these prerequisites on most Linux distributions:

```bash
# Update your system
sudo apt-get update
sudo apt-get upgrade -y

# Install Docker
sudo apt-get install -y docker.io

# Install docker-compose
sudo apt-get install -y docker-compose
```

## Quick Start

### Step 1: Clone the Repository

```bash
git clone https://github.com/yourusername/n8n-deployment-docker.git
cd n8n-deployment-docker
chmod +x setup.sh
```

### Step 2: Run the Setup Script

For interactive setup with prompts:

```bash
sudo ./setup.sh
```

This will guide you through the setup process with a user-friendly menu system.

## Deployment Options

### Local Deployment (Simplest)

This option runs n8n with local storage and backups:

```bash
sudo ./setup.sh --type local
```

### S3 Backup Deployment

This option adds automatic backups to Amazon S3:

```bash
sudo ./setup.sh --type s3 --s3-bucket your-bucket-name --aws-key YOUR_KEY --aws-secret YOUR_SECRET
```

### HTTPS with Traefik Deployment

This option adds HTTPS support with automatic SSL certificates:

```bash
sudo ./setup.sh --type traefik --domain n8n.yourdomain.com --email your@email.com
```

### Production Deployment (Recommended for Public Instances)

This option combines HTTPS support with S3 backups for a complete production-ready solution:

```bash
sudo ./setup.sh --type production --domain n8n.yourdomain.com --email your@email.com --s3-bucket your-bucket-name --aws-key YOUR_KEY --aws-secret YOUR_SECRET
```

## Configuration

All configuration is managed through a single `.env` file. An example with all available options is provided in `.env.example`.

**Key Configuration:**

- `BASE_DIR`: Specifies the root directory on the host machine where all persistent data (database, n8n data, backups, logs) will be stored. Defaults to `/opt/n8n-data` if not set.
- `DEPLOYMENT_TYPE`: Determines which services and features are enabled (e.g., `local`, `s3`, `traefik`, `production`).
- Other variables control database credentials, S3 details, Traefik settings, etc.

The setup script will automatically generate secure credentials and create the necessary configuration based on your selected deployment type.

### Manual Configuration

If you want to manually configure the deployment:

1. Copy the example environment file: `cp .env.example .env`
2. Edit the `.env` file, paying close attention to `BASE_DIR` and other settings relevant to your chosen `DEPLOYMENT_TYPE`.
3. Run the setup script with the `--no-interactive` flag: `sudo ./setup.sh --no-interactive`

## Backup and Restore

### Automatic Backups

When using the `s3` or `production` deployment types, the `backup-scheduler` service automatically runs daily (at midnight server time) using the script located at `./s3/backup-s3.sh`. Backups are uploaded to the configured S3 bucket.

- **Local Backups:** While the `backup-scheduler` primarily focuses on S3, temporary backup files might be created within your `${BASE_DIR}` during the process before being uploaded.
- **Retention:** Backup retention within S3 is typically managed by the `backup-s3.sh` script or S3 lifecycle policies (check the script for details).

### Manual Backup (S3/Production Profiles)

To trigger a manual backup when the `backup-scheduler` service is running:

```bash
# Execute the backup script inside the running container
sudo docker exec n8n-backup-scheduler sh -c "${BASE_DIR}/s3/backup-s3.sh"
```

*Note: Ensure the `BASE_DIR` variable is correctly set in your `.env` file, as it's passed into the container.*

### Restoring from Backup

Restoration typically involves retrieving the desired backup archive from S3 and using the `restore-s3.sh` script.

1.  **Download Backup:** Manually download the required backup archive (e.g., `n8n-backup-YYYYMMDD_HHMMSS.tar.gz`) from your S3 bucket to your host machine.
2.  **Run Restore Script:** Execute the restore script, providing the path to the downloaded archive. You might need to run this within a temporary container that has access to Docker and the necessary tools (like `psql`, `tar`, `docker`).

```bash
# Example (conceptual - exact command might vary depending on restore script logic):
# You might need to adapt this or use a dedicated helper container
sudo docker run --rm -it --network n8n-network \
  -v $(pwd)/n8n-backup-YYYYMMDD_HHMMSS.tar.gz:/tmp/backup.tar.gz \
  -v ${BASE_DIR}:${BASE_DIR} \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e POSTGRES_USER=${POSTGRES_USER} \
  -e POSTGRES_PASSWORD=${POSTGRES_PASSWORD} \
  -e POSTGRES_DB=${POSTGRES_DB} \
  --entrypoint sh \
  amazon/aws-cli:2.17.11 \
  ./s3/restore-s3.sh --backup-file /tmp/backup.tar.gz
```

*Consult the `./s3/restore-s3.sh` script for its specific usage and requirements.* The exact restore procedure depends heavily on the script's implementation.

## Troubleshooting

### Common Issues

1. **n8n fails to start**:

   - Check logs: `sudo docker logs n8n`
   - Verify PostgreSQL is running: `sudo docker ps | grep postgres`
   - Ensure environment variables are set correctly in `.env`, especially `BASE_DIR`.

2. **Backup fails**:

   - Check `backup-scheduler` logs: `sudo docker logs n8n-backup-scheduler`
   - Verify S3 credentials, bucket permissions, and region in `.env`.
   - Check available space within the `${BASE_DIR}` on the host if temporary files are large: `df -h ${BASE_DIR}`

3. **Traefik SSL certificate issues**:
   - Ensure your domain (`DOMAIN_NAME` in `.env`) points correctly to the server's public IP address.
   - Check Traefik logs: `sudo docker logs n8n-traefik`

For more detailed troubleshooting information, see the [Troubleshooting Guide](troubleshooting-guide.md).

### Logs

Check the following logs for troubleshooting:

- n8n logs: `sudo docker logs n8n`
- PostgreSQL logs: `sudo docker logs n8n-postgres`
- Qdrant logs: `sudo docker logs n8n-qdrant`
- Backup Scheduler logs: `sudo docker logs n8n-backup-scheduler` (includes cron output)
- Traefik logs: `sudo docker logs n8n-traefik`
- Deployment log: Check within `${BASE_DIR}/deployment.log` (if created by setup script)
- Backup log: Check within `${BASE_DIR}/backup.log` (created by backup script)

## Removing n8n

To remove n8n and all its components, you can use the interactive menu:

```bash
sudo ./utils/remove-n8n.sh
```

This will present you with a menu of options to selectively remove components.

For command-line removal with specific options:

```bash
# Remove everything (with confirmation prompts)
sudo ./utils/remove-n8n.sh --all

# Remove only containers
sudo ./utils/remove-n8n.sh --containers

# Remove containers and images
sudo ./utils/remove-n8n.sh --containers --images

# Force remove everything without confirmations
sudo ./utils/remove-n8n.sh --all --force
```

For more details on removal options, see the [Removal Guide](remove-n8n.md).

## Development

### Pre-commit Hooks

This repository uses pre-commit hooks to ensure code quality and consistency. The hooks perform the following checks:

- **Shell Scripts**: Lints shell scripts using shellcheck (if installed)
- **Markdown Files**: Validates markdown files using markdownlint
- **YAML Files**: Formats YAML files using prettier
- **JSON Files**: Formats JSON files using prettier
- **Commit Messages**: Validates commit messages using commitlint

#### Setup for Development

If you're contributing to this project, make sure you have the pre-commit hooks installed:

1. Ensure you have Node.js and pnpm installed
2. The hooks are automatically installed when you clone the repository and run `pnpm install`

```bash
# Install dependencies (including dev dependencies)
pnpm install
```

#### Commit Message Convention

This project follows the [Conventional Commits](https://www.conventionalcommits.org/) specification. Your commit messages should be structured as follows:

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

Examples:

- `feat: add S3 backup rotation feature`
- `fix: correct environment variable handling in setup script`
- `docs: update deployment instructions`
- `chore: update dependencies`

#### Manual Linting

You can manually run the linters with:

```bash
# Lint markdown files
pnpm run lint:md

# Lint shell scripts (requires shellcheck)
pnpm run lint:sh
```

## License

This project is licensed under the MIT License - see below for details:

```
MIT License

Copyright (c) 2023-2025 Easy-Cloud - https://easy-cloud.in

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Acknowledgements

This project utilizes several open-source tools and technologies:

- [n8n](https://n8n.io/) - Workflow automation platform
- [Docker](https://www.docker.com/) - Container platform
- [PostgreSQL](https://www.postgresql.org/) - Relational database
- [Traefik](https://traefik.io/) - Cloud-native application proxy
- [Qdrant](https://qdrant.tech/) - Vector database for AI features
- [Prometheus](https://prometheus.io/) - Monitoring system
- [Grafana](https://grafana.com/) - Observability platform
- [AWS CLI](https://aws.amazon.com/cli/) - Command line interface for AWS

Special thanks to the n8n team for their excellent workflow automation platform and to all contributors who have helped improve this deployment solution.

## Author

This project is maintained by Sakar SR from Easy-Cloud (https://easy-cloud.in).

## 📑 Navigation

[![Home](https://img.shields.io/badge/📖-Documentation%20Home-blue)](index.md)
[![Quick Reference](https://img.shields.io/badge/🔍-Quick%20Reference-green)](quick-reference.md)
[![Troubleshooting](https://img.shields.io/badge/🛠️-Troubleshooting-red)](troubleshooting-guide.md)
[![Diagrams](https://img.shields.io/badge/📊-Deployment%20Diagrams-orange)](deployment-diagrams.md)
[![Layman's Guide](https://img.shields.io/badge/🧩-Layman's%20Guide-purple)](layman-guide.md)
[![Remove n8n](https://img.shields.io/badge/🗑️-Removal%20Guide-lightgrey)](remove-n8n.md)
