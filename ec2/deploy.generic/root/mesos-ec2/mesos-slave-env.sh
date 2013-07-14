export MESOS_master=`cat /root/mesos-ec2/cluster-url`
export MESOS_log_dir=/mnt/mesos-log
export MESOS_work_dir=/mnt/mesos-work
if [ -e /proc/cgroups ]; then
  if [ `grep memory /proc/cgroups | awk '{ print $4 }'` = '1' ]; then
    # Only enable cgroups if the memory controller is enabled;
    # Debian disables it by default.
    export MESOS_isolation=cgroups
  fi
fi
