#!/system/bin/sh
# v4.5: 用sh显式调用，不依赖脚本执行权限
MODDIR=/data/adb/modules/oneplus_tri_key_remapper
mkdir -p /data/local/tmp/tri_key 2>/dev/null
echo "booted:$(date '+%s')" > /data/local/tmp/tri_key/boot.tag 2>/dev/null
echo "started:$(date '+%s')" > /data/local/tmp/tri_key/service.tag 2>/dev/null
# 等待三段式节点就绪
while [ ! -f /proc/tristatekey/tri_state ]; do sleep 1; done
echo "tri_ok:$(date '+%s')" >> /data/local/tmp/tri_key/service.tag 2>/dev/null
# 用sh执行，不依赖脚本+x权限
sh $MODDIR/tri_key_monitor.sh --daemon > /data/local/tmp/tri_key/service.log 2>&1 &
echo "launched:$(date '+%s')" >> /data/local/tmp/tri_key/service.tag 2>/dev/null