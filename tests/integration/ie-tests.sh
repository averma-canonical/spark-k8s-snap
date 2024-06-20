#!/bin/bash

# Copyright 2024 Canonical Ltd.

# Import reusable utilities
source ./tests/integration/utils/s3-utils.sh
source ./tests/integration/utils/azure-utils.sh


readonly SPARK_IMAGE='ghcr.io/canonical/charmed-spark@sha256:fd458fbbe4b90232ec657c92375da01789396f914865bcb4c0f919bf33c031f4'
S3_BUCKET=test-snap-$(uuidgen)
SERVICE_ACCOUNT=spark
NAMESPACE=tests


setup_tests() {
  sudo snap connect spark-client:dot-kube-config
}

validate_pi_value() {
  pi=$1

  if [ "${pi}" != "3.1" ]; then
      echo "ERROR: Computed Value of pi is $pi, Expected Value: 3.1. Aborting with exit code 1."
      return 1
  fi
  return 0
}

validate_file_length() {
  # validate the length of the test file
  number_of_lines=$1
  l=$(wc -l ./tests/integration/resources/example.txt | cut -d' ' -f1)
  if [ "${number_of_lines}" != "$l" ]; then
      echo "ERROR: Number of lines is $number_of_lines, Expected Value: $l. Aborting with exit code 1."
      exit 1
  fi
}

setup_s3_properties(){
  # Setup S3 related Spark properties in the service account
  spark-client.service-account-registry add-config \
    --username $SERVICE_ACCOUNT --namespace $NAMESPACE \
    --conf spark.hadoop.fs.s3a.aws.credentials.provider=org.apache.hadoop.fs.s3a.SimpleAWSCredentialsProvider \
    --conf spark.hadoop.fs.s3a.connection.ssl.enabled=false \
    --conf spark.hadoop.fs.s3a.path.style.access=true \
    --conf spark.hadoop.fs.s3a.endpoint=$(get_s3_endpoint) \
    --conf spark.hadoop.fs.s3a.access.key=$(get_s3_access_key) \
    --conf spark.hadoop.fs.s3a.secret.key=$(get_s3_secret_key) \
    --conf spark.sql.warehouse.dir=s3a://$S3_BUCKET/warehouse \
    --conf spark.sql.catalog.local.warehouse=s3a://$S3_BUCKET/warehouse \
    --conf spark.hadoop.hive.metastore.warehouse.dir=s3a://$S3_BUCKET/hwarehouse  
}


setup_azure_storage_properties(){
  # Setup Azure Storage related Spark properties in the service account
  # 
  # Arguments:
  # $1: The name of the azure container

  AZURE_CONTAINER=$1

  warehouse_path=$(construct_resource_uri $AZURE_CONTAINER warehouse abfss)
  account_name=$(get_azure_storage_account_name)
  secret_key=$(get_azure_storage_secret_key)

  spark-client.service-account-registry add-config \
    --username $SERVICE_ACCOUNT --namespace $NAMESPACE \
    --conf spark.hadoop.fs.azure.account.key.$account_name.dfs.core.windows.net=$secret_key \
    --conf spark.sql.warehouse.dir=$warehouse_path \
    --conf spark.sql.catalog.local.warehouse=$warehouse_path \
    --conf spark.hadoop.hive.metastore.warehouse.dir=$warehouse_path 
}


run_spark_pi_example() {

  KUBE_CONFIG=/home/${USER}/.kube/config

  K8S_MASTER_URL=k8s://$(kubectl --kubeconfig=${KUBE_CONFIG} config view -o jsonpath="{.clusters[0]['cluster.server']}")
  SPARK_EXAMPLES_JAR_NAME='spark-examples_2.12-3.4.2.jar'

  echo $K8S_MASTER_URL

  PREVIOUS_JOB=$(kubectl --kubeconfig=${KUBE_CONFIG} get pods | grep driver | tail -n 1 | cut -d' ' -f1)

  NAMESPACE=$1
  USERNAME=$2

  # run the sample pi job using spark-submit
  spark-client.spark-submit \
    --username=${USERNAME} \
    --namespace=${NAMESPACE} \
    --log-level "DEBUG" \
    --deploy-mode cluster \
    --conf spark.kubernetes.driver.request.cores=100m \
    --conf spark.kubernetes.executor.request.cores=100m \
    --conf spark.kubernetes.container.image=$SPARK_IMAGE \
    --class org.apache.spark.examples.SparkPi \
    local:///opt/spark/examples/jars/$SPARK_EXAMPLES_JAR_NAME 100

  # kubectl --kubeconfig=${KUBE_CONFIG} get pods
  DRIVER_JOB=$(kubectl --kubeconfig=${KUBE_CONFIG} get pods -n ${NAMESPACE} | grep driver | tail -n 1 | cut -d' ' -f1)

  if [[ "${DRIVER_JOB}" == "${PREVIOUS_JOB}" ]]
  then
    echo "ERROR: Sample job has not run!"
    exit 1
  fi

  echo -e "Inspecting logs for driver job: ${DRIVER_JOB}"
  # kubectl --kubeconfig=${KUBE_CONFIG} logs ${DRIVER_JOB}

  EXECUTOR_JOB=$(kubectl --kubeconfig=${KUBE_CONFIG} get pods -n ${NAMESPACE} | grep exec | tail -n 1 | cut -d' ' -f1)
  echo -e "Inspecting state of executor job: ${EXECUTOR_JOB}"
  # kubectl --kubeconfig=${KUBE_CONFIG} describe pod ${EXECUTOR_JOB}

  # Check job output
  # Sample output
  # "Pi is roughly 3.13956232343"
  pi=$(kubectl --kubeconfig=${KUBE_CONFIG} logs $(kubectl --kubeconfig=${KUBE_CONFIG} get pods -n ${NAMESPACE} | grep driver | tail -n 1 | cut -d' ' -f1)  -n ${NAMESPACE} | grep 'Pi is roughly' | rev | cut -d' ' -f1 | rev | cut -c 1-3)
  echo -e "Spark Pi Job Output: \n ${pi}"

  validate_pi_value $pi
  if [ $? -eq 1 ]; then
    exit 1
  fi
}

test_spark_pi_example() {
  run_spark_pi_example tests spark
}

run_spark_shell() {
  echo "run_spark_shell ${1} ${2}"

  NAMESPACE=$1
  USERNAME=$2

  # Check job output
  # Sample output
  # "Pi is roughly 3.13956232343"
  echo -e "$(cat ./tests/integration/resources/test-spark-shell.scala | spark-client.spark-shell \
      --username=${USERNAME} \
      --conf spark.kubernetes.container.image=$SPARK_IMAGE \
      --namespace ${NAMESPACE})" \
      > spark-shell.out
  pi=$(cat spark-shell.out  | grep "^Pi is roughly" | rev | cut -d' ' -f1 | rev | cut -c 1-3)
  echo -e "Spark-shell Pi Job Output: \n ${pi}"
  rm spark-shell.out
  validate_pi_value $pi
  if [ $? -eq 1 ]; then
    exit 1
  fi
}

test_spark_shell() {
  run_spark_shell tests spark
}


run_pyspark(){
  # Run PySpark with an test script provided.
  # Arguments:
  # $1: The path to the Python script that is to be executed by PySpark
  
  script_path=$1

  cat $script_path

  echo -e "$(cat $script_path | spark-client.pyspark \
      --username=${SERVICE_ACCOUNT} \
      --conf spark.kubernetes.container.image=$SPARK_IMAGE \
      --namespace ${NAMESPACE} --conf spark.executor.instances=2)" \
      > pyspark.out
  l=$(cat pyspark.out  | grep -oP 'Number of lines \K[0-9]+' )
  rm pyspark.out
  validate_file_length $l
  return $?
}


test_pyspark_with_s3(){
  temp_script_file=/tmp/test-pyspark-s3.py
  example_txt_path=s3a://${S3_BUCKET}/example.txt
  sed "s|EXAMPLE_TEXT_FILE|$example_txt_path|g" ./tests/integration/resources/test-pyspark-s3.py > $temp_script_file

  create_s3_bucket $S3_BUCKET
  copy_file_to_s3_bucket $S3_BUCKET ./tests/integration/resources/example.txt

  setup_s3_properties
  run_pyspark $temp_script_file
  retcode=$?

  rm $temp_script_file
  delete_s3_bucket $S3_BUCKET

  if [ $retcode -eq 1 ]; then
    exit 1
  fi

}

test_pyspark_with_azure_abfss(){
  AZURE_CONTAINER=test-snap-$(uuidgen)
  temp_script_file=/tmp/test-pyspark-s3.py
  example_txt_path=$(construct_resource_uri $AZURE_CONTAINER example.txt abfss)
  sed "s|EXAMPLE_TEXT_FILE|$example_txt_path|g" ./tests/integration/resources/test-pyspark-s3.py > $temp_script_file

  create_azure_container $AZURE_CONTAINER
  copy_file_to_azure_container $AZURE_CONTAINER ./tests/integration/resources/example.txt

  setup_azure_storage_properties $AZURE_CONTAINER
  run_pyspark $temp_script_file
  retcode=$?

  rm $temp_script_file
  delete_azure_container $AZURE_CONTAINER

  if [ $retcode -eq 1 ]; then
    exit 1
  fi
}


run_example_job(){
  # Run a given example job with spark-submit.
  #
  # Arguments:
  # $1: The path to the spark job that is to be processed
  # $2: The path to the example.txt file required for this test

  test_job_py_path=$1
  example_txt_path=$2

  KUBE_CONFIG=/home/${USER}/.kube/config
  PREVIOUS_JOB=$(kubectl --kubeconfig=${KUBE_CONFIG} get pods | grep driver | tail -n 1 | cut -d' ' -f1)

  spark-client.spark-submit \
    --username=${SERVICE_ACCOUNT} --namespace=${NAMESPACE} \
    --log-level "DEBUG" \
    --deploy-mode cluster \
    --conf spark.kubernetes.driver.request.cores=100m \
    --conf spark.kubernetes.executor.request.cores=100m \
    --conf spark.kubernetes.container.image=$SPARK_IMAGE \
    --conf spark.executor.instances=2 \
    $test_job_py_path $example_txt_path

  DRIVER_JOB=$(kubectl --kubeconfig=${KUBE_CONFIG} get pods -n ${NAMESPACE} | grep driver | tail -n 1 | cut -d' ' -f1)

  if [[ "${DRIVER_JOB}" == "${PREVIOUS_JOB}" ]]
  then
    echo "ERROR: Sample job has not run!"
    return 1
  fi

  echo -e "Inspecting logs for driver job: ${DRIVER_JOB}"
  DRIVER_LOGS=$(kubectl --kubeconfig=${KUBE_CONFIG} logs ${DRIVER_JOB} -n ${NAMESPACE})

  l=$(echo $DRIVER_LOGS  | grep -oP 'Number of lines \K[0-9]+' ) 

  validate_file_length $l
  return $? 
}

test_example_job_with_azure_abfss() {
  AZURE_CONTAINER=test-snap-$(uuidgen)
  AZURE_STORAGE_ACCOUNT=$(get_azure_storage_account_name)
  AZURE_STORAGE_KEY=$(get_azure_storage_secret_key)

  # First create Azure storage container
  create_azure_container $AZURE_CONTAINER

  # Copy 'example.txt' script to the container
  copy_file_to_azure_container $AZURE_CONTAINER ./tests/integration/resources/example.txt
  copy_file_to_azure_container $AZURE_CONTAINER ./tests/integration/resources/test-job.py

  setup_azure_storage_properties $AZURE_CONTAINER

  example_txt_path=$(construct_resource_uri $AZURE_CONTAINER example.txt abfss)
  test_job_py_path=$(construct_resource_uri $AZURE_CONTAINER test-job.py abfss)

  run_example_job $test_job_py_path $example_txt_path 
  retcode=$?

  delete_azure_container $AZURE_CONTAINER

  if [ $retcode -eq 1 ]; then
    exit 1
  fi
}

test_example_job_with_s3() {

  # First create a S3 Bucket 
  create_s3_bucket $S3_BUCKET

  # Copy 'example.txt' and script to the S3 bucket
  copy_file_to_s3_bucket $S3_BUCKET ./tests/integration/resources/example.txt
  copy_file_to_s3_bucket $S3_BUCKET ./tests/integration/resources/test-job.py

  setup_s3_properties

  example_txt_path=s3a://$S3_BUCKET/example.txt
  test_job_py_path=s3a://$S3_BUCKET/test-job.py
  run_example_job $test_job_py_path $example_txt_path 
  retcode=$?

  delete_s3_bucket $S3_BUCKET

  if [ $retcode -eq 1 ]; then
    exit 1
  fi
}


run_spark_sql() {
  # Run the example SQL script line by line on spark-sql

  echo -e "$(cat ./tests/integration/resources/test-spark-sql.sql | spark-client.spark-sql \
      --username=${SERVICE_ACCOUNT} --namespace ${NAMESPACE} \
      --conf spark.kubernetes.container.image=$SPARK_IMAGE \
      --conf spark.executor.instances=2)" > spark_sql.out 
  cat spark_sql.out
  l=$(cat spark_sql.out | grep "^Inserted Rows:" | rev | cut -d' ' -f1 | rev)
  echo -e "Number of rows inserted: ${l}"
  rm spark_sql.out
  if [ "$l" != "3" ]; then
      echo "ERROR: Number of rows inserted: $l, Expected: 3. Aborting with exit code 1."
      return 1
  fi
  return 0

}


test_spark_sql_with_s3() {
  # Test Spark SQL with S3 as object storage
  create_s3_bucket $S3_BUCKET

  setup_s3_properties
  run_spark_sql
  retcode=$?

  delete_s3_bucket $S3_BUCKET

  if [ $retcode -eq 1 ]; then
    exit 1
  fi
}


test_spark_sql_with_azure_abfss() {
  # Test Spark SQL with Azure Storage as object storage (using abfss protocol)
  AZURE_CONTAINER=test-snap-$(uuidgen)
  create_azure_container $AZURE_CONTAINER

  setup_azure_storage_properties $AZURE_CONTAINER
  run_spark_sql
  retcode=$?

  delete_azure_container $AZURE_CONTAINER

  if [ $retcode -eq 1 ]; then
    exit 1
  fi
}


test_restricted_account() {
  kubectl config set-context spark-context --namespace=tests --cluster=prod --user=spark
  run_spark_pi_example tests spark
}

setup_user() {
  echo "setup_user() ${1} ${2} ${3}"

  USERNAME=$1
  NAMESPACE=$2

  kubectl create namespace ${NAMESPACE}

  if [ "$#" -gt 2 ]
  then
    CONTEXT=$3
    spark-client.service-account-registry create --context ${CONTEXT} --username ${USERNAME} --namespace ${NAMESPACE}
  else
    spark-client.service-account-registry create --username ${USERNAME} --namespace ${NAMESPACE}
  fi

}

setup_user_admin_context() {
  setup_user $SERVICE_ACCOUNT $NAMESPACE
}

setup_user_restricted_context() {
  setup_user spark tests microk8s
}

cleanup_user() {
  EXIT_CODE=$1
  USERNAME=$2
  NAMESPACE=$3

  spark-client.service-account-registry delete --username=${USERNAME} --namespace ${NAMESPACE}

  rm -rf metastore_db/ derby.log

  OUTPUT=$(spark-client.service-account-registry list)

  EXISTS=$(echo -e "$OUTPUT" | grep "$NAMESPACE:$USERNAME" | wc -l)

  if [ "${EXISTS}" -ne "0" ]; then
      exit 2
  fi

  kubectl delete namespace ${NAMESPACE}

  if [ "${EXIT_CODE}" -ne "0" ]; then
      exit 1
  fi
}

cleanup_user_success() {
  echo "cleanup_user_success()......"
  cleanup_user 0 spark tests
}

cleanup_user_failure() {
  echo "cleanup_user_failure()......"
  cleanup_user 1 spark tests
}



setup_tests

(setup_user_admin_context && test_spark_pi_example && cleanup_user_success) || cleanup_user_failure

(setup_user_admin_context && test_spark_shell && cleanup_user_success) || cleanup_user_failure

(setup_user_admin_context && test_spark_sql_with_s3 && cleanup_user_success) || cleanup_user_failure

(setup_user_admin_context && test_spark_sql_with_azure_abfss && cleanup_user_success) || cleanup_user_failure

(setup_user_admin_context && test_pyspark_with_s3 && cleanup_user_success) || cleanup_user_failure

(setup_user_admin_context && test_pyspark_with_azure_abfss && cleanup_user_success) || cleanup_user_failure

(setup_user_admin_context && test_example_job_with_s3 && cleanup_user_success) || cleanup_user_failure

(setup_user_admin_context && test_example_job_with_azure_abfss && cleanup_user_success) || cleanup_user_failure

(setup_user_restricted_context && test_restricted_account && cleanup_user_success) || cleanup_user_failure
