# Detailed Design: GPG Encryption for Vaultwarden Backup

This document provides a detailed technical design for implementing GPG (GNU Privacy Guard) public key encryption into the `vaultwarden-backup` project, based on the initial high-level design.

## 1. Core Objectives

1.  **End-to-End Encryption**: Encrypt backup archives using a provided GPG public key before uploading them to a remote destination via Rclone.
2.  **Seamless Integration**: Integrate the encryption step into the existing `backup.sh` script, triggered by new environment variables.
3.  **Configuration via Environment**: All GPG settings (public key, recipient, etc.) will be configurable through environment variables for easy deployment.
4.  **Maintain Existing Functionality**: The change should be backward compatible. If GPG variables are not set, the script should perform the backup as it currently does.
5.  **Decryption Support**: Provide a clear process for decrypting the backup files during a restore operation.

## 2. Detailed Implementation Plan

### 2.1. Dockerfile Modifications

The existing `Dockerfile` will be modified to add the `gnupg` package, which provides the necessary GPG command-line tools. This is done by adding `gnupg` to the `apk add` instruction within the `RUN` command.

```dockerfile
# ... (omitted lines)

RUN chmod +x /app/*.sh \
  && mkdir -m 777 /bitwarden \
  && apk add --no-cache 7zip bash curl gnupg mariadb-client postgresql17-client sqlite supercronic s-nail tzdata \
  && apk info --no-cache -Lq mariadb-client | grep -vE '/bin/mariadb$' | grep -vE '/bin/mariadb-dump$' | xargs -I {} rm -f "/{}" \
  && ln -sf "${LOCALTIME_FILE}" /etc/localtime \
# ... (omitted lines)
```

### 2.2. Environment Variable Schema

To control the GPG encryption feature, the following environment variables will be introduced:

| Variable                  | Required | Description                                                                                                                               | Example                               |
| ------------------------- | -------- | ----------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------- |
| `GPG_ENABLE`              | No       | A boolean (`true`/`false`) to enable or disable the GPG encryption feature. If not set or `false`, the script will skip encryption.         | `true`                                |
| `GPG_RECIPIENT`           | Yes      | The email address or key ID of the GPG key recipient. The public key provided must match this recipient.                                  | `user@example.com`                    |
| `GPG_PUBLIC_KEY_BASE64`   | Yes      | The GPG public key, encoded in Base64. This is the recommended way to pass multi-line text as an environment variable.                     | `bXktcHVibGljLWtleQo=`                |
| `GPG_TRUST_LEVEL`         | No       | The level of trust to assign to the imported key. Defaults to `always` to ensure the key can be used without manual verification.           | `ultimate`                            |
| `KEEP_UNENCRYPTED_BACKUP` | No       | If set to `true`, the original unencrypted backup archive will be kept locally after the encrypted version is created. Defaults to `false`. | `false`                               |

**Note on `GPG_PUBLIC_KEY_BASE64`**: Users will be instructed to generate this value using the command: `base64 -w 0 my_key.asc`.

### 2.3. `backup.sh` Script Modifications

The `backup.sh` script will be the primary location for the new logic. The changes will be implemented within a dedicated function, `encrypt_with_gpg`, to keep the code modular.

**Proposed Script Logic:**

```bash
#!/bin/bash
# ... (existing script setup) ...

# Function to handle GPG encryption
encrypt_with_gpg() {
    local source_file="$1"
    local encrypted_file="${source_file}.gpg"

    echo "GPG encryption is enabled. Starting the encryption process."

    # 1. Validate required environment variables
    if [ -z "$GPG_RECIPIENT" ] || [ -z "$GPG_PUBLIC_KEY_BASE64" ]; then
        echo "Error: GPG_RECIPIENT and GPG_PUBLIC_KEY_BASE64 must be set when GPG_ENABLE is true."
        exit 1
    fi

    # 2. Decode and import the public key
    echo "Importing GPG public key..."
    echo "$GPG_PUBLIC_KEY_BASE64" | base64 -d | gpg --batch --import
    if [ $? -ne 0 ]; then
        echo "Error: Failed to import GPG public key."
        exit 1
    fi

    # 3. Encrypt the backup file
    echo "Encrypting backup file: ${source_file}"
    local trust_level="${GPG_TRUST_LEVEL:-always}"
    
    gpg --yes --batch --trust-model "${trust_level}" \
        --recipient "$GPG_RECIPIENT" \
        --output "$encrypted_file" \
        --encrypt "$source_file"

    if [ $? -ne 0 ]; then
        echo "Error: GPG encryption failed."
        exit 1
    fi

    echo "Encryption successful. Encrypted file created at: ${encrypted_file}"

    # 4. Remove the original unencrypted file unless specified otherwise
    if [ "$KEEP_UNENCRYPTED_BACKUP" != "true" ]; then
        echo "Removing unencrypted backup file: ${source_file}"
        rm -f "$source_file"
    fi

    # Return the path of the encrypted file for uploading
    echo "$encrypted_file"
}

# ... (inside the main backup logic) ...

# Original backup file path (e.g., /backup/vaultwarden_20250914_1030.zip) 
BACKUP_FILE_PATH="/path/to/backup.zip" 

# After creating the zip/tar archive, check if GPG is enabled
if [ "$GPG_ENABLE" == "true" ]; then
    # The function returns the new path, which will be used for the Rclone upload
    UPLOAD_FILE_PATH=$(encrypt_with_gpg "$BACKUP_FILE_PATH")
else
    UPLOAD_FILE_PATH="$BACKUP_FILE_PATH"
fi

# The Rclone command will use the UPLOAD_FILE_PATH variable
echo "Uploading ${UPLOAD_FILE_PATH} to remote..."
rclone copy "$UPLOAD_FILE_PATH" "$RCLONE_REMOTE_NAME:backup/"
```

### 2.4. `restore.sh` Decryption Process

The current `restore.sh` script is not designed for interactive use. Modifying it to handle GPG decryption would require adding logic to:
1.  Detect if the backup file has a `.gpg` extension.
2.  Prompt the user to provide their private key and passphrase.

Given the security implications and complexity, the initial implementation will focus on **manual decryption**. The documentation will be updated with clear instructions for the user on how to decrypt the file before running the restore script.

**Manual Decryption Steps for User Documentation:**

1.  **Download the Backup**: Fetch the encrypted backup file (e.g., `backup.zip.gpg`) from your Rclone remote.
2.  **Import Your Private Key**: If you haven't already, import your private GPG key into your local GPG keyring:
    ```bash
    gpg --import /path/to/your_private_key.asc
    ```
3.  **Decrypt the File**: Use the `gpg` command to decrypt the backup file. You will be prompted for your passphrase.
    ```bash
    gpg --decrypt --output backup.zip backup.zip.gpg
    ```
4.  **Run the Restore Script**: Once you have the decrypted `backup.zip` file, you can proceed with the standard restore process using the `restore.sh` script.

## 3. Security Considerations

1.  **Private Key Management**: The user is solely responsible for the security of their GPG private key. This key should **never** be stored in the backup container or committed to source control.
2.  **Public Key Handling**: The `GPG_PUBLIC_KEY_BASE64` variable contains a public key, which is safe to store as an environment variable.
3.  **Unencrypted Backups**: The default behavior will be to delete the local unencrypted backup file (`KEEP_UNENCRYPTED_BACKUP=false`) to prevent sensitive data from lingering on the backup volume.
4.  **Trust Model**: Using `--trust-model always` simplifies the process but bypasses the GPG web of trust. This is an acceptable trade-off in this context, as the user is explicitly providing the key they wish to use.

## 4. Testing and Validation Plan

The testing strategy will be a combination of automated integration tests that fit into the existing test framework and manual end-to-end tests for processes that require user interaction.

### 4.1. Automated Integration Tests

A new test unit will be created at `tests/units/backup-gpg/`. This will contain a `test.sh` script to automate the verification of the core GPG encryption functionality.

**Test Unit: `backup-gpg`**

1.  **Setup**:
    *   The script will first generate a temporary GPG key pair (`test_key.asc` and `test_key_private.asc`).
    *   The public key will be Base64 encoded.
    *   A mock Rclone remote will be set up to capture the output.

2.  **Test Case 1: Successful GPG Encryption**
    *   **Action**: Run the `backup.sh` script with `GPG_ENABLE=true`, a valid `GPG_RECIPIENT`, and the Base64-encoded `GPG_PUBLIC_KEY_BASE64`.
    *   **Assertions**:
        *   Verify that the script output contains "GPG encryption is enabled."
        *   Check that a `.gpg` encrypted file is created in the backup directory.
        *   Confirm that the unencrypted original backup file is deleted.
        *   Verify that the Rclone command was called with the `.gpg` filename.

3.  **Test Case 2: GPG Disabled (Backward Compatibility)**
    *   **Action**: Run `backup.sh` without any `GPG_*` environment variables.
    *   **Assertions**:
        *   Verify that the script does *not* output "GPG encryption is enabled."
        *   Check that a standard, unencrypted backup file is created.
        *   Verify that the Rclone command was called with the unencrypted filename.

4.  **Test Case 3: Missing GPG Configuration**
    *   **Action**: Run `backup.sh` with `GPG_ENABLE=true` but without `GPG_RECIPIENT`.
    *   **Assertions**:
        *   Verify that the script exits with a non-zero status code.
        *   Check that the script's output contains the error message "Error: GPG_RECIPIENT and GPG_PUBLIC_KEY_BASE64 must be set...".

5.  **Test Case 4: Keep Unencrypted Backup**
    *   **Action**: Run `backup.sh` with GPG enabled and `KEEP_UNENCRYPTED_BACKUP=true`.
    *   **Assertions**:
        *   Verify that both the original unencrypted backup and the new `.gpg` file exist in the backup directory.

### 4.2. Manual End-to-End Test

This test covers the full user workflow, including the decryption and restore process, which cannot be easily automated.

1.  **Prerequisites**:
    *   Generate a personal GPG key pair on your local machine.
    *   Have a running Vaultwarden instance and a configured Rclone remote.

2.  **Test Steps**:
    *   **Step 1: Configure and Run Backup**:
        *   Set the `GPG_ENABLE`, `GPG_RECIPIENT`, and `GPG_PUBLIC_KEY_BASE64` environment variables in your `docker-compose.yml`.
        *   Start the `vaultwarden-backup` container.
        *   Manually trigger a backup by executing `docker exec vaultwarden_backup /app/backup.sh`.
    *   **Step 2: Verify Upload**:
        *   Check your Rclone remote destination to confirm that the encrypted backup file (e.g., `backup.zip.gpg`) has been uploaded.
    *   **Step 3: Manual Decryption**:
        *   Download the encrypted backup file from the remote.
        *   On your local machine, run `gpg --decrypt --output backup.zip backup.zip.gpg`.
        *   Enter your passphrase when prompted.
    *   **Step 4: Verify Content**:
        *   Unzip the decrypted `backup.zip`.
        *   Confirm that the contents (e.g., `db.sqlite3`, `config.json`) are present and appear valid.
    *   **Step 5: (Optional) Perform Restore**:
        *   Use the decrypted backup archive to perform a restore operation following the project's standard restore instructions. Verify that the restore is successful.

## 5. Documentation Updates

The `README.md` file will be updated with a new section titled "GPG Encryption" that includes:
*   A high-level overview of the feature.
*   A detailed description of the new environment variables.
*   A complete `docker-compose.yml` example demonstrating how to configure the feature.
*   Step-by-step instructions on how to generate a GPG key pair and encode the public key in Base64.
*   The manual decryption process for restoring a backup.

```
