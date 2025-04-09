# n8n Deployment Options

This document provides a visual explanation of the different deployment options available in this repository.

## 📑 Navigation

[![README](https://img.shields.io/badge/📘-Main%20README-blue)](README.md)
[![Home](https://img.shields.io/badge/📖-Documentation%20Home-blueviolet)](index.md)
[![Troubleshooting](https://img.shields.io/badge/🛠️-Troubleshooting-red)](troubleshooting-guide.md)
[![Layman's Guide](https://img.shields.io/badge/🧩-Layman's%20Guide-purple)](layman-guide.md)
[![Quick Reference](https://img.shields.io/badge/🔍-Quick%20Reference-green)](quick-reference.md)

## 1. Local Deployment

The simplest deployment option with all data stored locally.

```
┌─────────────────────────────────────────────┐
│                   Server                     │
│                                             │
│  ┌─────────┐      ┌─────────┐     ┌──────┐  │
│  │  n8n    │◄────►│ Postgres│     │Qdrant│  │
│  └─────────┘      └─────────┘     └──────┘  │
│        │               │             │      │
│        └───────────────┴─────────────┘      │
│                     │                       │
│                     ▼                       │
│            ┌──────────────────┐             │
│            │  Local Storage   │             │
│            └──────────────────┘             │
└─────────────────────────────────────────────┘
```

**Features:**

- HTTP access only (no HTTPS)
- Local backups only
- Simplest to set up
- Good for development and testing

## 2. S3 Backup Deployment

Adds automatic backups to Amazon S3 for better data protection.

```
┌─────────────────────────────────────────────┐
│                   Server                     │
│                                             │
│  ┌─────────┐      ┌─────────┐     ┌──────┐  │
│  │  n8n    │◄────►│ Postgres│     │Qdrant│  │
│  └─────────┘      └─────────┘     └──────┘  │
│        │               │             │      │
│        └───────────────┴─────────────┘      │
│                     │                       │
│                     ▼                       │
│            ┌──────────────────┐             │
│            │  Local Storage   │             │
│            └──────────────────┘             │
│                     │                       │
│                     ▼                       │
│            ┌──────────────────┐             │
│            │ Backup Scheduler │             │
│            └──────────────────┘             │
│                     │                       │
└─────────────────────┼───────────────────────┘
                      │
                      ▼
            ┌──────────────────┐
            │    AWS S3        │
            │    Bucket        │
            └──────────────────┘
```

**Features:**

- HTTP access only (no HTTPS)
- Automatic daily backups to S3
- Better data protection
- Good for staging environments

## 3. HTTPS with Traefik Deployment

Adds HTTPS support with automatic SSL certificate management.

```
┌─────────────────────────────────────────────┐
│                   Server                     │
│                                             │
│  ┌─────────┐                                │
│  │ Traefik │◄───┐                          │
│  └─────────┘    │                          │
│        │        │                          │
│        ▼        │                          │
│  ┌─────────┐    │   ┌─────────┐   ┌──────┐ │
│  │  n8n    │◄───┴──►│ Postgres│   │Qdrant│ │
│  └─────────┘        └─────────┘   └──────┘ │
│        │                │            │     │
│        └────────────────┴────────────┘     │
│                      │                      │
│                      ▼                      │
│             ┌──────────────────┐            │
│             │  Local Storage   │            │
│             └──────────────────┘            │
└─────────────────────────────────────────────┘
```

**Features:**

- HTTPS access with automatic SSL certificates
- Local backups only
- Traefik dashboard for monitoring
- Good for internal production environments

## 4. Production Deployment (HTTPS with S3 Backups)

The complete production-ready solution combining HTTPS support with S3 backups.

```
┌─────────────────────────────────────────────┐
│                   Server                     │
│                                             │
│  ┌─────────┐                                │
│  │ Traefik │◄───┐                          │
│  └─────────┘    │                          │
│        │        │                          │
│        ▼        │                          │
│  ┌─────────┐    │   ┌─────────┐   ┌──────┐ │
│  │  n8n    │◄───┴──►│ Postgres│   │Qdrant│ │
│  └─────────┘        └─────────┘   └──────┘ │
│        │                │            │     │
│        └────────────────┴────────────┘     │
│                      │                      │
│                      ▼                      │
│             ┌──────────────────┐            │
│             │  Local Storage   │            │
│             └──────────────────┘            │
│                      │                      │
│                      ▼                      │
│             ┌──────────────────┐            │
│             │ Backup Scheduler │            │
│             └──────────────────┘            │
│                      │                      │
└──────────────────────┼──────────────────────┘
                       │
                       ▼
             ┌──────────────────┐
             │    AWS S3        │
             │    Bucket        │
             └──────────────────┘
```

**Features:**

- HTTPS access with automatic SSL certificates
- Automatic daily backups to S3
- Traefik dashboard for monitoring
- Complete data protection
- Recommended for public-facing production environments

## Choosing the Right Deployment Option

| Feature                    | Local | S3 Backup | Traefik | Production |
| -------------------------- | ----- | --------- | ------- | ---------- |
| HTTPS Support              | ❌    | ❌        | ✅      | ✅         |
| Automatic SSL Certificates | ❌    | ❌        | ✅      | ✅         |
| S3 Backups                 | ❌    | ✅        | ❌      | ✅         |
| Traefik Dashboard          | ❌    | ❌        | ✅      | ✅         |
| Setup Complexity           | Low   | Medium    | Medium  | High       |
| Resource Requirements      | Low   | Medium    | Medium  | High       |
| Suitable for Production    | ❌    | ⚠️        | ✅      | ✅         |
| Data Protection Level      | Low   | High      | Low     | High       |

**Recommendation:**

- **Development/Testing**: Use Local deployment
- **Internal Tools**: Use S3 Backup or Traefik deployment
- **Public-Facing Production**: Use Production deployment

## 📑 Navigation

[![README](https://img.shields.io/badge/📘-Main%20README-blue)](README.md)
[![Home](https://img.shields.io/badge/📖-Documentation%20Home-blueviolet)](index.md)
[![Troubleshooting](https://img.shields.io/badge/🛠️-Troubleshooting-red)](troubleshooting-guide.md)
[![Layman's Guide](https://img.shields.io/badge/🧩-Layman's%20Guide-purple)](layman-guide.md)
[![Quick Reference](https://img.shields.io/badge/🔍-Quick%20Reference-green)](quick-reference.md)
