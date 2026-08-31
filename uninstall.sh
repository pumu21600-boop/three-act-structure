#!/system/bin/sh
# 三段式模块卸载脚本 - 彻底清理所有残留

# 1. 杀掉所有相关进程（不留活口）
for p in $(pgrep -f 'tri_key_monitor\|tri_watchdog\|tri_key_config' 2>/dev/null); do
    kill -9 "$p" 2>/dev/null
done

# 2. 通过PID文件杀
for f in /data/local/tmp/tri_key/guard.pid /data/local/tmp/tri_key/monitor.pid; do
    [ -f "$f" ] && kill -9 "$(cat "$f" 2>/dev/null)" 2>/dev/null
done

sleep 1

# 3. 删除所有模块运行时文件
rm -rf /data/local/tmp/tri_key 2>/dev/null
rm -rf /data/local/tmp/trikey_* 2>/dev/null

# 4. 清理开机自启残留
rm -f /data/adb/service.d/tri_key_monitor.sh 2>/dev/null
rm -f /data/adb/service.d/40trikey.sh 2>/dev/null
rm -f /data/adb/service.d/*trikey* 2>/dev/null
rm -f /data/adb/post-fs-data.d/*trikey* 2>/dev/null

# 5. 恢复三段式原功能权限
chmod 0644 /proc/tristatekey/tri_state 2>/dev/null

# 6. 清理可能残留的日志缓存
rm -f /data/local/tmp/tri_key*.log 2>/dev/null
rm -f /data/local/tmp/*trikey* 2>/dev/null

# 7. 验证清理结果
[ -z "$(pgrep -f tri_key 2>/dev/null)" ] && \
[ ! -d "/data/local/tmp/tri_key" ] && \
[ "$(stat -c '%a' /proc/tristatekey/tri_state 2>/dev/null)" = "644" ] && \
echo "✅ 三段式模块已彻底清理，无任何残留" || \
echo "⚠️ 清理完成，请手动检查"