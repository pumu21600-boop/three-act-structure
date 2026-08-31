#!/system/bin/sh
PID_FILE="/data/local/tmp/tri_key/monitor.pid"
LOG_FILE="/data/local/tmp/tri_key/tri_key.log"
SELF_PATH="/data/local/tmp/tri_key/tri_key_monitor.sh"

echo -1000 > /proc/$$/oom_score_adj 2>/dev/null
echo -17 > /proc/$$/oom_adj 2>/dev/null
# cgroup逃逸
echo $$ > /sys/fs/cgroup/cgroup.procs 2>/dev/null

while true; do
    sleep 5
    main_pid=$(cat "$PID_FILE" 2>/dev/null)
    if [ -z "$main_pid" ] || ! kill -0 "$main_pid" 2>/dev/null; then
        echo "[$(date '+%m-%d %H:%M:%S')] 🔄 看门狗检测到主进程死亡，独立重启中..." >> "$LOG_FILE"
        setsid nohup "$SELF_PATH" --daemon > /dev/null 2>&1 &
        exit 0
    fi
done
