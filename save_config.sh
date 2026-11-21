#!/system/bin/sh
# WebUI保存配置辅助脚本
UP="$1"; MID="$2"; DN="$3"; SHIELD="$4"
CFG="/data/local/tmp/tri_key/tri_key_config.sh"
mkdir -p /data/local/tmp/tri_key 2>/dev/null
cat > "$CFG" << EOF
#!/system/bin/sh
UP_FUNC="$UP"
MID_FUNC="$MID"
DOWN_FUNC="$DN"
CUSTOM_CMD="echo hello"
SHIELD_TRIKEY="$SHIELD"
EOF
echo "saved"
# 通知主进程热重载（不杀进程，避免4~5秒空窗期）
touch /data/local/tmp/tri_key/reload.flag 2>/dev/null