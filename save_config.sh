#!/system/bin/sh
# WebUI保存配置辅助脚本
UP="$1"; MID="$2"; DN="$3"; SHIELD="$4"
CFG="/data/local/tmp/tri_key/tri_key_config.sh"
cat > "$CFG" << EOF
#!/system/bin/sh
UP_FUNC="$UP"
MID_FUNC="$MID"
DOWN_FUNC="$DN"
CUSTOM_CMD="echo hello"
SHIELD_TRIKEY="$SHIELD"
EOF
echo "saved"
# 杀掉主进程让看门狗重启
kill -9 $(cat /data/local/tmp/tri_key/monitor.pid 2>/dev/null) 2>/dev/null
