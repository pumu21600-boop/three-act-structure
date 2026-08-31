#!/system/bin/sh
# v4.2: setsid独立守护进程
MODDIR=/data/adb/modules/oneplus_tri_key_remapper
while [ ! -f /proc/tristatekey/tri_state ]; do sleep 1; done
echo $$ > /sys/fs/cgroup/cgroup.procs 2>/dev/null
setsid nohup $MODDIR/tri_key_monitor.sh --daemon > /dev/null 2>&1 &
