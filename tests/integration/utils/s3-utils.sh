#!/bin/bash

# Copyright 2024 Canonical Ltd.

# This file contains several Bash utility functions related to S3 bucket management
# To use them, simply `source` this file in your bash script.


# Check if AWS CLI has been installed and the credentials have been configured. If not, exit.
if ! aws s3 ls > /dev/null 2>&1; then
    echo "The AWS CLI and S3 credentials have not been configured properly. Exiting..."
    exit 1
fi


get_s3_endpoint(){
  # Print the endpoint where the S3 bucket is exposed on.
  kubectl get service minio -n minio-operator -o jsonpath='{.spec.clusterIP}'
}


get_s3_access_key(){
  # Print the S3 Access Key by reading it from K8s secret
  kubectl get secret -n minio-operator microk8s-user-1 -o jsonpath='{.data.CONSOLE_ACCESS_KEY}' | base64 -d
}


get_s3_secret_key(){
  # Print the S3 Secret Key by reading it from K8s secret
  kubectl get secret -n minio-operator microk8s-user-1 -o jsonpath='{.data.CONSOLE_SECRET_KEY}' | base64 -d
}


create_s3_bucket(){
  # Create a S3 bucket with the given name.
  #
  # Arguments:
  # $1: Name of the bucket to be created.

  BUCKET_NAME=$1
  aws s3 mb s3://"$BUCKET_NAME"
  echo "Created S3 bucket ${BUCKET_NAME}."
}


delete_s3_bucket(){
  # Delete a S3 bucket with the given name.
  #
  # Arguments:
  # $1: Name of the bucket to be deleted.

  BUCKET_NAME=$1
  aws s3 rb "s3://$BUCKET_NAME" --force
  echo "Deleted S3 bucket ${BUCKET_NAME}"
}


copy_file_to_s3_bucket(){
  # Copy a file from local to S3 bucket.
  #
  # Arguments:
  # $1: Name of the destination bucket
  # $2: Path of the local file to be uploaded

  BUCKET_NAME=$1
  FILE_PATH=$2

  # If file path is '/foo/bar/file.ext', the basename is 'file.ext'
  BASE_NAME=$(basename "$FILE_PATH")

  # Copy the file to S3 bucket
  aws s3 cp $FILE_PATH s3://"$BUCKET_NAME"/"$BASE_NAME"

  echo "Copied file ${FILE_PATH} to S3 bucket ${BUCKET_NAME}."
}