#!/bin/bash

# Test script for GPG feature in Dockerfile
# This test builds the Docker image and verifies that the `gnupg` package is installed.

set -e # Exit immediately if a command exits with a non-zero status.

# Get the directory of the currently executing script
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${DIR}/../../../" && pwd)"
TEST_IMAGE_NAME="vaultwarden-backup-gpg-test:latest"

echo "---"
echo "Building Docker image to test GPG installation..."
echo "---"

# Build the Docker image from the project root
docker build -t "${TEST_IMAGE_NAME}" "${ROOT_DIR}"

echo "---"
echo "Verifying 'gpg' command exists in the new image..."
echo "---"

# Run a command in a temporary container to check for gpg
# We override the entrypoint to prevent the default script from running,
# as it requires a mounted volume that isn't present in this test.
docker run --rm --entrypoint="" "${TEST_IMAGE_NAME}" gpg --version

echo "---"
echo "GPG installation test PASSED."
echo "---"

# Clean up the test image
echo "Cleaning up test image..."
docker rmi "${TEST_IMAGE_NAME}"

echo "Cleanup complete."
