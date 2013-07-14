#!/bin/bash
set -e

# This script is intended to be run on a "blank" Linux machine to make a
# suitable template for the mesos-ec2 scripts.


### SETTINGS TO CHANGE CREATED AMI ###

MESOS_GIT=git://git.apache.org/incubator-mesos.git
MESOS_BRANCH=master

SPARK_ARCHIVE=http://spark-project.org/files/spark-0.7.2-prebuilt-cdh4.tgz

# Scala version to get; must be compatible with Spark.
SCALA_ARCHIVE=http://www.scala-lang.org/downloads/distrib/files/scala-2.9.3.tgz

# Hadoop MapReduce version to build
HADOOP_VERSION=hadoop-2.0.0-mr1-cdh4.2.1
# Prebuilt Hadoop to get for HDFS. Needs to be wire-compatible with the
# HDFS verison.
HDFS_ARCHIVE=http://archive.cloudera.com/cdh4/cdh/4/hadoop-2.0.0-cdh4.2.1.tar.gz
HDFS_EXTRACT_DIR=hadoop-2.0.0-cdh4.2.1

EXTRA_PACKAGES=

### END OF SETTINGS ###

if [ -x /usr/bin/yum ]; then
  JAVA_PACKAGE='java-sdk jre'
  JAVA_HOME=/usr/lib/jvm/java
elif [ -x /usr/bin/apt-get ]; then
  JAVA_PACKAGE=default-jdk
  JAVA_HOME=/usr/lib/jvm/default-java
else
  cat <<_END_OF_MESSAGE_
I don't understand this version of Linux; giving up.
_END_OF_MESSAGE_
  exit 1
fi

FEDORA_PACKAGES="
  git-core
  autoconf
  automake
  libtool
  gcc-c++
  libcurl-devel
  zlib-devel
  openssl-devel
  patch
  python-devel
  ant
  exportfs
  maven
  rsync
  wget
  psmisc
  $JAVA_PACKAGE
"
DEBIAN_PACKAGES="
  build-essential
  automake
  autoconf
  libtool
  git-core
  libcurl4-openssl-dev
  zlib1g-dev
  libssl-dev
  patch
  python2.7-dev
  ant
  nfs-kernel-server
  nfs-common
  maven
  rsync
  wget
  psmisc
  $JAVA_PACKAGE
"

# Utility function to checkout a particular branch OR tag in a git repo.
checkout_branch() {
  BRANCH=$1
  if git tag -l $BRANCH | grep -q $BRANCH; then
    git checkout -b from-$BRANCH $BRANCH
  elif [ "$BRANCH" != `git rev-parse --abbrev-ref HEAD` ]; then
    git checkout -b $BRANCH --track origin/$BRANCH
  fi
}

# 1. Install dependencies.
cat <<_END_OF_MESSAGE_

  Installing dependencies.

_END_OF_MESSAGE_

if [ -x /usr/bin/yum ]; then
  yum install -y $FEDORA_PACKAGES
  # Apparently yum won't fail when some packages can't be found.
  mvn -v || echo "Failed to install dependencies" && exit 1
elif [ -x /usr/bin/apt-get ]; then
  apt-get install -y $DEBIAN_PACKAGES
else
  cat <<_END_OF_MESSAGE_
Could not find package manager; giving up.
_END_OF_MESSAGE_
  exit 1
fi


# 2. Setup AMI for root login.
if [ -e /etc/cloud/cloud.cfg ]; then
  sed -i -e 's/disable_root: 1/disable_root: 0/' /etc/cloud/cloud.cfg
  if grep -q disable_root /etc/cloud/cloud.cfg; then
    echo 'disable_root: 0' >> /etc/cloud/cloud.cfg
  fi
fi

if [ -e /etc/init.d/ec2-get-credentials ]; then
  sed -i -e 's/username=.*/username=root/' /etc/init.d/ec2-get-credentials
fi

if [ -e /etc/ssh/sshd_config ]; then
  sed -i -e 's/^PermitRootLogin .*/PermitRootLogin without-password/' \
     /etc/ssh/sshd_config
  if [ -x /etc/init.d/ssh ]; then
    /etc/init.d/ssh restart
  elif [ -x /etc/init.d/sshd ]; then
    /etc/init.d/sshd restart
  else
    cat <<_END_OF_MESSAGE_
WARNING: Didn't know how to restart sshd.
_END_OF_MESSAGE_
  fi
  if [ -e /root/.ssh/authorized_keys ]; then
    if grep -q command= /root/.ssh/authorized_keys; then
      grep -v command= /root/.ssh/authorized_keys || true >/tmp/auth-keys
      mv /tmp/auth-keys /root/.ssh/authorized_keys
    fi
  fi
fi

# 3. Create new user for Hadoop/HDFS.
if id hadoop >/dev/null 2>&1; then
  true
else
  # We create the user with a home directory so building hadoop as hadoop
  # works.
  useradd -r -m hadoop
fi

# 4. Build Mesos and Hadoop.
export JAVA_HOME

pushd /root >/dev/null 2>&1

# Checkout mesos into /root/mesos-source
rm -fr mesos-source
git clone $MESOS_GIT mesos-source
pushd mesos-source >/dev/null 2>&1
checkout_branch $MESOS_BRANCH
./bootstrap
popd >/dev/null 2>&1

# Do an out-of-source build into /root/mesos-build, installing into /root/mesos
if [ -d mesos-build ]; then
  rm -f -r mesos-build
fi
mkdir mesos-build
pushd mesos-build >/dev/null 2>&1
../mesos-source/configure --prefix=/root/mesos
make
make install
make maven-install
# Manually install the mesos jar into /root/mesos.jar;
#                  mesos supporting Hadoop into /root/{hadoop,hadoop.tar.gz}
MESOS_JAR=`echo src/mesos-@PACKAGE_VERSION@.jar | ./config.status --file=-:-`
cp $MESOS_JAR /root/mesos.jar
chmod a+r /root/mesos.jar

popd >/dev/null 2>&1

# Make sure 'hadoop' user has permissions to build this.
chmod -R a+rX mesos-build
chmod -R a+rX mesos-source
chmod a+rx .
chown -R hadoop mesos-build/hadoop

# Build hadoop archive as the 'hadoop' user.
# (We can't do it as root because some distributions of Hadoop MapReduce
#  refuse to run the jobtracker as root, and the make target unconditionally
#  tests the built jobtracker.)
if [ -d /root/hadoop ]; then
  rm -f -r /root/hadoop
fi
if [ -f /root/hadoop.tar.gz ]; then
  rm -f -r /root/hadoop.tar.gz
fi
pushd mesos-build/hadoop >/dev/null 2>&1
su hadoop -c "make $HADOOP_VERSION"
mv $HADOOP_VERSION/build/hadoop-*-mesos /root/hadoop
mv $HADOOP_VERSION/build/hadoop-*-mesos.tar.gz /root/hadoop.tar.gz
popd >/dev/null 2>&1

# 5. Copy zookeeper into place.
pushd /root >/dev/null 2>&1
cp -r mesos-build/3rdparty/zookeeper-*[0-9] ./zookeeper
popd >/dev/null 2>&1

# 6. Setup Scala.
rm -fr scala
wget -O scala.tar.gz $SCALA_ARCHIVE
tar --no-same-owner -zxf scala.tar.gz
mv scala-* scala

# 7. Setup Spark.
export SCALA_HOME=/root/scala
rm -fr spark
wget -O spark.tar.gz $SPARK_ARCHIVE
tar -zxf spark.tar.gz
mv spark-* spark

# 8. Install HDFS (prebuilt) twice.
wget -O hdfs-archive.tar.gz $HDFS_ARCHIVE
tar --no-same-owner -zxf hdfs-archive.tar.gz
mv $HDFS_EXTRACT_DIR ephemeral-hdfs
tar --no-same-owner -zxf hdfs-archive.tar.gz
mv $HDFS_EXTRACT_DIR persistent-hdfs

if [ -e ephemeral-hdfs/etc/hadoop ]; then
  mv ephemeral-hdfs/etc/hadoop ephemeral-hdfs/conf
  mv persistent-hdfs/etc/hadoop persistent-hdfs/conf
fi

# Suppress messages about native code being unavailable; they can prevent
# the start-dfs.sh, etc. scripts from working
for dir in ephemeral-hdfs persistent-hdfs; do
  cat <<_END_OF_STRING_ >>$dir/conf/log4j.properties
log4j.logger.org.apache.hadoop.util.NativeCodeLoader=ERROR
_END_OF_STRING_
done


# 9. Make sure things are world-readable.
chmod -R a+rX /root/hadoop /root/hadoop.tar.gz /root/scala /root/spark
