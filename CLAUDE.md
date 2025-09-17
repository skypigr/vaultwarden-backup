# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Docker-based backup tool for [vaultwarden](https://github.com/dani-garcia/vaultwarden) instances. The tool creates scheduled backups of vaultwarden data (database, config, attachments, RSA keys) and uploads them to remote storage via rclone. The project supports multiple database backends (SQLite, PostgreSQL, MySQL/MariaDB), compression formats (zip/7z), and notification methods (email, webhooks).

## Development Commands

### Testing
```bash
# Run all unit tests
./tests/test.sh

# Run specific test unit
./tests/units/backup-zip-file/test.sh
./tests/units/backup-7z-file/test.sh
./tests/units/backup-unpackage/test.sh
./tests/units/backup-cron/test.sh
./tests/units/env-priority/test.sh
./tests/units/check-rclone-connection-initializing/test.sh
```

### Docker Build and Testing
```bash
# Build test base image
docker buildx bake image-test-base

# Build test image
docker buildx bake image-test

# Build production images (multi-platform)
docker buildx bake image-stable

# Build beta version
docker buildx bake image-beta
```

### Development Setup
```bash
# Start development environment
docker-compose up -d

# Configure rclone for testing
docker run --rm -it \
  --mount type=volume,source=vaultwarden-rclone-data,target=/config/ \
  ttionya/vaultwarden-backup:latest \
  rclone config

# Test mail configuration
docker run --rm -it \
  -e MAIL_SMTP_VARIABLES='<smtp variables>' \
  ttionya/vaultwarden-backup:latest mail <recipient>

# Test ping notifications
docker run --rm -it \
  -e PING_URL='<ping url>' \
  ttionya/vaultwarden-backup:latest ping <test_identifier>
```

## Code Architecture

### Core Scripts (scripts/)
- **entrypoint.sh**: Main entry point handling different modes (backup, restore, rclone, mail/ping tests)
- **backup.sh**: Core backup logic for database, config, attachments, and compression
- **restore.sh**: Restore functionality with support for individual files or compressed archives
- **includes.sh**: Shared functions for notifications, environment handling, and rclone operations

### Key Functions in includes.sh
- `check_rclone_connection()`: Validates rclone configuration and connectivity
- `send_notification()`: Unified notification system for email and webhooks
- `export_env_file()`: Environment variable loading with priority handling
- `color()`: Colored terminal output for logs

### Test Structure (tests/)
- **test.sh**: Main test runner that executes all unit tests
- **units/**: Individual test cases for specific functionality
- **fixtures/**: Test data including sample vaultwarden data structure
- Each test unit follows pattern: setup → execute → validate → cleanup

### Database Support
The backup system supports three database backends:
- **SQLite**: Uses `sqlite3 .backup` command for consistent snapshots
- **PostgreSQL**: Uses `pg_dump -Fc` for compressed custom format dumps
- **MySQL/MariaDB**: Uses `mysqldump` with appropriate flags

### Environment Variable System
Environment variables are loaded with this priority:
1. Direct environment variable
2. File pointed to by `<VAR>_FILE` environment variable
3. `<VAR>_FILE` in `.env` file
4. Direct variable in `.env` file

### Compression and Encryption
- Supports zip and 7z compression formats
- Password protection for compressed archives
- GPG encryption support (current development focus)
- Files can be uploaded individually or as compressed archives

## Current Development

The project is actively implementing GPG encryption functionality on the `encrypt_with_gpg` branch. Key development documents:
- `DETAILED_DESIGN.md`: Technical design for GPG implementation
- `EXECUTION_PLAN.md`: Phased implementation plan
- `WORK_STATUS.md`: Current development status tracking

## Testing Guidelines

- All new features must include corresponding unit tests in `tests/units/`
- Tests should follow the existing pattern of using Docker containers for isolation
- Use the provided test utility functions in `tests/test.sh` for consistent output
- Validate file integrity using the `check_files_same_in_folders()` function
- Test both success and failure scenarios

## Common Development Patterns

- Use the `color()` function for consistent log output
- Environment variables should support both direct values and `_FILE` variants for Docker secrets
- All external commands should include proper error handling and user feedback
- Follow the existing backup file naming convention: `<type>.<timestamp>.<extension>`
- Maintain backward compatibility when adding new features