# spark-on-eks

<!-- markdownlint-disable MD033 -->
<center>
<a href="#">
<img src="https://user-images.githubusercontent.com/1993348/91601148-d0b01b80-e971-11ea-9903-6299b2396499.png" width="100%" height="50%">
</a>

Examples and custom spark images for working with the spark-on-k8s operator on AWS.

Allows using Spark 2 with IRSA and Spark 3 with IRSA and AWS Glue as a metastore

**Note**: Spark 2 images will not be updated, please see the [FAQ](#faq)

---

![operator](https://img.shields.io/docker/cloud/build/bbenzikry/spark-eks-operator?style=plastic&label=operator)
![spark2](https://img.shields.io/docker/cloud/build/bbenzikry/spark-eks/spark2-latest?label=spark2)
![pyspark2](https://img.shields.io/docker/cloud/build/bbenzikry/spark-eks/pyspark2-latest?label=pyspark2)
![spark3](https://img.shields.io/docker/cloud/build/bbenzikry/spark-eks/spark3-latest?label=spark3)
![pyspark3](https://img.shields.io/docker/cloud/build/bbenzikry/spark-eks/pyspark3-latest?label=pyspark3)
![spark3-edge](https://img.shields.io/docker/cloud/build/bbenzikry/spark-eks/spark3-edge?label=spark3-edge)
![pyspark3-edge](https://img.shields.io/docker/cloud/build/bbenzikry/spark-eks/pyspark3-edge?label=pyspark3-edge)

</center>

## Prerequisites

- Deploy [spark-on-k8s operator](https://github.com/GoogleCloudPlatform/spark-on-k8s-operator) using the [helm chart](https://github.com/helm/charts/tree/master/incubator/sparkoperator) and the [patched operator](https://github.com/bbenzikry/spark-on-k8s-operator/tree/hive-subpath) image `bbenzikry/spark-eks-operator:latest`

Suggested values for the helm chart can be found in the [flux](./flux/releases/operator.yaml) example.

> Note: Do not create the spark service account automatically as part of chart use.

## using IAM roles for service accounts on EKS

### Creating roles and service account

- Create an AWS role for driver
- Create an AWS role for executors

> [AWS docs on creating policies and roles](https://docs.aws.amazon.com/eks/latest/userguide/create-service-account-iam-policy-and-role.html)

- Add default service account EKS role for executors in your spark job namespace ( optional )

```yaml
# NOTE: Only required when not building spark from source or using a version of spark < 3.1. If you use our *-edge docker images for spark3/pyspark3 you can skip this step, as it will rely on the driver pod.
apiVersion: v1
kind: ServiceAccount
metadata:
  name: default
  namespace: SPARK_JOB_NAMESPACE
  annotations:
    # can also be the driver role
    eks.amazonaws.com/role-arn: "arn:aws:iam::ACCOUNT_ID:role/executor-role"
```

- Make sure spark service account is configured to an EKS role as well

```yaml
## With the spark3 source builds, when this is configured and no executor role exists, executors default to this SA as well.
# This is not recommended for production until a stable release is provided.
apiVersion: v1
kind: ServiceAccount
metadata:
  name: spark
  namespace: SPARK_JOB_NAMESPACE
  annotations:
    eks.amazonaws.com/role-arn: "arn:aws:iam::ACCOUNT_ID:role/executor-role"
```

### Building a compatible image

- For spark < 3.0.0, see [spark2.Dockerfile](./docker/spark2.Dockerfile) and [pyspark.Dockerfile](./docker/pyspark.Dockerfile)

- For spark 3.0.0+, see [spark3.Dockerfile](./docker/spark3.Dockerfile) [spark3.edge.Dockerfile](docker/spark3.edge.Dockerfile)

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
# source / master build
FROM bbenzikry/spark-eks:spark3-edge
# pyspark2
FROM bbenzikry/spark-eks:pyspark2-latest
# pyspark3
FROM bbenzikry/spark-eks:pyspark3-latest
# pyspark3-edge
FROM bbenzikry/spark-eks:pyspark3-edge
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
  securityContext:
    fsGroup: 65534
```

- Full example [here]()

### Working with AWS Glue as metastore

#### Prerequisites

- Make sure your driver and executor roles have the relevant glue permissions

```json
{
  /* Example below is an example configuration for accessing db1/table1. 
  Modify this as you deem worthy for potential access. 
  Last 3 resources must be present for your region.
  */

  "Effect": "Allow",
  "Action": ["glue:*Database*", "glue:*Table*", "glue:*Partition*"],
  "Resource": [
    "arn:aws:glue:us-west-2:123456789012:catalog",
    "arn:aws:glue:us-west-2:123456789012:database/db1",
    "arn:aws:glue:us-west-2:123456789012:table/db1/table1",

    "arn:aws:glue:eu-west-1:123456789012:database/default",
    "arn:aws:glue:eu-west-1:123456789012:database/global_temp",
    "arn:aws:glue:eu-west-1:123456789012:database/parquet"
  ]
}
```

- Make sure you are using the patched operator image
- Add a config map to your spark job namespace as defined [here](conf/configmap.yaml)

### Submitting your application

## Working with the spark history server on S3

## FAQ

- Where can I find a Spark 2 build with Glue support?
  - As spark 2 becomes less and less relevant, I opted against the need to add glue support.
    You can take a look [here](https://github.com/tinyclues/spark-glue-data-catalog/blob/master/build-spark.sh) for a reference implementation which you can add to the Spark 2 dockerfile [dockerfile](./docker/spark2.Dockerfile)
- Why a patched operator image?
  - Some PRs are still pending on the operator image. Once they are pushed through and properly tested, you can use them instead.
