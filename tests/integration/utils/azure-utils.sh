#!/bin/bash

# Copyright 2024 Canonical Ltd.

# This file contains several Bash utility functions related to Azure storage management
# To use them, simply `source` this file in your bash script.

# Early check to see if the two required environment variables are set.
if [[ -z "${AZURE_STORAGE_ACCOUNT}" || -z "${AZURE_STORAGE_KEY}" ]]; then
  echo "Error: AZURE_STORAGE_ACCOUNT and/or AZURE_STORAGE_KEY variable is not set."
  exit 1
fi

# Check if Azure CLI has been installed and the credentials have been configured. If not, exit.
if ! azcli storage container list > /dev/null 2>&1; then
    echo "The Azure CLI and credentials have not been configured properly. Exiting..."
    exit 1
fi


get_azure_storage_account_name(){
  # Print the name of the azure container (from the environment variable).
  echo $AZURE_STORAGE_ACCOUNT
}


get_azure_storage_secret_key(){
  # Print the secret key for the Azure storage account used for test.
  echo $AZURE_STORAGE_KEY
}


create_azure_container(){
  # Create an Azure container with given name
  #
  # Arguments:
  # $1: Name of the container to be created.

  name=$1
  azcli storage container create --fail-on-exist --name $name && echo "Created Azure Storage container '$name'."
}


delete_azure_container(){
  # Delete an existing Azure container with given name
  #
  # Arguments:
  # $1: Name of the container to be deleted.

  name=$1
  azcli storage container delete --name $name
  echo "Deleted Azure Storage container '$name'."
}


copy_file_to_azure_container(){
  # Copy a file from local to Azure Storage container.
  #
  # Arguments:
  # $1: Name of the destination container
  # $2: Path of the local file to be uploaded

  container=$1
  file_path=$2

  # If file path is '/foo/bar/file.ext', the basename is 'file.ext'
  base_name=$(basename "$file_path")

  azcli storage blob upload --container-name $container --file $file_path --name $base_name
  echo "Copied file '${file_path}' to Azure container '${container}'."
}



construct_resource_uri(){
  # Construct the full resource URI for the given absolute path of the resource
  #
  # Arguments:
  # $1: Name of the container where the resource exists
  # $2: Path of the resource relative to the root of the container
  # $3: The connection protocol to be used

  container=$1
  path=$2
  protocol=$3
  account_name=$(get_azure_storage_account_name)

  case "$protocol" in
    "abfs")
      echo "abfs://$container@$account_name.dfs.core.windows.net/$path"
      ;;
    "abfss")
      echo "abfss://$container@$account_name.dfs.core.windows.net/$path"
      ;;
    "wasb")
      echo "wasb://$container@$account_name.blob.core.windows.net/$path"
      ;;
    "wasbs")
      echo "wasbs://$container@$account_name.blob.core.windows.net/$path"
      ;;
    *)
      echo "Unknown protocol specified: $protocol. Exiting..."
      exit 1
      ;;
  esac
}
