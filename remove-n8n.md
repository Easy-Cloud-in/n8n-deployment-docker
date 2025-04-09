# Removing n8n Deployment

This guide explains how to safely remove n8n components from your system using the `remove-n8n.sh` utility script.

## 📑 Navigation

[![README](https://img.shields.io/badge/📘-Main%20README-blue)](README.md)
[![Home](https://img.shields.io/badge/📖-Documentation%20Home-blueviolet)](index.md)
[![Troubleshooting](https://img.shields.io/badge/🛠️-Troubleshooting-red)](troubleshooting-guide.md)
[![Diagrams](https://img.shields.io/badge/📊-Deployment%20Diagrams-orange)](deployment-diagrams.md)
[![Quick Reference](https://img.shields.io/badge/🔍-Quick%20Reference-green)](quick-reference.md)
[![Layman's Guide](https://img.shields.io/badge/🧩-Layman's%20Guide-purple)](layman-guide.md)

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Interactive Mode](#interactive-mode)
- [Command-Line Options](#command-line-options)
- [Examples](#examples)
- [Component Details](#component-details)
- [Safety Measures](#safety-measures)
- [Troubleshooting](#troubleshooting)
- [Recovery](#recovery)

## Overview

The `remove-n8n.sh` script provides a systematic way to remove n8n components, including:

- Containers and images
- Volumes and networks
- Data directories and logs
- Cron jobs and configurations

The script has been designed with safety in mind, providing confirmation prompts for destructive operations and proper error handling.

## Prerequisites

- Root access or sudo privileges
- Active n8n deployment (local, S3, Traefik, or production setup)
- Docker installed (required)
- docker-compose installed (recommended)

## Interactive Mode

The easiest way to use the removal tool is in interactive mode:

```bash
sudo ./utils/remove-n8n.sh
```

This will display a menu with the following options:

1. Remove containers only
2. Remove images only
3. Remove volumes
4. Remove networks
5. Remove logs
6. Remove data directories
7. Remove cron jobs
8. Remove everything (complete cleanup)
9. Help
10. Exit

Each option will provide clear information about what will be removed and ask for confirmation before proceeding with destructive operations.

## Command-Line Options

For automated or scripted removal, you can use command-line options:

```bash
sudo ./utils/remove-n8n.sh [OPTIONS]
```

Available options:

| Option         | Description                                                                      |
| -------------- | -------------------------------------------------------------------------------- |
| `--all`        | Remove everything (containers, images, volumes, networks, data, logs, cron jobs) |
| `--containers` | Remove only containers                                                           |
| `--images`     | Remove n8n related images                                                        |
| `--volumes`    | Remove volumes (requires confirmation)                                           |
| `--networks`   | Remove networks (requires confirmation)                                          |
| `--logs`       | Remove all logs                                                                  |
| `--data`       | Remove data directories (requires confirmation)                                  |
| `--cron`       | Remove n8n related cron jobs                                                     |
| `--force`      | Skip all confirmations                                                           |

## Examples

1. Remove everything (with confirmation prompts):

```bash
sudo ./utils/remove-n8n.sh --all
```

2. Remove specific components:

```bash
sudo ./utils/remove-n8n.sh --containers --images
```

3. Force remove everything without confirmations:

```bash
sudo ./utils/remove-n8n.sh --all --force
```

4. Remove only data directories:

```bash
sudo ./utils/remove-n8n.sh --data
```

5. Remove containers and cron jobs:

```bash
sudo ./utils/remove-n8n.sh --containers --cron
```

## Component Details

The script removes the following components:

### Containers

- n8n main container
- PostgreSQL database
- Qdrant vector database
- Traefik proxy (if installed)
- Backup containers
- Backup scheduler (for S3 or production deployments)

### Data Directories

- `/opt/n8n-data/n8n/`
- `/opt/n8n-data/postgres/`
- `/opt/n8n-data/qdrant/`
- `/opt/n8n-data/n8n-backup/`
- `/opt/n8n-data/postgres-backup/`
- `/opt/n8n-data/qdrant-backup/`
- `/opt/n8n-data/shared/`
- `/opt/n8n-data/traefik/` (if present)

### Networks

- n8n-network
- traefik-network (if present)

### Volumes

- n8n data volumes
- Database volumes
- Backup volumes

### Additional Items

- Log files
- Cron jobs (daily S3 backup job at midnight for S3 and production deployments)
- Environment files

## Safety Measures

The script includes several safety features:

1. Confirmation prompts for destructive operations
2. Separate flags for different components
3. Root privilege check
4. Dependency verification (checks for required commands)
5. Safe directory removal with path validation
6. Error handling and comprehensive logging
7. Directory existence checks before operations

## Troubleshooting

Common issues and solutions:

1. **Permission denied**

   ```bash
   sudo chmod +x ./utils/remove-n8n.sh
   ```

2. **Locked volumes**

   ```bash
   # Stop all related containers first
   sudo docker stop $(docker ps -a | grep 'n8n-' | awk '{print $1}')
   ```

3. **Network in use**

   ```bash
   # Check for containers using the network
   sudo docker network inspect n8n-network
   ```

4. **Missing docker-compose**

   ```bash
   # Install docker-compose
   sudo apt-get install -y docker-compose
   ```

5. **Command not found errors**

   ```bash
   # Ensure the script is run from the project root directory
   cd /path/to/n8n-deployment
   sudo ./utils/remove-n8n.sh --all
   ```

## Recovery

To recover after removal:

1. Restore from backup:

```bash
# For local backup
sudo /opt/n8n-data/restore.sh --backup-id YYYYMMDD_HHMMSS

# For S3 backup
sudo /opt/n8n-data/restore-s3.sh --backup-id YYYYMMDD_HHMMSS
```

2. Fresh installation:

```bash
# Follow the standard installation procedure
sudo ./setup.sh
```

## 📑 Navigation

[![README](https://img.shields.io/badge/📘-Main%20README-blue)](README.md)
[![Home](https://img.shields.io/badge/📖-Documentation%20Home-blueviolet)](index.md)
[![Troubleshooting](https://img.shields.io/badge/🛠️-Troubleshooting-red)](troubleshooting-guide.md)
[![Diagrams](https://img.shields.io/badge/📊-Deployment%20Diagrams-orange)](deployment-diagrams.md)
[![Quick Reference](https://img.shields.io/badge/🔍-Quick%20Reference-green)](quick-reference.md)
[![Layman's Guide](https://img.shields.io/badge/🧩-Layman's%20Guide-purple)](layman-guide.md)
