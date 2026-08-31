#!/system/bin/sh
PID_FILE="/data/local/tmp/tri_key/monitor.pid"
LOG_FILE="/data/local/tmp/tri_key/tri_key.log"
SELF_PATH="/data/local/tmp/tri_key/tri_key_monitor.sh"

# 多路径cgroup逃逸
for _cg in /sys/fs/cgroup/cgroup.procs /sys/fs/cgroup/unified/cgroup.procs /dev/cpuctl/tasks /sys/fs/cgroup/uid_0/cgroup.procs; do
    echo $$ > "$_cg" 2>/dev/null
done
echo -1000 > /proc/$$/oom_score_adj 2>/dev/null
echo -17 > /proc/$$/oom_adj 2>/dev/null

while true; do
    sleep 5
    main_pid=$(cat "$PID_FILE" 2>/dev/null)
    if [ -z "$main_pid" ] || ! kill -0 "$main_pid" 2>/dev/null; then
        echo "[$(date '+%m-%d %H:%M:%S')] 🔄 看门狗检测到主进程死亡，独立重启中..." >> "$LOG_FILE"
        # 用sh显式调用主监控脚本
        nohup sh "$SELF_PATH" --daemon > /dev/null 2>&1 &
        disown 2>/dev/null
        exit 0
    fi
done