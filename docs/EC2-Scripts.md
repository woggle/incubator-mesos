The `mesos-ec2` script located in the Mesos's `ec2` directory allows you to
launch, manage and shut down Mesos clusters on Amazon EC2. You don't need to
build Mesos locally to use this script -- you just need Python 2.6+ installed.

Currently, no official AMI (system image) is provided, so you will need to
build an AMI with Mesos installed on it. A script @setup-mesos-ami.sh@ is
provided for that purpose. If you find a prebuilt Mesos AMI from a third-party,
you can skip the "AMI setup" instructions below.

# AMI setup

First, you will need to create a template AMI. To do so, start with an VM
with Linux installed that supports the EC2-supplied keypair and run the
supplied `setup-mesos-ami.sh` script (in the `ec2` directory of the Mesos
source distribution) as root on that.
Then capture an AMI image of that (for example, from the Amazon's web interface
or `ec2-create-image` while the VM is running).

`setup-mesos-ami.sh` expects a base image that runs something Debian- or
Fedora-like. It assumes that sufficient EC2 support exists on the base AMI
to use SSH keypairs supplied to EC2 when launching the instance. It installs
into /root, which is assumed to be root's home directory.

`setup-mesos-ami.sh` assumes that maven is available as a `yum` or `apt-get`
package or is already installed. This is not true in some distributions,
for example, Amazon's Linux AMI (as of June 2013). There also may be additional
incompatabilities due to variations in package names.

The setup-mesos-ami.sh does the following:
* install many packages we require to build and run Mesos and Hadoop HDFS and
  Hadoop MapReduce;
* attempt to configure the image to allow keypair-based root login. (This
  should work if the cloud-config package is used as on the Amazon Linux AMI;
  otherwise local adjustments may be necessary.);
* download (from git) and build mesos,
    * installing it to `/root/mesos`
    * copying the JAR to `/root/mesos.jar`
* build hadoop with Mesos, copy the result to `/root/hadoop`, with an archive
  for use on slaves in `/root/hadoop.tar.gz`
* copy a built tree of zookeeper to `/root/zookeeper`
* download (from git) and build spark in `/root/spark` and install
  `spark-env.sh` that points to the mesos library.
* download scala (for Spark) and place it in `/root/scala`

## Optional AMI setup

Mesos will work best if your AMI supports cgroups. Debian (as of version 7)
disables the cgroup memory controller by default, but it can reenabled
with a kernel command-line option specified in `/boot/grub/menu.lst`.

If you intend to distribute an AMI publicly, remember to remove copies
of your SSH public keys from `authorized_keys` files.

# Using the `mesos-ec2 script

@mesos-ec2@ is designed to manage multiple named clusters.
You can launch a new cluster (telling the script its size and giving it a
name), shutdown an existing cluster, or log into a cluster. Each cluster is
identified by placing its machines into EC2 security groups whose names are
derived from the name of the cluster. For example, a cluster named `test` will
contain a master node in a security group called `test-master`, and a number of
slave nodes in a security group called `test-slaves`. The `mesos-ec2` script
will create these security groups for you based on the cluster name you
request. You can also use them to identify machines belonging to each cluster
in the EC2 Console or ElasticFox.

## Before You Start

* Create an Amazon EC2 key pair for yourself. This can be done by logging into
your Amazon Web Services account through the
[AWS console](http://aws.amazon.com/console/),
clicking Key Pairs on the left sidebar, and creating and downloading a key.
Make sure that you set the permissions for the private key file to `600`
(i.e. only you can read and write it) so that `ssh` will work. Note that this
keypair will be *copied to the instances*, so it may be a good idea to use a
single-purpose keypair for this.

* Whenever you want to use the `mesos-ec2` script, set the environment
variables `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` to your Amazon
EC2 access key ID and secret access key. These can be obtained from the
[AWS homepage](http://aws.amazon.com/) by clicking
Account > Security Credentials > Access Credentials.

## Launching a cluster

*   Go to the `ec2` directory.

*   Launch a cluster using the `mesos-ec2` utility:

        mesos-ec2 ARGS launch CLUSTER-NAME
  
    where `CLUSTER-NAME` is a name of your choice and ARGS contain at least:
    * `-a AMI` -- the ID of the AMI you are using (required);
    * `-k KEYPAIR-NAME` -- EC2's name for the keypair you created (required);
    * `-i IDENTITY-FILE` -- filename of the private part of the EC2 keypair
      (required);

    In addition, you are likely to want to supply some of the following
    options:
    * `-z ZONE` -- the availability zone to launch in (must be compatable with
      the AMI) (default is `us-east-1b`)
    * `-t INSTANCE-TYPE` -- the instance type to use (default is
      `m1.small`, which is too small to run many things reasonably)
    * `-s NUM-SLAVES` -- number of slaves to run (default is 1)
    * `--ft=NUM-MASTERS` -- run Mesos in fault-tolerant mode if NUM_MASTERS
      is greater than 1 (default is 1)

    If launching fails due to, e.g. not having the right permissions on your
    private key file, you can run `mesos-ec2 launch` with the `--resume` option
    to restart the setup process on a existing cluster.

    There are other useful options described under `mesos-ec2 --help`

## Viewing the web UI

*   To view the webui, create an  SSH-tunnelled SOCKS proxy by running something
    like

        mesos-ec2 ARGS login -D 6666 CLUSTER-NAME

    (6666 is the port number SSH listens for SOCKS connections) and configuring
    your browser to use the SOCKS proxy as with a Proxy Autoconfiguration file
    like [this one from Apache Whirr](https://svn.apache.org/repos/asf/whirr/trunk/resources/hadoop-ec2-proxy.pac). You will need to supply your SSH private key with
    the `-i` option in ARGS.

    Although it possible to open up the webui ports in the EC2 firewall
    configuration, this is a currently serious security risk: the webui port
    is also used for Mesos IPC, so (for example) frameworks or task launch
    requests can be submitted through the webui port.

*   To run jobs while logged into the cluster, a properly configured copy of
    Spark is provided in `/root/spark` and a copy of Hadoop MapReduce is provided
    in `/root/hadoop`. In addition, an HDFS instance is running at
    `hdfs://MASTER:9000/`. If you specified the `-v` option to `mesos-ec2` when
    launching the cluster, an EBS-backed HDFS instance will be running at
    `hdfs://MASTER:9010/`.

## Running Jobs

*   Go into the `ec2` directory in the release of Mesos you downloaded.

*   Run `./mesos-ec2 -i KEY-FILE login <cluster-name>` to SSH into the cluster,
    where `KEY-FILE` is your SSH private key file. (This is just for
    convenience; you could also use Elasticfox or the EC2 console.)

*   Copy your code to all the nodes. To do this, you can use the provided
    script `~/mesos-ec2/copy-dir`, which, given a directory path, RSYNCs it to
    the same location on all the slaves.

    If used the supplied AMI setup script, a copy of Spark and Hadoop MapReduce
    should already be installed (and configured to use the Mesos cluster)
    in `/root/spark` and `/root/hadoop` respectively.

*   If your job needs to access large datasets, the fastest way to do that is
    to load them from Amazon S3 or an Amazon EBS device into an instance of the
    Hadoop Distributed File System (HDFS) on your nodes. The `mesos-ec2` script
    already sets up a HDFS instance for you. It's installed in
    `/root/ephemeral-hdfs` and can be accessed using the `bin/hadoop` script in
    that directory or using `hdfs://MASTER:9000/`.
    Note that the data in this HDFS goes away when you stop and
    restart a machine.

*   If you specified the `--ebs-vol-size` option to `mesos-ec2 launch`, then
    there is also a _persistent HDFS_ instance in `/root/presistent-hdfs` (or
    `hdfs://MASTER:9010/`) that will keep data across cluster restarts. This
    data will be stored on EBS volumes attached to the EC2 instances.

If you get an "Executor on slave X disconnected" error when running your
framework, you probably haven't copied your code the slaves. Use the
`~/mesos-ec2/copy-dir` script to do that. If you keep getting the error,
though, look at the slave's logs for that framework using the Mesos web UI.
Please see [logging and debugging](Logging-and-Debugging.textile) for details.

## Pausing and Restarting EBS-backed clusters

The `mesos-ec2` script also supports pausing a cluster if you are using
EBS-backed virtual machines. In this case, the VMs are stopped but not
terminated, so they *lose all data on ephemeral disks (`/mnt`, ephemeral-hdfs)`
but keep the data in their root partitions and their `persistent-hdfs`. Stopped
machines will not cost you any EC2 cycles, but `will` continue to cost money
for EBS storage.
  
*   To stop one of your clusters, go into the `ec2` directory and run
    `./mesos-ec2 stop CLUSTER-NAME`.

*   To restart it later, run `./mesos-ec2 -i KEY-FILE start <cluster-name>`.

*   To ultimately destroy the cluster and stop consuming EBS space, run
    `./mesos-ec2 destroy CLUSTER-NAME` as described in the previous section.

## Changing Mesos settings

*   To change the configuration of Mesos edit (on the master that
    `mesos-ec2 login` will log into)
    `/root/mesos-ec2/mesos-slave-env.sh` and
    `/root/mesos-ec2/mesos-master-env.sh` and run (on the master)

        /root/mesos-ec2/copy-dir /root/mesos-ec2
        /root/mesos/sbin/stop-mesos-cluster.sh
        /root/mesos/sbin/start-mesos-cluster.sh
