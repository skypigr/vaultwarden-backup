#!/bin/bash

. /app/includes.sh

function clear_dir() {
    rm -rf "${BACKUP_DIR}"
}

function backup_init() {
    NOW="$(date +"${BACKUP_FILE_DATE_FORMAT}")"
    # backup vaultwarden database file (sqlite)
    BACKUP_FILE_DB_SQLITE="${BACKUP_DIR}/db.${NOW}.sqlite3"
    # backup vaultwarden database file (postgresql)
    BACKUP_FILE_DB_POSTGRESQL="${BACKUP_DIR}/db.${NOW}.dump"
    # backup vaultwarden database file (mysql)
    BACKUP_FILE_DB_MYSQL="${BACKUP_DIR}/db.${NOW}.sql"
    # backup vaultwarden config file
    BACKUP_FILE_CONFIG="${BACKUP_DIR}/config.${NOW}.json"
    # backup vaultwarden rsakey files
    BACKUP_FILE_RSAKEY="${BACKUP_DIR}/rsakey.${NOW}.tar"
    # backup vaultwarden attachments directory
    BACKUP_FILE_ATTACHMENTS="${BACKUP_DIR}/attachments.${NOW}.tar"
    # backup vaultwarden sends directory
    BACKUP_FILE_SENDS="${BACKUP_DIR}/sends.${NOW}.tar"
    # backup zip file
    BACKUP_FILE_ZIP="${BACKUP_DIR}/backup.${NOW}.${ZIP_TYPE}"
}

function backup_db_sqlite() {
    color blue "backup vaultwarden sqlite database"

    if [[ -f "${DATA_DB}" ]]; then
        sqlite3 "${DATA_DB}" ".backup '${BACKUP_FILE_DB_SQLITE}'"
    else
        color yellow "not found vaultwarden sqlite database, skipping"
    fi
}

function backup_db_postgresql() {
    color blue "backup vaultwarden postgresql database"

    pg_dump -Fc -h "${PG_HOST}" -p "${PG_PORT}" -d "${PG_DBNAME}" -U "${PG_USERNAME}" -f "${BACKUP_FILE_DB_POSTGRESQL}"
    if [[ $? != 0 ]]; then
        color red "backup vaultwarden postgresql database failed"

        send_notification "failure" "Backup failed at $(date +"%Y-%m-%d %H:%M:%S %Z"). Reason: Backup postgresql database failed."

        exit 1
    fi
}

function backup_db_mysql() {
    color blue "backup vaultwarden mysql database"

    local EXTRA_OPTIONS=()
    if [[ -n "${MYSQL_SSL}" ]]; then
        EXTRA_OPTIONS+=("--ssl=\"${MYSQL_SSL}\"")
    fi
    if [[ -n "${MYSQL_SSL_VERIFY_SERVER_CERT}" ]]; then
        EXTRA_OPTIONS+=("--ssl-verify-server-cert=\"${MYSQL_SSL_VERIFY_SERVER_CERT}\"")
    fi
    if [[ -n "${MYSQL_SSL_CA}" ]]; then
        EXTRA_OPTIONS+=("--ssl-ca=\"${MYSQL_SSL_CA}\"")
    fi
    if [[ -n "${MYSQL_SSL_CERT}" ]]; then
        EXTRA_OPTIONS+=("--ssl-cert=\"${MYSQL_SSL_CERT}\"")
    fi
    if [[ -n "${MYSQL_SSL_KEY}" ]]; then
        EXTRA_OPTIONS+=("--ssl-key=\"${MYSQL_SSL_KEY}\"")
    fi

    eval "mariadb-dump -h \"${MYSQL_HOST}\" -P \"${MYSQL_PORT}\" -u \"${MYSQL_USERNAME}\" -p\"${MYSQL_PASSWORD}\" ${EXTRA_OPTIONS[@]} \"${MYSQL_DATABASE}\" > \"${BACKUP_FILE_DB_MYSQL}\""
    if [[ $? != 0 ]]; then
        color red "backup vaultwarden mysql database failed"

        send_notification "failure" "Backup failed at $(date +"%Y-%m-%d %H:%M:%S %Z"). Reason: Backup mysql database failed."

        exit 1
    fi
}

function backup_config() {
    color blue "backup vaultwarden config"

    if [[ -f "${DATA_CONFIG}" ]]; then
        cp -f "${DATA_CONFIG}" "${BACKUP_FILE_CONFIG}"
    else
        color yellow "not found vaultwarden config, skipping"
    fi
}

function backup_rsakey() {
    color blue "backup vaultwarden rsakey"

    local FIND_RSAKEY=$(find "${DATA_RSAKEY_DIRNAME}" -name "${DATA_RSAKEY_BASENAME}*" | xargs -I {} basename {})
    local FIND_RSAKEY_COUNT=$(echo "${FIND_RSAKEY}" | wc -l)

    if [[ "${FIND_RSAKEY_COUNT}" -gt 0 ]]; then
        echo "${FIND_RSAKEY}" | tar -c -C "${DATA_RSAKEY_DIRNAME}" -f "${BACKUP_FILE_RSAKEY}" -T -

        color blue "display rsakey tar file list"

        tar -tf "${BACKUP_FILE_RSAKEY}"
    else
        color yellow "not found vaultwarden rsakey, skipping"
    fi
}

function backup_attachments() {
    color blue "backup vaultwarden attachments"

    if [[ -d "${DATA_ATTACHMENTS}" ]]; then
        tar -c -C "${DATA_ATTACHMENTS_DIRNAME}" -f "${BACKUP_FILE_ATTACHMENTS}" "${DATA_ATTACHMENTS_BASENAME}"

        color blue "display attachments tar file list"

        tar -tf "${BACKUP_FILE_ATTACHMENTS}"
    else
        color yellow "not found vaultwarden attachments directory, skipping"
    fi
}

function backup_sends() {
    color blue "backup vaultwarden sends"

    if [[ -d "${DATA_SENDS}" ]]; then
        tar -c -C "${DATA_SENDS_DIRNAME}" -f "${BACKUP_FILE_SENDS}" "${DATA_SENDS_BASENAME}"

        color blue "display sends tar file list"

        tar -tf "${BACKUP_FILE_SENDS}"
    else
        color yellow "not found vaultwarden sends directory, skipping"
    fi
}

function backup() {
    mkdir -p "${BACKUP_DIR}"

    case "${DB_TYPE}" in
        SQLITE)     backup_db_sqlite ;;
        POSTGRESQL) backup_db_postgresql ;;
        MYSQL)      backup_db_mysql ;;
    esac

    backup_config
    backup_rsakey
    backup_attachments
    backup_sends

    ls -lah "${BACKUP_DIR}"
}

function encrypt_with_gpg() {
    local source_file="$1"
    local encrypted_file="${source_file}.gpg"

    color blue "GPG encryption is enabled. Starting the encryption process"

    # Setup ephemeral GNUPG home for this operation
    local gpg_tmp_home
    gpg_tmp_home=$(mktemp -d 2>/dev/null)
    if [[ -z "${gpg_tmp_home}" || ! -d "${gpg_tmp_home}" ]]; then
        color red "Error: Unable to create temporary GNUPG home directory"

        send_notification "failure" "Backup failed at $(date +"%Y-%m-%d %H:%M:%S %Z"). Reason: Failed to init GPG environment."

        exit 1
    fi
    chmod 700 "${gpg_tmp_home}"
    echo "allow-loopback-pinentry" > "${gpg_tmp_home}/gpg-agent.conf"
    export GNUPGHOME="${gpg_tmp_home}"
    # Ensure cleanup on exit/failure; expand variable now to keep the path
    trap "rm -rf '${gpg_tmp_home}'" EXIT

    # Validate required environment variables
    if [[ -z "${GPG_RECIPIENT}" || -z "${GPG_PUBLIC_KEY_BASE64}" ]]; then
        color red "Error: GPG_RECIPIENT and GPG_PUBLIC_KEY_BASE64 must be set when GPG_ENABLE is true"

        send_notification "failure" "Backup failed at $(date +"%Y-%m-%d %H:%M:%S %Z"). Reason: GPG encryption failed - missing required variables."

        exit 1
    fi

    # Decode and import the public key
    color blue "Importing GPG public key"
    echo "${GPG_PUBLIC_KEY_BASE64}" | base64 -d | gpg --batch --pinentry-mode loopback --import
    if [[ $? -ne 0 ]]; then
        color red "Error: Failed to import GPG public key"

        send_notification "failure" "Backup failed at $(date +"%Y-%m-%d %H:%M:%S %Z"). Reason: GPG key import failed."

        exit 1
    fi

    # Encrypt the backup file
    color blue "Encrypting backup file: ${source_file}"
    gpg --yes --batch --trust-model "${GPG_TRUST_LEVEL}" --pinentry-mode loopback \
        --recipient "${GPG_RECIPIENT}" \
        --output "${encrypted_file}" \
        --encrypt "${source_file}"

    if [[ $? -ne 0 ]]; then
        color red "Error: GPG encryption failed"

        send_notification "failure" "Backup failed at $(date +"%Y-%m-%d %H:%M:%S %Z"). Reason: GPG encryption failed."

        exit 1
    fi

    color green "Encryption successful. Encrypted file created at: ${encrypted_file}"

    # Remove the original unencrypted file and update UPLOAD_FILE to encrypted version
    color blue "Removing unencrypted backup file: ${source_file}"
    rm -f "${source_file}"
    
    # Update UPLOAD_FILE to point to the encrypted file
    UPLOAD_FILE="${encrypted_file}"

    # Cleanup ephemeral GNUPGHOME
    rm -rf "${gpg_tmp_home}" 2>/dev/null || true
    trap - EXIT
    unset GNUPGHOME
}

function backup_package() {
    if [[ "${ZIP_ENABLE}" == "TRUE" ]]; then
        color blue "package backup file"

        UPLOAD_FILE="${BACKUP_FILE_ZIP}"

        if [[ "${ZIP_TYPE}" == "zip" ]]; then
            7z a -tzip -mx=9 -p"${ZIP_PASSWORD}" "${BACKUP_FILE_ZIP}" "${BACKUP_DIR}"/*
        else
            7z a -t7z -m0=lzma2 -mx=9 -mfb=64 -md=32m -ms=on -mhe=on -p"${ZIP_PASSWORD}" "${BACKUP_FILE_ZIP}" "${BACKUP_DIR}"/*
        fi

        ls -lah "${BACKUP_DIR}"

        color blue "display backup ${ZIP_TYPE} file list"

        7z l -p"${ZIP_PASSWORD}" "${BACKUP_FILE_ZIP}"

        # Apply GPG encryption if enabled
        if [[ "${GPG_ENABLE}" == "TRUE" ]]; then
            encrypt_with_gpg "${UPLOAD_FILE}"
            # UPLOAD_FILE will be updated by encrypt_with_gpg if successful
        fi
    else
        color yellow "skip package backup files"

        UPLOAD_FILE="${BACKUP_DIR}"
    fi
}

function upload() {
    # upload file not exist
    if [[ ! -e "${UPLOAD_FILE}" ]]; then
        color red "upload file not found: ${UPLOAD_FILE}"

        send_notification "failure" "File upload failed at $(date +"%Y-%m-%d %H:%M:%S %Z"). Reason: Upload file not found."

        exit 1
    fi

    # upload
    local HAS_ERROR="FALSE"

    for RCLONE_REMOTE_X in "${RCLONE_REMOTE_LIST[@]}"
    do
        color blue "upload backup file to storage system $(color yellow "[${RCLONE_REMOTE_X}]")"

        rclone ${RCLONE_GLOBAL_FLAG} copy "${UPLOAD_FILE}" "${RCLONE_REMOTE_X}"
        if [[ $? != 0 ]]; then
            color red "upload failed"

            HAS_ERROR="TRUE"
        fi
    done

    if [[ "${HAS_ERROR}" == "TRUE" ]]; then
        send_notification "failure" "File upload failed at $(date +"%Y-%m-%d %H:%M:%S %Z")."

        exit 1
    fi
}

function clear_history() {
    if [[ "${BACKUP_KEEP_DAYS}" -gt 0 ]]; then
        for RCLONE_REMOTE_X in "${RCLONE_REMOTE_LIST[@]}"
        do
            color blue "delete ${BACKUP_KEEP_DAYS} days ago backup files $(color yellow "[${RCLONE_REMOTE_X}]")"

            mapfile -t RCLONE_DELETE_LIST < <(rclone ${RCLONE_GLOBAL_FLAG} lsf "${RCLONE_REMOTE_X}" --min-age "${BACKUP_KEEP_DAYS}d")

            for RCLONE_DELETE_FILE in "${RCLONE_DELETE_LIST[@]}"
            do
                color yellow "deleting \"${RCLONE_DELETE_FILE}\""

                rclone ${RCLONE_GLOBAL_FLAG} delete "${RCLONE_REMOTE_X}/${RCLONE_DELETE_FILE}"
                if [[ $? != 0 ]]; then
                    color red "delete \"${RCLONE_DELETE_FILE}\" failed"
                fi
            done
        done
    fi
}

color blue "running the backup program at $(date +"%Y-%m-%d %H:%M:%S %Z")"

init_env

send_notification "start" "Start backup at $(date +"%Y-%m-%d %H:%M:%S %Z")"

check_rclone_connection any

clear_dir
backup_init
backup
backup_package
upload
clear_dir
clear_history

send_notification "success" "The file was successfully uploaded at $(date +"%Y-%m-%d %H:%M:%S %Z")."

color none ""
