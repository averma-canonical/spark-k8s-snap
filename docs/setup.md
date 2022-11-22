### Setup Apache Spark for your Kubernetes cluster
We are working with Kubernetes distribution for Spark. So, to be able to work with Kubernetes, we need to do some setup
for Spark jobs.

The spark-client snap comes with a setup utility which would be the starting point for the setup. You can
run the following command to understand it's usage.
```bash
spark-client.setup-spark-k8s --help
```

From the output you will notice that the setup utility supports the following actions.
* ***service-account*** - Set up a service account in Kubernetes for use during Spark job submission
* ***service-account-cleanup*** - Delete a service account and associated resources from Kubernetes
* ***sa-conf-create*** - Create configuration entries associated with the specified service account in Kubernetes. Immutable once created.
* ***sa-conf-get*** - Fetch configuration entries associated with the specified service account from Kubernetes
* ***sa-conf-delete*** - Delete all configuration entries associated with the specified service account from Kubernetes
* ***resources-primary-sa*** - List resources related to 'primary' service account used implicitly for spark-submit

```bash
usage: setup-spark-k8s.py [-h] [--log-level LOG_LEVEL] [--kubeconfig KUBECONFIG] [--context CONTEXT] [--namespace NAMESPACE] [--username USERNAME]
                          {service-account,service-account-cleanup,sa-conf-create,sa-conf-get,sa-conf-delete,resources-primary-sa} ...

positional arguments:
  {service-account,service-account-cleanup,sa-conf-create,sa-conf-get,sa-conf-delete,resources-primary-sa}

optional arguments:
  -h, --help            show this help message and exit
  --log-level LOG_LEVEL
                        Level for logging.
  --kubeconfig KUBECONFIG
                        Kubernetes configuration file
  --context CONTEXT     Context name to use within the provided kubernetes configuration file
  --namespace NAMESPACE
                        Namespace for the service account. Default is 'default'.
  --username USERNAME   Service account username. Default is 'spark'.
```

As you would have noticed, these commands can take following optional parameters.
* ***log-level*** - Log level used by the logging module. Default is 'INFO'.
* ***kubeconfig*** - Kubernetes configuration file. If not provided, ```$HOME/.kube/config``` is used by default
* ***context*** - For multi cluster Kubernetes deployments, Kubernetes configuration file will have multiple context entries. This parameter specifies which context name to pick from the configuration.
* ***namespace*** - Namespace for the service account to be used for the action. Default is 'default'.
* ***username*** - Username for the service account to be used for the action. Default is 'spark'.

#### Enabling Default Kubernetes Config File Access

First of you will have to allow the snap to access default kubeconfig file ```$HOME/.kube/config``` by executing the following command.

```bash
sudo snap connect spark-client:dot-kube-config
```

The spark-client snap is a strictly confined snap. The above command grants the snap permission to read the afore-mentioned
kubeconfig file from default location.

#### Service Account Creation
To submit Spark jobs to Kubernetes, we need a service account in Kubernetes. Service Account belongs to a Kubernetes namespace. 

You might already have a functional Service Account. Or you can use this spark-client snap to create a fresh one in a namespace of choice.

To get help regarding the usage of service account setup command within the snap, you can run the following command.

```bash
spark-client.setup-spark-k8s service-account --help
```

You will notice from the help output that the action takes following optional arguments
* ***primary*** - A marker to indicate the current service account should be made 'primary' for implicit spark-submit job submission purposes.
* ***properties-file*** - File with all configuration properties to be associated with a service account.
* ***conf*** - Values to add to and override the ones in specified properties-file param.

```bash
usage: setup-spark-k8s.py service-account [-h] [--primary] [--properties-file PROPERTIES_FILE] [--conf CONF]

optional arguments:
  -h, --help            show this help message and exit
  --primary             Boolean to mark the service account as primary.
  --properties-file PROPERTIES_FILE
                        File with all configuration properties assignments.
  --conf CONF           Config properties to be added to the service account.
```
Service account is an abstraction for a set of associated kubernetes resources needed to run a Spark job. The user can choose to associate configuration properties 
with the service account that can serve as default while submitting jobs against that service account from any machine within the kubernetes cluster. A typical use 
of this feature would look like this.

```bash
spark-client.setup-spark-k8s --username demouser --namespace demonamespace service-account --properties-file /home/demouser/conf/spark-defaults.conf --conf spark.app.name=demo-spark-app --conf spark.executor.instances=3
```

The above command sets up a service account for user ```demonamespace:demouser``` for Spark job submission using configuration properties coming from the specified 
properties file while overriding the configuration properties ```spark.app.name``` and ```spark.executor.instances```.

For [job submission](/docs/submit.md), this service account along with it's default configuration properties can be used to submit a Spark job. 

For example, assuming the properties file provided has configuration details to access data in S3, one could submit a job like
```bash
spark-client.spark-submit  --username demouser --namespace demonamespace --deploy-mode cluster --conf spark.app.name=demo-spark-s3-app $S3_PATH_FOR_CODE_FILE
```
This would launch the spark job with configuration coming from the service account for user ```demonamespace:demouser``` but the app name would be ```demo-spark-s3-app```. 

**_Note:_** The command described above does not create a kubernetes namespace but needs it to be there. It does however create the requested username in the specified and existing namespace.

During [job submission](/docs/submit.md), if the account is not specified, the account currently marked as ```primary``` is implicitly picked. An account can be marked as ```primary``` during creation.
