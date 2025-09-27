#!/bin/bash

TEST_NAME="backup-gpg"
TEST_OUTPUT_DIR="$(pwd)/${OUTPUT_DIR}/${TEST_NAME}"
TEST_EXTRACT_DIR="$(pwd)/${EXTRACT_DIR}/${TEST_NAME}"

PASSWORD="71ad8764-2f69-4c0c-8452-61e08b9f489d"
BACKUP_FILE="${TEST_OUTPUT_DIR}/backup.test.zip"
BACKUP_FILE_GPG="${BACKUP_FILE}.gpg"

# Test GPG configuration
GPG_RECIPIENT="test@example.com"
GPG_PRIVATE_KEY_FILE="${TEST_OUTPUT_DIR}/test_private_key.asc"
GPG_PUBLIC_KEY_FILE="${TEST_OUTPUT_DIR}/test_public_key.asc"

FAILED_NUM=0

color yellow "Starting test case \"${TEST_NAME}\""

function generate_test_gpg_keys() {
    color blue "Creating real test GPG key pair"
    
    # Create a real test public key (generated with GPG)
    cat > "${GPG_PUBLIC_KEY_FILE}" << 'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mDMEaMk0WxYJKwYBBAHaRw8BAQdARlCNZMk5YxjNLyS6dfgroj1wBKXt/+RS58yD
LOnosl20HFRlc3QgVXNlciA8dGVzdEBleGFtcGxlLmNvbT6ImQQTFgoAQRYhBF1P
TWXNJSBFAlUwEdAEGIzefyMRBQJoyTRbAhsDBQkFo5qABQsJCAcCAiICBhUKCQgL
AgQWAgMBAh4HAheAAAoJENAEGIzefyMRN5kA/iSzSOulLFXX0umAkpPCU65OPI3P
VzF6F4e5GQl9lqIhAQCSkVdUqn/hzOWUURmu/LpS6oei52PSxdQTmBllf60oC7g4
BGjJNFsSCisGAQQBl1UBBQEBB0AbER32mz4+XTqSZo8u1mZRjc4fok/jy3nYyK1F
tzywBgMBCAeIfgQYFgoAJhYhBF1PTWXNJSBFAlUwEdAEGIzefyMRBQJoyTRbAhsM
BQkFo5qAAAoJENAEGIzefyMRx/sBANphKcGWohD4LlAbJuwidbFdRGImK0NSS57E
n2FS8c0CAP4jSWVNf/NrCaTDvukLuFBuiTWMUwzO4vVtrVu159edDQ==
=Kbyp
-----END PGP PUBLIC KEY BLOCK-----
EOF
    
    # Create a real test private key (matching the public key above)
    cat > "${GPG_PRIVATE_KEY_FILE}" << 'EOF'
-----BEGIN PGP PRIVATE KEY BLOCK-----

lFgEaMk0WxYJKwYBBAHaRw8BAQdARlCNZMk5YxjNLyS6dfgroj1wBKXt/+RS58yD
LOnosl0AAP90oPRjE+wLa5tgbRxBJbu7jq84D9ft8NoUn6oKZFpB/xC2tBxUZXN0
IFVzZXIgPHRlc3RAZXhhbXBsZS5jb20+iJkEExYKAEEWIQRdT01lzSUgRQJVMBHQ
BBiM3n8jEQUCaMk0WwIbAwUJBaOagAULCQgHAgIiAgYVCgkICwIEFgIDAQIeBwIX
gAAKCRDQBBiM3n8jETeZAP4ks0jrpSxV19LpgJKTwlOuTjyNz1cxeheHuRkJfZai
IQEAkpFXVKp/4czllFEZrvy6UuqHoudj0sXUE5gZZX+tKAucXQRoyTRbEgorBgEE
AZdVAQUBAQdAGxEd9ps+Pl06kmaPLtZmUY3OH6JP48t52MitRbc8sAYDAQgHAAD/
WzssPLBkvA05nVAUqutwfqxcq1uk4OFhSB0hxe2MZSgPvIh+BBgWCgAmFiEEXU9N
Zc0lIEUCVTAR0AQYjN5/IxEFAmjJNFsCGwwFCQWjmoAACgkQ0AQYjN5/IxHH+wEA
2mEpwZaiEPguUBsm7CJ1sV1EYiYrQ1JLnsSfYVLxzQIA/iNJZU1/82sJpMO+6Qu4
UG6JNYxTDM7i9W2tW7Xn150N
=l5dD
-----END PGP PRIVATE KEY BLOCK-----
EOF
    
    # Encode keys to base64 (compatibility with different base64 implementations)
    GPG_PUBLIC_KEY_BASE64=$(base64 < "${GPG_PUBLIC_KEY_FILE}" | tr -d '\n')
    GPG_PRIVATE_KEY_BASE64=$(base64 < "${GPG_PRIVATE_KEY_FILE}" | tr -d '\n')
    
    color green "Test GPG keys created successfully ($(echo ${GPG_PUBLIC_KEY_BASE64} | wc -c) chars)"
}

function prepare() {
    mkdir -p "${TEST_OUTPUT_DIR}" "${TEST_EXTRACT_DIR}"
    generate_test_gpg_keys
    
    # Create a local rclone config for testing
    mkdir -p "${TEST_OUTPUT_DIR}/.config/rclone"
    cat > "${TEST_OUTPUT_DIR}/.config/rclone/rclone.conf" << EOF
[TestBackup]
type = local
EOF
}

function test_case_1_environment_validation() {
    color blue "Test Case 1: Environment Variable Validation"
    
    local test_failed=0
    
    # Test that GPG environment variables are properly handled
    local docker_output
    docker_output=$(docker run --rm \
        --mount "type=bind,source=${DATA_DIR},target=/bitwarden/data" \
        --mount "type=bind,source=${TEST_OUTPUT_DIR},target=${REMOTE_DIR}" \
        --mount "type=bind,source=${TEST_OUTPUT_DIR}/.config,target=/config" \
        -e "RCLONE_REMOTE_NAME=TestBackup" \
        -e "RCLONE_REMOTE_DIR=${REMOTE_DIR}" \
        -e "ZIP_ENABLE=TRUE" \
        -e "ZIP_PASSWORD=${PASSWORD}" \
        -e "BACKUP_FILE_SUFFIX=test" \
        -e "GPG_ENABLE=TRUE" \
        -e "GPG_RECIPIENT=${GPG_RECIPIENT}" \
        -e "GPG_PUBLIC_KEY_BASE64=${GPG_PUBLIC_KEY_BASE64}" \
        -e "GPG_TRUST_LEVEL=always" \
        "${DOCKER_IMAGE}" \
        backup 2>&1)
    echo "$docker_output"
    # Check that GPG settings are displayed correctly
    if echo "$docker_output" | grep -q "GPG_ENABLE: TRUE"; then
        color green "PASS: GPG_ENABLE is correctly set to TRUE"
    else
        color red "FAIL: GPG_ENABLE not displayed correctly"
        ((test_failed++))
    fi
    
    if echo "$docker_output" | grep -q "GPG_RECIPIENT: ${GPG_RECIPIENT}"; then
        color green "PASS: GPG_RECIPIENT is correctly set"
    else
        color red "FAIL: GPG_RECIPIENT not displayed correctly"
        ((test_failed++))
    fi
    
    if echo "$docker_output" | grep -q "GPG_TRUST_LEVEL: always"; then
        color green "PASS: GPG_TRUST_LEVEL is correctly set"
    else
        color red "FAIL: GPG_TRUST_LEVEL not displayed correctly"
        ((test_failed++))
    fi
    
    
    # Check that backup was attempted with GPG (even if it fails due to key issues)
    if echo "$docker_output" | grep -q "GPG encryption is enabled"; then
        color green "PASS: GPG encryption logic was triggered"
    else
        color yellow "WARNING: GPG encryption logic may not have been triggered"
        # This is a warning, not a failure, as the key might be invalid in test environment
    fi
    
    return $test_failed
}

function test_case_2_gpg_disabled() {
    color blue "Test Case 2: GPG Disabled (Backward Compatibility)"
    
    local test_failed=0
    local backup_file_2="${TEST_OUTPUT_DIR}/backup.test2.zip"
    
    # Run backup with GPG disabled (default)
    docker run --rm \
        --mount "type=bind,source=${DATA_DIR},target=/bitwarden/data" \
        --mount "type=bind,source=${TEST_OUTPUT_DIR},target=${REMOTE_DIR}" \
        --mount "type=bind,source=${TEST_OUTPUT_DIR}/.config,target=/config" \
        -e "RCLONE_REMOTE_NAME=TestBackup" \
        -e "RCLONE_REMOTE_DIR=${REMOTE_DIR}" \
        -e "ZIP_ENABLE=TRUE" \
        -e "ZIP_PASSWORD=${PASSWORD}" \
        -e "BACKUP_FILE_SUFFIX=test2" \
        "${DOCKER_IMAGE}" \
        backup
    
    # Check that regular backup file was created
    if [[ ! -f "${backup_file_2}" ]]; then
        color red "FAIL: Regular backup file not found"
        ((test_failed++))
    else
        color green "PASS: Regular backup file created"
    fi
    
    # Check that no .gpg file was created
    if [[ -f "${backup_file_2}.gpg" ]]; then
        color red "FAIL: GPG file should not have been created"
        ((test_failed++))
    else
        color green "PASS: No GPG file created when disabled"
    fi
    
    return $test_failed
}

function test_case_3_missing_configuration() {
    color blue "Test Case 3: Missing GPG Configuration"
    
    local test_failed=0
    
    # Run backup with GPG enabled but missing recipient
    # Capture both exit code and output
    local docker_output
    local exit_code
    docker_output=$(docker run --rm \
        --mount "type=bind,source=${DATA_DIR},target=/bitwarden/data" \
        --mount "type=bind,source=${TEST_OUTPUT_DIR},target=${REMOTE_DIR}" \
        --mount "type=bind,source=${TEST_OUTPUT_DIR}/.config,target=/config" \
        -e "RCLONE_REMOTE_NAME=TestBackup" \
        -e "RCLONE_REMOTE_DIR=${REMOTE_DIR}" \
        -e "ZIP_ENABLE=TRUE" \
        -e "ZIP_PASSWORD=${PASSWORD}" \
        -e "BACKUP_FILE_SUFFIX=test3" \
        -e "GPG_ENABLE=TRUE" \
        -e "GPG_PUBLIC_KEY_BASE64=${GPG_PUBLIC_KEY_BASE64}" \
        "${DOCKER_IMAGE}" \
        backup 2>&1)
    exit_code=$?
    
    # Should exit with non-zero status or contain error message
    if [[ $exit_code -eq 0 ]] && ! echo "$docker_output" | grep -q "Error.*GPG_RECIPIENT"; then
        color red "FAIL: Should have failed with missing GPG_RECIPIENT (exit code: $exit_code)"
        color red "Output: $docker_output"
        ((test_failed++))
    else
        color green "PASS: Correctly failed with missing GPG_RECIPIENT (exit code: $exit_code)"
    fi
    
    return $test_failed
}

function test_case_4_successful_encryption() {
    color blue "Test Case 4: Successful GPG Encryption"
    
    local test_failed=0
    
    # Run backup with GPG enabled and all required settings
    local docker_output
    docker_output=$(docker run --rm \
        --mount "type=bind,source=${DATA_DIR},target=/bitwarden/data" \
        --mount "type=bind,source=${TEST_OUTPUT_DIR},target=${REMOTE_DIR}" \
        --mount "type=bind,source=${TEST_OUTPUT_DIR}/.config,target=/config" \
        -e "RCLONE_REMOTE_NAME=TestBackup" \
        -e "RCLONE_REMOTE_DIR=${REMOTE_DIR}" \
        -e "ZIP_ENABLE=TRUE" \
        -e "ZIP_PASSWORD=${PASSWORD}" \
        -e "BACKUP_FILE_SUFFIX=test4" \
        -e "GPG_ENABLE=TRUE" \
        -e "GPG_RECIPIENT=${GPG_RECIPIENT}" \
        -e "GPG_PUBLIC_KEY_BASE64=${GPG_PUBLIC_KEY_BASE64}" \
        -e "GPG_TRUST_LEVEL=always" \
        "${DOCKER_IMAGE}" \
        backup 2>&1)
    
    # Check that GPG encryption was successful
    if echo "$docker_output" | grep -q "Encryption successful"; then
        color green "PASS: GPG encryption was successful"
    else
        color red "FAIL: GPG encryption did not succeed"
        color red "Docker output:"
        echo "$docker_output"
        ((test_failed++))
    fi
    
    # Check that encrypted backup file was created
    local backup_file_4="${TEST_OUTPUT_DIR}/backup.test4.zip.gpg"
    if [[ -f "${backup_file_4}" ]]; then
        color green "PASS: Encrypted backup file was created"
    else
        color red "FAIL: No encrypted backup file was created"
        color red "Files in ${TEST_OUTPUT_DIR}:"
        ls -la "${TEST_OUTPUT_DIR}" || echo "Directory not found"
        ((test_failed++))
    fi
    
    # Check that original unencrypted file was NOT uploaded (only encrypted file should exist)
    local unencrypted_file="${TEST_OUTPUT_DIR}/backup.test4.zip"
    if [[ ! -f "${unencrypted_file}" ]]; then
        color green "PASS: Unencrypted backup file was not uploaded"
    else
        color red "FAIL: Unencrypted backup file should not exist in upload directory"
        ((test_failed++))
    fi
    
    return $test_failed
}

function test_case_5_sign_and_encrypt_inline() {
    color blue "Test Case 5: Inline Sign + Encrypt"

    local test_failed=0

    # Run backup with GPG signing enabled (inline signature)
    local docker_output
    docker_output=$(docker run --rm \
        --mount "type=bind,source=${DATA_DIR},target=/bitwarden/data" \
        --mount "type=bind,source=${TEST_OUTPUT_DIR},target=${REMOTE_DIR}" \
        --mount "type=bind,source=${TEST_OUTPUT_DIR}/.config,target=/config" \
        -e "RCLONE_REMOTE_NAME=TestBackup" \
        -e "RCLONE_REMOTE_DIR=${REMOTE_DIR}" \
        -e "ZIP_ENABLE=TRUE" \
        -e "ZIP_PASSWORD=${PASSWORD}" \
        -e "BACKUP_FILE_SUFFIX=test5" \
        -e "GPG_ENABLE=TRUE" \
        -e "GPG_RECIPIENT=${GPG_RECIPIENT}" \
        -e "GPG_PUBLIC_KEY_BASE64=${GPG_PUBLIC_KEY_BASE64}" \
        -e "GPG_TRUST_LEVEL=always" \
        -e "GPG_SIGN_ENABLE=TRUE" \
        -e "GPG_SIGNER=${GPG_RECIPIENT}" \
        -e "GPG_SIGNING_PRIVATE_KEY_BASE64=${GPG_PRIVATE_KEY_BASE64}" \
        "${DOCKER_IMAGE}" \
        backup 2>&1)

    # Optional log assertion (message depends on image version); treat as info
    if echo "$docker_output" | grep -q "Signing and encrypting backup file"; then
        color green "PASS: Signing path message observed"
    else
        color yellow "INFO: Signing path message not observed (may be due to image build)"
    fi

    # Check that encrypted backup file was created
    local backup_file_5="${TEST_OUTPUT_DIR}/backup.test5.zip.gpg"
    if [[ -f "${backup_file_5}" ]]; then
        color green "PASS: Encrypted backup file created (inline signed)"
    else
        color red "FAIL: Encrypted backup file not found (inline signed)"
        ((test_failed++))
    fi

    # Verify signature during decryption inside the container
    if [[ -f "${backup_file_5}" ]]; then
        local verify_output
        verify_output=$(docker run --rm \
            --mount "type=bind,source=${TEST_OUTPUT_DIR},target=/work" \
            --entrypoint sh \
            "${DOCKER_IMAGE}" \
            -lc "cd /work && \
                 gpg --batch --import test_public_key.asc && \
                 gpg --batch --import test_private_key.asc && \
                 gpg --batch --yes --pinentry-mode loopback --decrypt backup.test5.zip.gpg > /dev/null" 2>&1)

        echo "$verify_output"
        if echo "$verify_output" | grep -qi "Good signature"; then
            color green "PASS: Decryption verified a good signature"
        else
            color red "FAIL: Signature verification during decrypt did not show 'Good signature'"
            ((test_failed++))
        fi
    fi

    return $test_failed
}

function test_case_6_detached_signature() {
    color blue "Test Case 6: Detached Signature of Ciphertext"

    local test_failed=0

    # Run backup with GPG signing and detached signature enabled
    local docker_output
    docker_output=$(docker run --rm \
        --mount "type=bind,source=${DATA_DIR},target=/bitwarden/data" \
        --mount "type=bind,source=${TEST_OUTPUT_DIR},target=${REMOTE_DIR}" \
        --mount "type=bind,source=${TEST_OUTPUT_DIR}/.config,target=/config" \
        -e "RCLONE_REMOTE_NAME=TestBackup" \
        -e "RCLONE_REMOTE_DIR=${REMOTE_DIR}" \
        -e "ZIP_ENABLE=TRUE" \
        -e "ZIP_PASSWORD=${PASSWORD}" \
        -e "BACKUP_FILE_SUFFIX=test6" \
        -e "GPG_ENABLE=TRUE" \
        -e "GPG_RECIPIENT=${GPG_RECIPIENT}" \
        -e "GPG_PUBLIC_KEY_BASE64=${GPG_PUBLIC_KEY_BASE64}" \
        -e "GPG_TRUST_LEVEL=always" \
        -e "GPG_SIGN_ENABLE=TRUE" \
        -e "GPG_SIGNER=${GPG_RECIPIENT}" \
        -e "GPG_SIGNING_PRIVATE_KEY_BASE64=${GPG_PRIVATE_KEY_BASE64}" \
        -e "GPG_DETACHED_SIGN_ENABLE=TRUE" \
        -e "GPG_SIG_ARMOR=TRUE" \
        "${DOCKER_IMAGE}" \
        backup 2>&1)

    # Check that encrypted backup file and detached signature were created
    local backup_file_6="${TEST_OUTPUT_DIR}/backup.test6.zip.gpg"
    local sig_file_6="${backup_file_6}.sig"

    if [[ -f "${backup_file_6}" ]]; then
        color green "PASS: Encrypted backup file created"
    else
        color red "FAIL: Encrypted backup file not found"
        ((test_failed++))
    fi

    if [[ -f "${sig_file_6}" ]]; then
        color green "PASS: Detached signature file created"
    else
        color red "FAIL: Detached signature file not found"
        ((test_failed++))
    fi

    # Verify detached signature inside the container using the public key
    if [[ -f "${sig_file_6}" && -f "${backup_file_6}" ]]; then
        local verify_output
        verify_output=$(docker run --rm \
            --mount "type=bind,source=${TEST_OUTPUT_DIR},target=/work" \
            --entrypoint sh \
            "${DOCKER_IMAGE}" \
            -lc "cd /work && \
                 gpg --batch --import test_public_key.asc && \
                 gpg --batch --verify backup.test6.zip.gpg.sig backup.test6.zip.gpg" 2>&1)

        echo "$verify_output"
        if echo "$verify_output" | grep -qi "Good signature"; then
            color green "PASS: Detached signature verified successfully"
        else
            color red "FAIL: Detached signature verification failed"
            ((test_failed++))
        fi
    fi

    return $test_failed
}

function test() {
    color blue "Running GPG encryption tests..."
    
    local total_failures=0
    
    # Run all test cases
    test_case_1_environment_validation
    total_failures=$((total_failures + $?))
    
    test_case_2_gpg_disabled
    total_failures=$((total_failures + $?))
    
    test_case_3_missing_configuration
    total_failures=$((total_failures + $?))
    
    test_case_4_successful_encryption
    total_failures=$((total_failures + $?))
    
    test_case_5_sign_and_encrypt_inline
    total_failures=$((total_failures + $?))

    test_case_6_detached_signature
    total_failures=$((total_failures + $?))
    
    FAILED_NUM=$total_failures
}

function cleanup() {
    rm -rf "${TEST_OUTPUT_DIR}" "${TEST_EXTRACT_DIR}"
}

prepare
test
cleanup

test_result "${TEST_NAME}" "${FAILED_NUM}"
