# spark-on-eks

![Logos](logos.png)

Examples and custom spark images for working with the spark-on-k8s operator on AWS.

![docker](https://img.shields.io/docker/automated/bbenzikry/spark-eks?style=plastic)
![build](https://img.shields.io/docker/build/bbenzikry/spark-eks?style=plastic)

![spark2](https://img.shields.io/docker/v/bbenzikry/spark-eks/spark2-latest)
![pyspark2](https://img.shields.io/docker/v/bbenzikry/spark-eks/pyspark2-latest)

![spark3](https://img.shields.io/docker/v/bbenzikry/spark-eks/spark3-latest)
![pyspark3](https://img.shields.io/docker/v/bbenzikry/spark-eks/pyspark3-latest)

![spark3](https://img.shields.io/docker/v/bbenzikry/spark-eks/spark3-edge)
![pyspark3](https://img.shields.io/docker/v/bbenzikry/spark-eks/pyspark3-edge)

![operator](https://img.shields.io/docker/v/bbenzikry/spark-eks/operator-latest)

## Prerequisites

- Deploy [spark-on-k8s operator](https://github.com/GoogleCloudPlatform/spark-on-k8s-operator) using the [helm chart](https://github.com/helm/charts/tree/master/incubator/sparkoperator) or with [flux](./flux/releases/operator.yaml) with the [patched operator](./docker/operator.Dockerfile) image

> Note: Do not create the spark service account automatically as part of chart use

## using IAM roles for service accounts on EKS

### Creating roles and service account

- Create an AWS role for driver
- Create an AWS role for executors

> [AWS docs on creating policies and roles](https://docs.aws.amazon.com/eks/latest/userguide/create-service-account-iam-policy-and-role.html)

- Add default service account EKS role for executors in your spark job namespace

```yaml
# NOTE: This is only required when not building spark from source or using a version of spark < 3.1. If using our edge docker images for spark3/pyspark3 you can skip this step
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

```dockerfile
FROM bbenzikry/spark-eks:3-irsa
```

### Submit your spark application with IRSA support

```yaml
hadoopConf:
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

## Working with AWS Glue as metastore

## Working with the spark history server on S3

## FAQ

- Where can I find a spark 2 build with Glue support?
  - As spark 2 becomes less and less relevant, I opted against the need to add glue support.
    You can take a look [here](https://github.com/tinyclues/spark-glue-data-catalog/blob/master/build-spark.sh) for a reference implementation which you can add to the spark2 irsa [dockerfile](./irsa/spark2/spark2.Dockerfile)
