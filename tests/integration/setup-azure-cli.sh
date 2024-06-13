#!/bin/bash

echo "Installing Azure CLI..."
sudo snap install azcli


# Early check to see if the two required environment variables are set.
if [[ -z "${AZURE_STORAGE_ACCOUNT}" || -z "{$AZURE_STORAGE_KEY}" ]]; then
  echo "Error: AZURE_STORAGE_ACCOUNT and/or AZURE_STORAGE_KEY variable is not set."
  exit 1
fi
echo "The variables AZURE_STORAGE_ACCOUNT and AZURE_STORAGE_KEY are found to be set."


# Test if the credentials are correct by listing containers
echo "Testing Azure Storage credentials..."
if ! azcli storage container list > /dev/null 2>&1; then
  echo "Error: Invalid Azure Storage credentials."
  exit 1
fi

echo "Azure CLI setup successfully."