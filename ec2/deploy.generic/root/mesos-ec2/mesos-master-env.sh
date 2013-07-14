export MESOS_port=5050
CLUSTER_URL=`cat /root/mesos-ec2/cluster-url`
if echo $CLUSTER_URL | grep -q zk://; then
    export MESOS_zk=$CLUSTER_URL
fi
export MESOS_log_dir=/mnt/mesos-log
