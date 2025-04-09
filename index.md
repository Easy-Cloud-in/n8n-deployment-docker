# n8n Deployment Documentation

Welcome to the n8n deployment documentation. This set of guides will help you deploy, configure, and maintain your n8n instance in various environments.

## 📑 Navigation

[![README](https://img.shields.io/badge/📘-Main%20README-blue)](README.md)
[![Quick Reference](https://img.shields.io/badge/🔍-Quick%20Reference-green)](quick-reference.md)
[![Troubleshooting](https://img.shields.io/badge/🛠️-Troubleshooting-red)](troubleshooting-guide.md)
[![Diagrams](https://img.shields.io/badge/📊-Deployment%20Diagrams-orange)](deployment-diagrams.md)
[![Layman's Guide](https://img.shields.io/badge/🧩-Layman's%20Guide-purple)](layman-guide.md)
[![Remove n8n](https://img.shields.io/badge/🗑️-Removal%20Guide-lightgrey)](remove-n8n.md)
[![Improvements](https://img.shields.io/badge/🚀-Deployment%20Improvements-brightgreen)](deployment-improvements-guide.md)
[![Prometheus](https://img.shields.io/badge/📈-Prometheus%20Guide-yellow)](prometheus-explanation.md)

## Getting Started

Choose the guide that best matches your experience level and needs:

### For Beginners

- [**🧩 Layman's Guide**](layman-guide.md) - Step-by-step instructions with detailed explanations for those new to server administration
- [**📊 Visual Deployment Diagrams**](deployment-diagrams.md) - Visual representations of the different deployment architectures

### For Experienced Users

- [**📘 README**](README.md) - Comprehensive overview of all deployment options
- [**🔍 Quick Reference Guide**](quick-reference.md) - Concise commands and steps for rapid deployment

## Deployment Options

This documentation covers several deployment configurations:

1. **Local Deployment with Local Backup**

   - Simplest setup
   - All data and backups stored on the same server
   - Suitable for testing and small-scale deployments

2. **Deployment with S3 Backup**

   - Enhanced data safety with cloud backups
   - Automatic backup to Amazon S3
   - Suitable for production environments

3. **Deployment with Traefik (HTTPS)**

   - Secure access with SSL/TLS encryption
   - Automatic certificate management
   - Professional setup with domain name

4. **Complete Setup (Traefik + S3)**
   - Combines security of HTTPS with reliability of cloud backups
   - Most robust configuration
   - Recommended for business-critical deployments

## Advanced Topics

- [**🚀 Deployment Improvements Guide**](deployment-improvements-guide.md) - Enhance your deployment with additional features
- [**📈 Prometheus Explanation**](prometheus-explanation.md) - Learn about monitoring your n8n instance with Prometheus

## Removal and Cleanup

- [**🗑️ Removal Guide**](remove-n8n.md) - Instructions for safely removing n8n components

## Troubleshooting

- [**🛠️ Troubleshooting Guide**](troubleshooting-guide.md) - Solutions for common issues and problems

## Directory Structure

```
/
├── README.md                  # Main documentation
├── index.md                   # This navigation file
├── layman-guide.md            # Beginner-friendly guide
├── deployment-diagrams.md     # Visual architecture diagrams
├── troubleshooting-guide.md   # Problem-solving guide
├── quick-reference.md         # Command reference
├── remove-n8n.md              # Removal guide
├── deployment-improvements-guide.md # Deployment improvements
├── prometheus-explanation.md  # Prometheus monitoring guide
├── docker-compose.yml         # Main Docker Compose configuration
├── setup.sh                   # Unified setup script
├── local/                     # Local deployment files
│   ├── backup.sh              # Local backup script
│   └── restore.sh             # Restore script
├── s3/                        # S3 backup deployment files
│   ├── backup-s3.sh           # S3 backup script
│   └── restore-s3.sh          # S3 restore script
├── traefik/                   # Traefik HTTPS configuration
│   └── setup-traefik.sh       # Traefik setup script
└── utils/                     # Utility scripts
    ├── common.sh              # Common functions
    ├── cleanup.sh             # Cleanup utilities
    ├── configure-firewall.sh  # Firewall configuration
    ├── generate-secrets.sh    # Security credential generator
    ├── health-check.sh        # Health check script
    ├── remove-n8n.sh          # Removal script
    ├── test-deployment.sh     # Deployment testing
    └── update-version.sh      # Version update utility
```

## Key Concepts

### Containers

This deployment uses Docker containers to isolate and manage the different components:

- **n8n**: The main workflow automation engine
- **PostgreSQL**: Database for storing workflows and credentials
- **Qdrant**: Vector database for AI features
- **Traefik**: Reverse proxy for HTTPS (optional)
- **Backup Scheduler**: Container for S3 backups (optional)

### Data Storage

All persistent data is stored in `/opt/n8n-data/` with subdirectories for each component:

- `/opt/n8n-data/n8n/`: n8n workflows and data
- `/opt/n8n-data/postgres/`: PostgreSQL database files
- `/opt/n8n-data/qdrant/`: Qdrant vector database files
- `/opt/n8n-data/traefik/`: Traefik configuration (if used)

### Backups

Backups are stored in:

- **Local**: `/opt/n8n-data/*-backup/` directories
- **S3**: In the configured S3 bucket under the `backups/` prefix

## Getting Help

If you encounter issues not covered in these guides:

1. Check the logs:

- Deployment log: `/opt/n8n-data/deployment.log`
- Backup log: `/opt/n8n-data/backup.log`
- Container logs: `sudo docker logs n8n`

2. Consult the [Troubleshooting Guide](troubleshooting-guide.md)

3. Visit the official [n8n documentation](https://docs.n8n.io/)

## 📑 Navigation

[![README](https://img.shields.io/badge/📘-Main%20README-blue)](README.md)
[![Quick Reference](https://img.shields.io/badge/🔍-Quick%20Reference-green)](quick-reference.md)
[![Troubleshooting](https://img.shields.io/badge/🛠️-Troubleshooting-red)](troubleshooting-guide.md)
[![Diagrams](https://img.shields.io/badge/📊-Deployment%20Diagrams-orange)](deployment-diagrams.md)
[![Layman's Guide](https://img.shields.io/badge/🧩-Layman's%20Guide-purple)](layman-guide.md)
[![Remove n8n](https://img.shields.io/badge/🗑️-Removal%20Guide-lightgrey)](remove-n8n.md)
[![Improvements](https://img.shields.io/badge/🚀-Deployment%20Improvements-brightgreen)](deployment-improvements-guide.md)
[![Prometheus](https://img.shields.io/badge/📈-Prometheus%20Guide-yellow)](prometheus-explanation.md)
