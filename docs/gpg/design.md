# Vaultwarden Backup with GPG Encryption — Design Document

## 1. Project Background

`vaultwarden-backup` is a community open‑source project for backing up data from Vaultwarden (the lightweight Bitwarden server) and uploading it to cloud storage (Google Drive, OneDrive, etc.) via Rclone.

Existing features include:

- Packaging the data directory (zip or tar)
- Upload to an Rclone remote
- Scheduled backups via Cron
- Optional ZIP password protection

Shortcomings / areas for improvement:

- The raw backup is not encrypted before upload (unless a ZIP password is used)
- To improve security, add support for GPG public‑key encryption to achieve end‑to‑end protection and keep backups safe at rest in the cloud

---

## 2. Design Goals

1. Add GPG public‑key encryption to the existing backup flow
2. Support configuring the public key and recipient via environment variables
3. Keep existing Cron‑based scheduling unchanged
4. Preserve compatibility with existing Rclone remotes
5. Keep the design extensible for other encryption methods or signing schemes

---

## 3. Data Flow

```
Vaultwarden data directory (/data)
        │
        ▼
    Package to backup.tar.gz
        │
        ▼
    GPG encrypt -> backup.tar.gz.gpg
        │
        ▼
    Rclone upload -> VaultwardenBackup:backup/
```

- The `/data` directory is mounted from the Vaultwarden container’s volume
- The encrypted backup file is written to the temporary directory `/backup`
- Rclone uploads the `.gpg` file; the original unencrypted backup can be kept or deleted

---

## 4. System Components

| Component                 | Responsibility                                                      |
| ------------------------- | ------------------------------------------------------------------ |
| Vaultwarden container     | Provides the password manager service; data stored in a Docker volume |
| Vaultwarden‑backup image  | Packages, encrypts, and uploads backups                             |
| backup.sh (entry script)  | Backup logic: packaging, GPG encryption, Rclone upload              |
| Rclone                    | Uploads files to remote storage (Google Drive, OneDrive, etc.)      |
| Cron                      | Invokes backup.sh on schedule                                       |
| GPG                       | Public‑key encryption for transport and at‑rest security            |

---

## 5. Docker Image Design

### 5.1 Base Image

- Use the official `ttionya/vaultwarden-backup:latest`
- Install the `gpg` CLI tools

### 5.2 Add GPG in Dockerfile

```dockerfile
FROM ttionya/vaultwarden-backup:latest

# Install GPG
RUN apt-get update && apt-get install -y gnupg

# The entry script doesn’t need to change; only add encryption in backup.sh
```

### 5.3 Volume Mounts

- Vaultwarden data volume: `vw_data:/data`
- Temporary backup directory: `./backup:/backup`
- Rclone config volume: `vaultwarden-rclone-data:/config/rclone`

---

## 6. Environment Variables

| Variable               | Description                         | Example                 |
| ---------------------- | ----------------------------------- | ----------------------- |
| `DATA_DIR`             | Vaultwarden data directory          | `/data`                 |
| `RCLONE_REMOTE_NAME`   | Rclone remote name                  | `VaultwardenBackup`     |
| `CRON_SCHEDULE`        | Cron schedule expression            | `0 2 * * *`             |
| `GPG_PUBLIC_KEY`       | GPG public key path or content      | `/backup/pubkey.asc`    |
| `GPG_RECIPIENT`        | Recipient email/ID for encryption   | `backup@example.com`    |
| `GPG_PASSPHRASE`       | Optional, to unlock private key     | `******`                |
| `KEEP_LOCAL_BACKUP`    | Keep local unencrypted backup       | `false`                 |

---

## 7. Backup Script Changes

### 7.1 Current Flow

1. Package Vaultwarden data into `backup.tar.gz`
2. Upload to the Rclone remote
3. Optional ZIP password protection

### 7.2 Add GPG Encryption Step

```bash
# Path to the original backup file
BACKUP_FILE="/backup/backup.tar.gz"

# Path to the encrypted file
ENCRYPTED_FILE="${BACKUP_FILE}.gpg"

# GPG encryption
gpg --yes --batch --trust-model always \
    --recipient "$GPG_RECIPIENT" \
    --output "$ENCRYPTED_FILE" \
    --encrypt "$BACKUP_FILE"

# Optionally delete the original unencrypted file
if [ "$KEEP_LOCAL_BACKUP" != "true" ]; then
    rm -f "$BACKUP_FILE"
fi

# Upload the encrypted file
rclone copy "$ENCRYPTED_FILE" "$RCLONE_REMOTE_NAME:backup/"
```

- The script remains compatible with Cron scheduling
- Supports multiple recipients (e.g. `--recipient "user1@example.com" --recipient "user2@example.com"`)

---

## 8. Docker Compose Example

```yaml
version: "3.9"

services:
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    restart: unless-stopped
    volumes:
      - vw_data:/data
    environment:
      - WEBSOCKET_ENABLED=true
    networks:
      - happy-services

  vaultwarden-backup:
    build: ./vaultwarden-backup-gpg
    container_name: vaultwarden_backup
    restart: unless-stopped
    volumes:
      - vw_data:/data
      - vaultwarden-rclone-data:/config/rclone
      - ./backup:/backup
    environment:
      - DATA_DIR=/data
      - RCLONE_REMOTE_NAME=VaultwardenBackup
      - CRON_SCHEDULE="0 2 * * *"
      - GPG_RECIPIENT=backup@example.com
      - GPG_PUBLIC_KEY=/backup/pubkey.asc
      - KEEP_LOCAL_BACKUP=false
    networks:
      - happy-services

networks:
  happy-services:
    external: true

volumes:
  vw_data:
  vaultwarden-rclone-data:
```

---

## 9. Security Considerations

1. **GPG public‑key management**

   - Do not hardcode the public key in the Dockerfile
   - Mount an external public‑key file or use a secrets manager
2. **Rclone configuration**

   - Avoid relying on embedded client_id/client_secret; prefer your own OAuth app
3. **Local backups**

   - Delete the unencrypted file by default to avoid data leakage
4. **Cron logs**

   - Record encryption and upload logs to aid troubleshooting

---

## 10. Testing & Validation

1. Run the backup script manually and confirm a `.gpg` file is generated
2. Verify the backup decrypts with `gpg --decrypt`
3. Upload to the Rclone remote and check file integrity
4. Test the Cron schedule to confirm automated encrypted uploads work

---

## 11. Future Enhancements

1. **Signing backup files** (GPG signatures)
2. **Multi‑cloud sync** (Rclone to multiple remotes)
3. **Incremental backups** (only changed data)
4. **Encrypted log storage** (improved auditability)

