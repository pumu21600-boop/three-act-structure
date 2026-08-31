#!/system/bin/sh
for f in /data/local/tmp/tri_key/guard.pid /data/local/tmp/tri_key/monitor.pid; do
    [ -f "$f" ] && kill -9 $(cat "$f") 2>/dev/null
done
for p in $(pgrep -f tri_key_monitor 2>/dev/null; pgrep -f tri_watchdog 2>/dev/null); do
    kill -9 $p 2>/dev/null
done
sleep 1
rm -f /data/local/tmp/tri_key/monitor.pid /data/local/tmp/tri_key/guard.pid 2>/dev/null
rm -f /data/adb/service.d/40trikey.sh 2>/dev/null
