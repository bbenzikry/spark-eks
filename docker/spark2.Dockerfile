ARG java_image_tag=8-jre-slim
ARG spark_uid=185

ARG BUILD_DATE
ARG VCS_REF

FROM python:3.7-slim-buster as builder

# Build options
ARG spark_version=3.0.0
# uncomment if you want dev build
# ARG spark_dev_version=v3.0.1-rc2
# HIVE version for glue support
ARG hive_version=2.3.7
# Hadoop and SDK versions for IRSA support
ARG hadoop_version=3.3.0
ARG aws_java_sdk_version=1.11.797
ARG jmx_prometheus_javaagent_version=0.12.0

# maven
ENV MAVEN_VERSION=3.6.3
ENV PATH=/opt/apache-maven-$MAVEN_VERSION/bin:$PATH

WORKDIR /

# JDK repo
RUN echo "deb http://ftp.us.debian.org/debian sid main" >> /etc/apt/sources.list \
    &&  apt-get update \
    &&  mkdir -p /usr/share/man/man1

# install deps
RUN apt-get install -y git wget openjdk-8-jdk patch && rm -rf /var/cache/apt/*

# maven
RUN cd /opt \
    &&  wget https://downloads.apache.org/maven/maven-3/$MAVEN_VERSION/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz \
    &&  tar zxvf /opt/apache-maven-${MAVEN_VERSION}-bin.tar.gz \
    &&  rm apache-maven-${MAVEN_VERSION}-bin.tar.gz

# Download JXM Prometheus javaagent jar
ADD https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/${jmx_prometheus_javaagent_version}/jmx_prometheus_javaagent-${jmx_prometheus_javaagent_version}.jar /prometheus/
RUN chmod 0644 prometheus/jmx_prometheus_javaagent*.jar

# Glue support
RUN git clone https://github.com/bbenzikry/aws-glue-data-catalog-client-for-apache-hive-metastore catalog
ADD https://github.com/apache/hive/archive/rel/release-${hive_version}.tar.gz hive.tar.gz
RUN mkdir hive && tar xzf hive.tar.gz --strip-components=1 -C hive 

## Build patched hive
WORKDIR /hive
ADD https://issues.apache.org/jira/secure/attachment/12958418/HIVE-12679.branch-2.3.patch hive.patch
RUN patch -p0 <hive.patch &&\
    mvn clean install -DskipTests

## Build glue hive client jars
WORKDIR /catalog
RUN mvn clean package -DskipTests -pl -aws-glue-datacatalog-hive2-client
RUN mkdir /jars && find /catalog -name "*.jar" -exec cp {} /jars \;

# Spark
## Uncomment this for source/dev
# RUN git clone https://github.com/apache/spark
# ADD https://github.com/apache/spark/archive/${spark_dev_version}.tar.gz spark.tar.gz
# RUN mkdir /spark && tar xzf spark.tar.gz --strip-components=1 -C /spark

WORKDIR /
ADD https://archive.apache.org/dist/spark/spark-${spark_version}/spark-${spark_version}-bin-without-hadoop.tgz .
RUN tar -xvzf spark-${spark_version}-bin-without-hadoop.tgz
RUN mv spark-${spark_version}-bin-without-hadoop spark

# Uncomment for source
## WORKDIR /spark
## RUN dev/make-distribution.sh --name custom-spark --pip -Pkubernetes -Phive -Phive-thriftserver -Phadoop-provided -Dhive.version=${hive_version}
## WORKDIR /spark/opt

# Hadoop
ADD http://mirrors.whoishostingthis.com/apache/hadoop/common/hadoop-${hadoop_version}/hadoop-${hadoop_version}.tar.gz .
RUN tar -xvzf hadoop-${hadoop_version}.tar.gz
RUN mv hadoop-${hadoop_version} hadoop

# Delete unnecessary hadoop documentation
RUN rm -rf hadoop/share/doc

WORKDIR /hadoop/share/hadoop/tools/lib
RUN rm ./aws-java-sdk-bundle-*.jar
ADD https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/${aws_java_sdk_version}/aws-java-sdk-bundle-${aws_java_sdk_version}.jar .
RUN chmod 0644 aws-java-sdk-bundle*.jar

FROM openjdk:8-jdk-slim as final
LABEL maintainer="bbenzikry@gmail.com" \
    org.label-schema.build-date=$BUILD_DATE \
    org.label-schema.vcs-url="https://github.com/bbenzikry/spark-eks.git" \
    org.label-schema.vcs-ref=$VCS_REF \
    org.label-schema.schema-version="1.0.0"\
    org.label-schema.version="0.0.1"

# Copy spark + glue + hadoop from builder stage
COPY --from=builder /spark /opt/spark
COPY --from=builder /jars/*.jar /opt/spark/jars/
COPY --from=builder /spark/kubernetes/dockerfiles/spark/entrypoint.sh /opt

# On master
## COPY --from=builder /spark/dist/kubernetes/dockerfiles/spark/decom.sh /opt

# Hadoop
COPY --from=builder /hadoop /opt/hadoop
# Copy Prometheus jars from builder stage
COPY --from=builder /prometheus /prometheus

RUN set -ex && \
    sed -i 's/http:\/\/deb.\(.*\)/https:\/\/deb.\1/g' /etc/apt/sources.list && \
    apt-get update && \
    ln -s /lib /lib64 && \
    apt install -y bash tini libc6 libpam-modules krb5-user libnss3 procps && \
    mkdir -p /opt/spark && \
    mkdir -p /opt/spark/examples && \
    mkdir -p /opt/spark/work-dir && \
    touch /opt/spark/RELEASE && \
    rm /bin/sh && \
    ln -sv /bin/bash /bin/sh && \
    echo "auth required pam_wheel.so use_uid" >> /etc/pam.d/su && \
    chgrp root /etc/passwd && chmod ug+rw /etc/passwd && \
    rm -rf /var/cache/apt/*

ENV SPARK_HOME /opt/spark
ENV HADOOP_HOME /opt/hadoop
ENV SPARK_DIST_CLASSPATH="$HADOOP_HOME/etc/hadoop:$HADOOP_HOME/share/hadoop/common/lib/*:$HADOOP_HOME/share/hadoop/common/*:$HADOOP_HOME/share/hadoop/hdfs:$HADOOP_HOME/share/hadoop/hdfs/lib/*:$HADOOP_HOME/share/hadoop/hdfs/*:$HADOOP_HOME/share/hadoop/yarn:$HADOOP_HOME/share/hadoop/yarn/lib/*:$HADOOP_HOME/share/hadoop/yarn/*:$HADOOP_HOME/share/hadoop/mapreduce/lib/*:$HADOOP_HOME/share/hadoop/mapreduce/*:/contrib/capacity-scheduler/*.jar:$HADOOP_HOME/share/hadoop/tools/lib/*"
ENV SPARK_EXTRA_CLASSPATH="$SPARK_DIST_CLASSPATH"
ENV LD_LIBRARY_PATH /lib64

WORKDIR /opt/spark/work-dir
RUN chmod g+w /opt/spark/work-dir
# RUN chmod a+x /opt/decom.sh

ENTRYPOINT [ "/opt/entrypoint.sh" ]

# Specify the User that the actual main process will run as
USER ${spark_uid}