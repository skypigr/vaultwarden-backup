#!/bin/bash

TEST_NAME="backup-local-copy"
TEST_OUTPUT_DIR="$(pwd)/${OUTPUT_DIR}/${TEST_NAME}"
TEST_LOCAL_DIR="$(pwd)/${TEMP_DIR}/${TEST_NAME}_local"
TEST_EXTRACT_DIR="$(pwd)/${EXTRACT_DIR}/${TEST_NAME}"

PASSWORD="local-copy-password"
BACKUP_FILE="${TEST_OUTPUT_DIR}/backup.test.zip"
LOCAL_BACKUP_FILE="${TEST_LOCAL_DIR}/backup.test.zip"

FAILED_NUM=0

color yellow "Starting test case \"${TEST_NAME}\""

function prepare() {
    mkdir -p "${TEST_OUTPUT_DIR}" "${TEST_LOCAL_DIR}" "${TEST_EXTRACT_DIR}"
}

function start_and_test() {
    # 1. Test zipped backup + local copy
    color blue "Running backup with local copy..."
    docker run --rm \
        --mount "type=bind,source=${TEST_OUTPUT_DIR},target=${REMOTE_DIR}" \
        --mount "type=bind,source=${TEST_LOCAL_DIR},target=/bitwarden/local_backups" \
        -e "RCLONE_REMOTE_DIR=${REMOTE_DIR}" \
        -e "ZIP_PASSWORD=${PASSWORD}" \
        -e "BACKUP_FILE_SUFFIX=test" \
        -e "LOCAL_BACKUP_DIR=/bitwarden/local_backups" \
        "${DOCKER_IMAGE}" \
        backup

    # Verify both Rclone remote and LOCAL_BACKUP_DIR have the file
    if [[ ! -f "${BACKUP_FILE}" ]]; then
        color red "Cloud Rclone backup file not found!"
        ((FAILED_NUM++))
    fi

    if [[ ! -f "${LOCAL_BACKUP_FILE}" ]]; then
        color red "Local copy of backup file not found!"
        ((FAILED_NUM++))
    fi

    # Verify restoring from the local copy works
    docker run --rm \
      --mount "type=bind,source=${TEST_EXTRACT_DIR},target=/bitwarden/data/" \
      --mount "type=bind,source=${TEST_LOCAL_DIR},target=/bitwarden/restore/" \
      "${DOCKER_IMAGE}" \
      restore \
      -f \
      -p "${PASSWORD}" \
      --zip-file "$(basename "${LOCAL_BACKUP_FILE}")"

    check_files_same_in_folders "${DATA_DIR}" "${TEST_EXTRACT_DIR}"
    if [[ $? != 0 ]]; then
        ((FAILED_NUM++))
    fi

    # 2. Test local cleanup retention policy
    color blue "Testing local backup retention cleanup..."
    # Touch a dummy file and backdate its modify time to 3 days ago
    local OLD_FILE="${TEST_LOCAL_DIR}/backup.old.zip"
    touch "${OLD_FILE}"
    
    # Backdate modification time by 3 days
    if [[ "$OSTYPE" == "darwin"* ]]; then
        touch -m -t "$(date -v -3d +"%Y%m%d%H%M")" "${OLD_FILE}"
    else
        touch -m -t "$(date -d "3 days ago" +"%Y%m%d%H%M")" "${OLD_FILE}"
    fi

    # Run backup again with local retention = 2 days
    docker run --rm \
        --mount "type=bind,source=${TEST_OUTPUT_DIR},target=${REMOTE_DIR}" \
        --mount "type=bind,source=${TEST_LOCAL_DIR},target=/bitwarden/local_backups" \
        -e "RCLONE_REMOTE_DIR=${REMOTE_DIR}" \
        -e "ZIP_PASSWORD=${PASSWORD}" \
        -e "BACKUP_FILE_SUFFIX=test2" \
        -e "LOCAL_BACKUP_DIR=/bitwarden/local_backups" \
        -e "LOCAL_BACKUP_KEEP_DAYS=2" \
        "${DOCKER_IMAGE}" \
        backup

    # The OLD_FILE (3 days old) should be deleted, but the new one should remain
    if [[ -f "${OLD_FILE}" ]]; then
        color red "Old local backup file was not cleaned up!"
        ((FAILED_NUM++))
    else
        color green "Old local backup file was successfully cleaned up!"
    fi
}

function cleanup() {
    rm -rf "${TEST_OUTPUT_DIR}" "${TEST_LOCAL_DIR}" "${TEST_EXTRACT_DIR}" 2>/dev/null || sudo -n rm -rf "${TEST_OUTPUT_DIR}" "${TEST_LOCAL_DIR}" "${TEST_EXTRACT_DIR}" 2>/dev/null

    unset TEST_OUTPUT_DIR
    unset TEST_LOCAL_DIR
    unset TEST_EXTRACT_DIR
    unset PASSWORD
    unset BACKUP_FILE
    unset LOCAL_BACKUP_FILE
}

prepare
start_and_test
cleanup

test_result "${TEST_NAME}" "${FAILED_NUM}"
