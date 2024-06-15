#!/bin/bash

# Copyright 2024 Canonical Ltd.

# Import reusable utilities
source ./tests/integration/utils/s3-utils.sh
source ./tests/integration/utils/azure-utils.sh


readonly SPARK_IMAGE='ghcr.io/canonical/charmed-spark:3.4-22.04_edge'
readonly S3_BUCKET=test-snap-$(uuidgen)
readonly AZURE_CONTAINER=$S3_BUCKET

setup_tests() {
  sudo snap connect spark-client:dot-kube-config
}

validate_pi_value() {
  pi=$1

  if [ "${pi}" != "3.1" ]; then
      echo "ERROR: Computed Value of pi is $pi, Expected Value: 3.1. Aborting with exit code 1."
      exit 1
  fi
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


run_example_job() {

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

}

test_example_job() {
  run_example_job tests spark
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
}

test_spark_shell() {
  run_spark_shell tests spark
}

run_pyspark() {
  echo "run_pyspark ${1} ${2}"

  NAMESPACE=$1
  USERNAME=$2

  # Check job output
  # Sample output
  # "Pi is roughly 3.13956232343"
  echo -e "$(cat ./tests/integration/resources/test-pyspark.py | spark-client.pyspark \
      --username=${USERNAME} \
      --conf spark.kubernetes.container.image=$SPARK_IMAGE \
      --namespace ${NAMESPACE} --conf spark.executor.instances=2)" \
      > pyspark.out
  cat pyspark.out
  pi=$(cat pyspark.out  | grep "^Pi is roughly" | rev | cut -d' ' -f1 | rev | cut -c 1-3)
  echo -e "Pyspark Pi Job Output: \n ${pi}"
  rm pyspark.out
  validate_pi_value $pi
}

run_pyspark_s3() {
  echo "run_pyspark_s3 ${1} ${2}"

  NAMESPACE=$1
  USERNAME=$2

  ACCESS_KEY="$(get_s3_access_key)"
  SECRET_KEY="$(get_s3_secret_key)"
  S3_ENDPOINT="$(get_s3_endpoint)"

  # First create S3 bucket named 'test'
  create_s3_bucket $S3_BUCKET

  # Copy 'example.txt' script to 'test' bucket
  copy_file_to_s3_bucket $S3_BUCKET ./tests/integration/resources/example.txt

  echo -e "$(cat ./tests/integration/resources/test-pyspark-s3.py | sed sed 's/S3_BUCKET/${S3_BUCKET}/g' | spark-client.pyspark \
      --username=${USERNAME} \
      --conf spark.kubernetes.container.image=$SPARK_IMAGE \
      --conf spark.hadoop.fs.s3a.aws.credentials.provider=org.apache.hadoop.fs.s3a.SimpleAWSCredentialsProvider \
      --conf spark.hadoop.fs.s3a.connection.ssl.enabled=false \
      --conf spark.hadoop.fs.s3a.path.style.access=true \
      --conf spark.hadoop.fs.s3a.endpoint=$S3_ENDPOINT \
      --conf spark.hadoop.fs.s3a.access.key=$ACCESS_KEY \
      --conf spark.hadoop.fs.s3a.secret.key=$SECRET_KEY \
      --namespace ${NAMESPACE} --conf spark.executor.instances=2)" \
      > pyspark.out
  cat pyspark.out
  l=$(cat pyspark.out  | grep "Number of lines" | rev | cut -d' ' -f1 | rev | cut -c 1-3)
  echo -e "Number of lines: \n ${l}"
  rm pyspark.out
  delete_s3_bucket $S3_BUCKET
  validate_file_length $l
}



run_example_job_with_azure_abfss() {
  echo "run_pyspark_abfss ${1} ${2}"

  NAMESPACE=$1
  USERNAME=$2

  AZURE_STORAGE_ACCOUNT=$(get_storage_account)
  AZURE_STORAGE_KEY=$(get_azure_secret_key)

  # First create Azure storage container named 'test'
  create_azure_container $AZURE_CONTAINER

  # Copy 'example.txt' script to 'test' container
  copy_file_to_azure_container $AZURE_CONTAINER ./tests/integration/resources/example.txt
  copy_file_to_azure_container $AZURE_CONTAINER ./tests/integration/resources/test-job.py

  example_txt_path=$(construct_resource_uri $AZURE_CONTAINER example.txt abfss)
  test_job_py_path=$(construct_resource_uri $AZURE_CONTAINER test-job.py abfss)

  KUBE_CONFIG=/home/${USER}/.kube/config
  PREVIOUS_JOB=$(kubectl --kubeconfig=${KUBE_CONFIG} get pods | grep driver | tail -n 1 | cut -d' ' -f1)

  # run the sample pi job using spark-submit
  spark-client.spark-submit \
    --username=${USERNAME} \
    --namespace=${NAMESPACE} \
    --log-level "DEBUG" \
    --deploy-mode cluster \
    --conf spark.kubernetes.driver.request.cores=100m \
    --conf spark.kubernetes.executor.request.cores=100m \
    --conf spark.kubernetes.container.image=$SPARK_IMAGE \
    --conf spark.executor.instances=2 \
    --conf spark.hadoop.fs.azure.account.key.$AZURE_STORAGE_ACCOUNT.dfs.core.windows.net=$AZURE_STORAGE_KEY \
    $test_job_py_path $example_txt_path

  DRIVER_JOB=$(kubectl --kubeconfig=${KUBE_CONFIG} get pods -n ${NAMESPACE} | grep driver | tail -n 1 | cut -d' ' -f1)

  if [[ "${DRIVER_JOB}" == "${PREVIOUS_JOB}" ]]
  then
    echo "ERROR: Sample job has not run!"
    exit 1
  fi

  echo -e "Inspecting logs for driver job: ${DRIVER_JOB}"
  DRIVER_LOGS=$(kubectl --kubeconfig=${KUBE_CONFIG} logs ${DRIVER_JOB} -n ${NAMESPACE})

  l=$(echo $DRIVER_LOGS  | grep -oP 'Number of lines \K[0-9]+' ) #| rev | cut -d' ' -f1 | rev | cut -c 1-3)

  delete_azure_container $AZURE_CONTAINER
  validate_file_length $l
}


run_spark_sql() {
  echo "run_spark_sql ${1} ${2}"

  NAMESPACE=$1
  USERNAME=$2

  ACCESS_KEY="$(get_s3_access_key)"
  SECRET_KEY="$(get_s3_secret_key)"
  S3_ENDPOINT="$(get_s3_endpoint)"

  # First create S3 bucket named 'test'
  create_s3_bucket $S3_BUCKET

  echo -e "$(cat ./tests/integration/resources/test-spark-sql.sql | spark-client.spark-sql \
      --username=${USERNAME} --namespace ${NAMESPACE} \
      --conf spark.kubernetes.container.image=$SPARK_IMAGE \
      --conf spark.hadoop.fs.s3a.aws.credentials.provider=org.apache.hadoop.fs.s3a.SimpleAWSCredentialsProvider \
      --conf spark.hadoop.fs.s3a.connection.ssl.enabled=false \
      --conf spark.hadoop.fs.s3a.path.style.access=true \
      --conf spark.hadoop.fs.s3a.endpoint=$S3_ENDPOINT \
      --conf spark.hadoop.fs.s3a.access.key=$ACCESS_KEY \
      --conf spark.hadoop.fs.s3a.secret.key=$SECRET_KEY \
      --conf spark.sql.catalog.local.warehouse=s3a://$S3_BUCKET/warehouse \
      --conf spark.sql.warehouse.dir=s3a://$S3_BUCKET/warehouse \
      --conf hive.metastore.warehouse.dir=s3a://$S3_BUCKET/hwarehouse \
      --conf spark.executor.instances=2)" > spark_sql.out 
  cat spark_sql.out
  l=$(cat spark_sql.out | grep "^Inserted Rows:" | rev | cut -d' ' -f1 | rev)
  echo -e "Number of rows inserted: ${l}"
  rm spark_sql.out
  delete_s3_bucket $S3_BUCKET
  if [ "$l" != "3" ]; then
      echo "ERROR: Number of rows inserted: $l, Expected: 3. Aborting with exit code 1."
      exit 1
  fi
}

test_pyspark() {
  run_pyspark tests spark
}

test_pyspark_s3() {
  run_pyspark_s3 tests spark
}

test_spark_sql() {
  run_spark_sql tests spark
}

test_example_job_with_azure_abfss(){
  run_example_job_with_azure_abfss tests spark
}

test_restricted_account() {

  kubectl config set-context spark-context --namespace=tests --cluster=prod --user=spark

  run_example_job tests spark
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
  setup_user spark tests
}

setup_user_restricted_context() {
  setup_user spark tests microk8s
}

cleanup_user() {
  EXIT_CODE=$1
  USERNAME=$2
  NAMESPACE=$3

  spark-client.service-account-registry delete --username=${USERNAME} --namespace ${NAMESPACE}

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

(setup_user_admin_context && test_example_job && cleanup_user_success) || cleanup_user_failure

(setup_user_admin_context && test_spark_shell && cleanup_user_success) || cleanup_user_failure

(setup_user_admin_context && test_pyspark && cleanup_user_success) || cleanup_user_failure

(setup_user_admin_context && test_spark_sql && cleanup_user_success) || cleanup_user_failure

(setup_user_admin_context && test_pyspark_s3 && cleanup_user_success) || cleanup_user_failure

(setup_user_admin_context && test_example_job_with_azure_abfss && cleanup_user_success) || cleanup_user_failure

(setup_user_restricted_context && test_restricted_account && cleanup_user_success) || cleanup_user_failure
