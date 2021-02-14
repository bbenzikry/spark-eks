# spark-on-eks

<!-- markdownlint-disable MD033 -->
<center>
<a href="#">
<img src="https://user-images.githubusercontent.com/1993348/91601148-d0b01b80-e971-11ea-9903-6299b2396499.png" width="100%" height="50%">
</a>

Examples and custom spark images for working with the spark-on-k8s operator on AWS.

Allows using Spark 2 with IRSA and Spark 3 with IRSA and AWS Glue as a metastore.

Note: Spark 3 images also include relevant jars for working with the [S3A commiters](https://hadoop.apache.org/docs/r3.1.1/hadoop-aws/tools/hadoop-aws/committers.html)

If you're looking for the Spark 3 custom distributions, you can find them [here](https://github.com/bbenzikry/spark-glue/releases)

**Note**: Spark 2 images will not be updated, please see the [FAQ](#faq)

---

[![operator](https://img.shields.io/docker/cloud/build/bbenzikry/spark-eks-operator?style=plastic&label=operator)](https://hub.docker.com/r/bbenzikry/spark-eks-operator)
[![spark-eks](https://img.shields.io/docker/cloud/build/bbenzikry/spark-eks?style=plastic&label=spark-eks)](https://hub.docker.com/r/bbenzikry/spark-eks)


</center>

## Prerequisites

- Deploy [spark-on-k8s operator](https://github.com/GoogleCloudPlatform/spark-on-k8s-operator) using the [helm chart](https://github.com/helm/charts/tree/master/incubator/sparkoperator) and the [patched operator](https://github.com/bbenzikry/spark-on-k8s-operator/tree/hive-subpath) image `bbenzikry/spark-eks-operator:latest`

Suggested values for the helm chart can be found in the [flux](./flux/operator.yaml) example.

> Note: Do not create the spark service account automatically as part of chart use.

## using IAM roles for service accounts on EKS

### Creating roles and service account

- Create an AWS role for driver
- Create an AWS role for executors

> [AWS docs on creating policies and roles](https://docs.aws.amazon.com/eks/latest/userguide/create-service-account-iam-policy-and-role.html)

- Add default service account EKS role for executors in your spark job namespace ( optional )

```yaml
# NOTE: Only required when not building spark from source or using a version of spark < 3.1. In 3.1, executor roles will rely on the driver definition. At the moment they execute with the default service account.
apiVersion: v1
kind: ServiceAccount
metadata:
  name: default
  namespace: SPARK_JOB_NAMESPACE
  annotations:
    # can also be the driver role
    eks.amazonaws.com/role-arn: "arn:aws:iam::ACCOUNT_ID:role/executor-role"
```

- Make sure spark service account ( used by driver pods ) is configured to an EKS role as well

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: spark
  namespace: SPARK_JOB_NAMESPACE
  annotations:
    eks.amazonaws.com/role-arn: "arn:aws:iam::ACCOUNT_ID:role/driver-role"
```

### Building a compatible image

- For spark < 3.0.0, see [spark2.Dockerfile](./docker/spark2.Dockerfile)

- For spark 3.0.0+, see [spark3.Dockerfile](./docker/spark3.Dockerfile)

- For pyspark, see [pyspark.Dockerfile](./docker/pyspark.Dockerfile)

### Submit your spark application with IRSA support

#### Select the right implementation for you

> Below are examples for latest versions.
>
> If you want to use pinned versions, all images are tagged by the commit SHA.
>
> You can find a full list of tags [here](https://hub.docker.com/repository/docker/bbenzikry/spark-eks/tags)

```dockerfile
# spark2
FROM bbenzikry/spark-eks:spark2-latest
# spark3
FROM bbenzikry/spark-eks:spark3-latest
# pyspark2
FROM bbenzikry/spark-eks:pyspark2-latest
# pyspark3
FROM bbenzikry/spark-eks:pyspark3-latest
```

#### Submit your SparkApplication spec

```yaml
hadoopConf:
  # IRSA configuration
  "fs.s3a.aws.credentials.provider": "com.amazonaws.auth.WebIdentityTokenCredentialsProvider"
driver:
  .....
  labels:
    .....
  serviceAccount: SERVICE_ACCOUNT_NAME

  # See: https://github.com/kubernetes/kubernetes/issues/82573
  # Note: securityContext has changed in recent versions of the operator to podSecurityContext
  podSecurityContext:
    fsGroup: 65534
```

### Working with AWS Glue as metastore

#### Glue Prerequisites

- Make sure your driver and executor roles have the relevant glue permissions

```json5
{
  /* 
  Example below depicts the IAM policy for accessing db1/table1.
  Modify this as you deem worthy for spark application access.
  */

  Effect: "Allow",
  Action: ["glue:*Database*", "glue:*Table*", "glue:*Partition*"],
  Resource: [
    "arn:aws:glue:us-west-2:123456789012:catalog",
    "arn:aws:glue:us-west-2:123456789012:database/db1",
    "arn:aws:glue:us-west-2:123456789012:table/db1/table1",

    "arn:aws:glue:eu-west-1:123456789012:database/default",
    "arn:aws:glue:eu-west-1:123456789012:database/global_temp",
    "arn:aws:glue:eu-west-1:123456789012:database/parquet",
  ],
}
```

- Make sure you are using the patched operator image
- Add a config map to your spark job namespace as defined [here](conf/configmap.yaml)

```yaml
apiVersion: v1
data:
  hive-site.xml: |-
    <configuration>
        <property>
            <name>hive.imetastoreclient.factory.class</name>
            <value>com.amazonaws.glue.catalog.metastore.AWSGlueDataCatalogHiveClientFactory</value>
        </property>
    </configuration>
kind: ConfigMap
metadata:
  namespace: SPARK_JOB_NAMESPACE
  name: spark-custom-config-map
```

### Submitting your application

In order to submit an application with glue support, you need to add a reference to the configmap in your `SparkApplication` spec.

```yaml
kind: SparkApplication
metadata:
  name: "my-spark-app"
  namespace: SPARK_JOB_NAMESPACE
spec:
  sparkConfigMap: spark-custom-config-map
```

## Working with the spark history server on S3

- Use the appropriate spark version and deploy the [helm](https://github.com/helm/charts/blob/master/stable/spark-history-server/) chart

- Flux / Helm values reference [here](./flux/history.yaml)

## FAQ

- Where can I find a Spark 2 build with Glue support?

  As spark 2 becomes less and less relevant, I opted against the need to add glue support.
  You can take a look [here](https://github.com/bbenzikry/spark-glue/blob/main/build.sh) for a reference build script which you can use to build a Spark 2 distribution to use with the Spark 2 [dockerfile](./docker/spark2.Dockerfile)

- Why a patched operator image?

  The patched image is a simple implementation for properly working with custom configuration files with the spark operator.
  It may be added as a PR in the future or another implementation will take its place. For more information, see the related issue https://github.com/GoogleCloudPlatform/spark-on-k8s-operator/issues/216
