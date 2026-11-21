#!/system/bin/sh
# 三段式按键监控脚本 v4.2 - 独立守护进程版
# v4.2: setsid 完全解耦，KSU杀后台不影响；独立看门狗进程(PPID=init)
# v4.1: 移除voice_memo，新增手电筒/微信/支付宝快捷功能

CONFIG_FILE="/data/local/tmp/tri_key/tri_key_config.sh"
LOG_FILE="/data/local/tmp/tri_key/tri_key.log"
PID_FILE="/data/local/tmp/tri_key/monitor.pid"
GUARD_FILE="/data/local/tmp/tri_key/guard.pid"
STATE_FILE="/data/local/tmp/tri_key/action_state"
MODE_FILE="/data/local/tmp/tri_key/last_mode"
SELF_PATH="/data/local/tmp/tri_key/tri_key_monitor.sh"
RELOAD_FLAG="/data/local/tmp/tri_key/reload.flag"

# ====== 如果父进程不是init，用独立session重启自己 ======
if [ "$PPID" != "1" ] && [ "$1" != "--daemon" ]; then
    # 杀掉所有旧的 tri_key 进程
    for old in $(pgrep -f tri_key_monitor 2>> "$LOG_FILE"); do
        [ "$old" != "$$" ] && kill -9 "$old" 2>/dev/null
    done
    sleep 0.5
    rm -f "$PID_FILE" "$GUARD_FILE"
    # 用sh显式调用，不依赖+x权限，也不用setsid（可能不存在）
    nohup sh "$SELF_PATH" --daemon >> "$LOG_FILE" 2>&1 &
    disown 2>/dev/null
    exit 0
fi

# ====== 清理旧进程 ======
if [ -f "$PID_FILE" ]; then
    old_pid=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$old_pid" ] && [ "$old_pid" != "$$" ] && kill -0 "$old_pid" 2>/dev/null; then
        kill -9 "$old_pid" 2>/dev/null
        sleep 0.3
    fi
fi
rm -f "$PID_FILE" 2>/dev/null
echo $$ > "$PID_FILE"

# 清理旧 grab 进程（避免重复占用导致新版启动失败）
_oldg=$(cat /data/local/tmp/tri_key/grab.pid 2>/dev/null)
if [ -n "$_oldg" ] && kill -0 "$_oldg" 2>/dev/null; then
    kill "$_oldg" 2>/dev/null
    sleep 0.2
fi
rm -f /data/local/tmp/tri_key/grab.pid 2>/dev/null

# ====== 进程保护 ======
# cgroup逃逸（优先v1路径）
for _cg in /sys/fs/cgroup/cgroup.procs /dev/cpuctl/tasks; do
    [ -f "$_cg" ] && echo $$ > "$_cg" 2>/dev/null
done
protect_oom() {
    echo -1000 > /proc/$$/oom_score_adj 2>/dev/null
    echo -17 > /proc/$$/oom_adj 2>/dev/null
}
protect_oom

# ====== 日志 ======
trim_log() {
    lines=$(wc -l < "$LOG_FILE" 2>/dev/null)
    [ "$lines" -gt 300 ] && tail -150 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
}

log() {
    trim_log
    echo "[$(date '+%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# ====== 屏蔽三段式原功能（EVIOCGRAB 独占 event5）======
GRAB_BIN="/data/local/tmp/tri_key/tri_grab"
GRAB_PID_FILE="/data/local/tmp/tri_key/grab.pid"
GRAB_LOG="/data/local/tmp/tri_key/grab.log"

grab_alive() {
    gp=$(cat "$GRAB_PID_FILE" 2>/dev/null)
    [ -n "$gp" ] && kill -0 "$gp" 2>/dev/null
}

start_grab() {
    [ -x "$GRAB_BIN" ] || { log "  ⚠ grab二进制缺失"; return 1; }
    grab_alive && return 0
    nohup "$GRAB_BIN" >> "$GRAB_LOG" 2>&1 &
    echo $! > "$GRAB_PID_FILE"
    sleep 0.2
    if grab_alive; then
        log "  🛡 已独占 event5，原生功能屏蔽中"
    else
        log "  ⚠ grab启动失败: $(tail -1 "$GRAB_LOG" 2>/dev/null)"
    fi
}

stop_grab() {
    gp=$(cat "$GRAB_PID_FILE" 2>/dev/null)
    if [ -n "$gp" ] && kill -0 "$gp" 2>/dev/null; then
        kill "$gp" 2>/dev/null
        log "  🔓 已释放 event5，原生功能恢复"
    fi
    rm -f "$GRAB_PID_FILE" 2>/dev/null
}

apply_shield() {
    if [ "$1" = "1" ]; then
        start_grab
    else
        stop_grab
    fi
}

# ====== 防抖 ======
read_stable_mode() {
    m1=$(cat /proc/tristatekey/tri_state 2>/dev/null)
    m2=$(cat /proc/tristatekey/tri_state 2>/dev/null)
    [ "$m1" = "$m2" ] && [ -n "$m1" ] && echo "$m1"
}

# ====== 状态机 ======
set_active_app() { echo "$1" > "$STATE_FILE"; }
get_active_app() { cat "$STATE_FILE" 2>/dev/null; }
clear_active_app() { rm -f "$STATE_FILE"; }

# ====== 系统级保活App ======
is_persistent_app() {
    case "$1" in
        com.heytap.speechassist) return 1 ;;
        *) return 1 ;;
    esac
}

# ====== 暴力关闭App ======
force_kill_app() {
    pkg="$1"
    if is_persistent_app "$pkg"; then
        pm hide "$pkg" >> "$LOG_FILE" 2>&1
        am force-stop "$pkg" >> "$LOG_FILE" 2>&1
        log "  killed(hide+stop): $pkg"
    else
        am force-stop "$pkg" >> "$LOG_FILE" 2>&1
        log "  force-stop: $pkg"
    fi
}

# ====== 三重唤醒 ======
force_start() {
    pkg="$1"; intent="$2"
    is_persistent_app "$pkg" && pm unhide "$pkg" >> "$LOG_FILE" 2>&1
    am set-inactive "$pkg" false >> "$LOG_FILE" 2>&1
    cmd appops set "$pkg" RUN_IN_BACKGROUND allow >> "$LOG_FILE" 2>&1
    result=$(am start $intent 2>&1)
    if ! echo "$result" | grep -q "Starting:"; then
        log "  ⚠ am start异常: $(echo "$result" | head -1)"
        return 1
    fi
    waited=0
    while [ $waited -lt 20 ]; do
        pidof "$pkg" >> "$LOG_FILE" 2>&1 && return 0
        sleep 0.1; waited=$((waited + 1))
    done
    return 1
}

# ====== 快速launch ======
quick_launch() {
    result=$(am start $@ 2>&1)
    if echo "$result" | grep -q "Starting:"; then return 0
    else log "  ⚠ 启动失败: $(echo "$result" | head -1)"; return 1; fi
}

# ====== 手电筒 ======
flashlight_on() {
    echo 0 > /sys/class/leds/led:torch_0/brightness 2>> "$LOG_FILE"
    echo 0 > /sys/class/leds/led:switch_0/brightness 2>> "$LOG_FILE"
    echo 500 > /sys/class/leds/led:torch_0/brightness 2>> "$LOG_FILE"
    echo 1 > /sys/class/leds/led:switch_0/brightness 2>> "$LOG_FILE"
    log "  🔦 手电筒已开启"
}
flashlight_off() {
    echo 0 > /sys/class/leds/led:torch_0/brightness 2>> "$LOG_FILE"
    echo 0 > /sys/class/leds/led:switch_0/brightness 2>> "$LOG_FILE"
    log "  🔦 手电筒已关闭"
}

# ====== 独立看门狗（setsid 创建独立session，PPID=init）======
start_watchdog() {
    old_guard=$(cat "$GUARD_FILE" 2>/dev/null)
    [ -n "$old_guard" ] && kill -9 "$old_guard" 2>/dev/null
    # 用sh显式调用看门狗
    nohup sh /data/local/tmp/tri_key/tri_watchdog.sh >> "$LOG_FILE" 2>&1 &
    disown 2>/dev/null
    echo $! > "$GUARD_FILE"
}

# ====== 异步action执行器 ======
RUNNER_PID=""

do_action_async() {
    pos="$1"; func="$2"

    [ -n "$RUNNER_PID" ] && kill -0 "$RUNNER_PID" 2>/dev/null && {
        kill -9 "$RUNNER_PID" 2>/dev/null
        log "  ⊘ 取消旧action"
    }

    # 预先设置active_app（立即写入STATE_FILE，不依赖异步子shell）
    case "$func" in
        record)           set_active_app "com.coloros.soundrecorder" ;;
        screenrecord)     set_active_app "com.oplus.screenrecorder" ;;
        ai_chat)          set_active_app "com.heytap.speechassist" ;;
        music_recognize)  set_active_app "com.coloros.colordirectservice" ;;
        flashlight)       set_active_app "__flashlight__" ;;
        wechat_scan|wechat_pay) set_active_app "com.tencent.mm" ;;
        alipay_scan|alipay_pay) set_active_app "com.eg.android.AlipayGphone" ;;
        camera_open)      set_active_app "com.oplus.camera" ;;
        xiaobu_screen)    set_active_app "com.coloros.colordirectservice" ;;
        xiaobu_flashnote) set_active_app "com.oplus.gleanerservice" ;;
        ai_voice_note)    set_active_app "com.coloros.accessibilityassistant" ;;
        calculator)       set_active_app "com.coloros.calculator" ;;
    esac

    (
        log "→ ${pos} ${func}"

        case "$func" in
            record)
                force_start "com.coloros.soundrecorder" \
                    "-a com.oplus.soundrecorder.open_quick_recording -n com.coloros.soundrecorder/oplus.multimedia.soundrecorder.slidebar.TransparentActivity -f 0x14000000" ;;
            screenrecord)
                force_start "com.oplus.screenrecorder" \
                    "-a oplus.intent.action.SCREENRECORDER_START -n com.oplus.screenrecorder/.MainActivity -f 0x14000000" ;;
            screenshot)
                input keyevent KEYCODE_SYSRQ >> "$LOG_FILE" 2>&1 ;;
            ai_chat)
                force_start "com.heytap.speechassist" \
                    "-n com.heytap.speechassist/.aichatlive.ui.AIChatLiveAiActivity -f 0x14000000" ;;
            music_recognize)
                force_start "com.coloros.colordirectservice" \
                    "-n com.coloros.colordirectservice/com.coloros.directui.identifymusic.RecognizeMusicPermissionActivity -f 0x14000000" ;;
            flashlight)
                flashlight_on ;;
            wechat_scan)
                quick_launch "-n com.tencent.mm/.plugin.scanner.ui.BaseScanUI -f 0x14000000" ;;
            wechat_pay)
                force_start "com.tencent.mm" \
                    "-n com.tencent.mm/.plugin.offline.ui.WalletOfflineCoinPurseUI -f 0x14000000" ;;
            alipay_scan)
                quick_launch '-d alipayqr://platformapi/startapp?saId=10000007' ;;
            alipay_pay)
                quick_launch '-d alipayqr://platformapi/startapp?saId=20000056' ;;
            custom)
                [ -n "$CUSTOM_CMD" ] && eval "$CUSTOM_CMD" >> "$LOG_FILE" 2>&1 ;;
            camera_open)
                am force-stop com.oplus.camera 2>> "$LOG_FILE"
                am start -W com.oplus.camera/.Camera >> "$LOG_FILE" 2>&1 & ;;
            xiaobu_screen)
                am start-foreground-service -n com.coloros.colordirectservice/.InvokeEntranceService -a com.coloros.directui.InvokeEntranceService >> "$LOG_FILE" 2>&1 ;;
            xiaobu_flashnote)
                # 使用am start-foreground-service触发小布闪记（保留extras参数）
                am set-inactive com.oplus.gleanerservice false >/dev/null 2>&1
                cmd appops set com.oplus.gleanerservice RUN_IN_BACKGROUND allow >/dev/null 2>&1
                sleep 0.2
                result=$(am start-foreground-service \
                    -a oplus.gleanerservice.intent.action.COLLECT_DATA \
                    -n com.oplus.gleanerservice/.flashnotes.business.service.DataCollectService \
                    --ei triggerType 1 2>&1)
                if echo "$result" | grep -qi "Service started\|Starting:"; then
                    log "  📝 小布闪记"
                else
                    log "  ⚠ 小布闪记异常: $(echo "$result" | head -1)"
                fi ;;
            ai_voice_note)
                quick_launch "-n com.coloros.accessibilityassistant/.floatpanel.MainActivity -f 0x14000000" ;;
            calculator)
                quick_launch "-n com.coloros.calculator/com.android.calculator2.Calculator -f 0x14000000" ;;
            off)
                active_pkg=$(get_active_app)
                if [ "$active_pkg" = "__flashlight__" ]; then
                    flashlight_off; clear_active_app
                elif [ -n "$active_pkg" ]; then
                    force_kill_app "$active_pkg"; clear_active_app
                else
                    flashlight_off
                fi ;;
        esac
    ) &
    RUNNER_PID=$!
}

# ====== 初始化 ======
mkdir -p /data/local/tmp/tri_key 2>/dev/null

# 写入启动标记（只要脚本开始执行就会写这个文件）
echo "monitor_init:$(date '+%s')" > /data/local/tmp/tri_key/monitor.tag 2>/dev/null

# 复制脚本到工作目录（供看门狗重启使用）
cp -f /data/adb/modules/oneplus_tri_key_remapper/tri_key_monitor.sh /data/local/tmp/tri_key/tri_key_monitor.sh 2>/dev/null
cp -f /data/adb/modules/oneplus_tri_key_remapper/tri_watchdog.sh /data/local/tmp/tri_key/tri_watchdog.sh 2>/dev/null
cp -f /data/adb/modules/oneplus_tri_key_remapper/tri_grab /data/local/tmp/tri_key/tri_grab 2>/dev/null
chmod 755 /data/local/tmp/tri_key/*.sh 2>/dev/null
chmod 755 /data/local/tmp/tri_key/tri_grab 2>/dev/null

# 创建默认配置（供WebUI读取）
if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" << 'EOF'
#!/system/bin/sh
UP_FUNC="off"
MID_FUNC="off"
DOWN_FUNC="off"
CUSTOM_CMD="echo hello"
SHIELD_TRIKEY="0"
EOF
fi

log "====== 监控启动 PID:$$ PPID:$PPID ======"

[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
apply_shield "$SHIELD_TRIKEY"

if [ -f "$MODE_FILE" ]; then
    LAST_MODE=$(cat "$MODE_FILE" 2>/dev/null)
else
    LAST_MODE=""
fi

while [ ! -f "/proc/tristatekey/tri_state" ]; do sleep 1; done

# 启动独立看门狗
start_watchdog

# ====== 主轮询循环 ======
_oom_cnt=0

while true; do
    # 更新心跳
    echo "alive:$(date '+%s')" > /data/local/tmp/tri_key/heartbeat 2>/dev/null

    # 配置热重载（WebUI保存后立即生效，无需杀进程）
    if [ -f "$RELOAD_FLAG" ]; then
        rm -f "$RELOAD_FLAG" 2>/dev/null
        [ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
        apply_shield "$SHIELD_TRIKEY"
        log "  ⟳ 配置已热重载 UP=$UP_FUNC MID=$MID_FUNC DN=$DOWN_FUNC SHIELD=$SHIELD_TRIKEY"
    fi

    mode=$(cat /proc/tristatekey/tri_state 2>/dev/null)

    [ -z "$mode" ] && { sleep 0.1; continue; }

    if [ "$mode" != "$LAST_MODE" ]; then
        stable_mode=$(read_stable_mode)
        if [ -z "$stable_mode" ] || [ "$stable_mode" != "$mode" ]; then
            # 不更新LAST_MODE，让状态稳定后重试
            sleep 0.05
            continue
        fi

        LAST_MODE="$mode"
        echo "$mode" > "$MODE_FILE"

        [ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
        apply_shield "$SHIELD_TRIKEY"

        ACTION_POS=""; ACTION_FUNC=""
        case "$mode" in
            1) ACTION_POS="上拨"; ACTION_FUNC="$UP_FUNC" ;;
            2) ACTION_POS="中拨"; ACTION_FUNC="$MID_FUNC" ;;
            3) ACTION_POS="下拨"; ACTION_FUNC="$DOWN_FUNC" ;;
        esac

        [ -n "$ACTION_FUNC" ] && do_action_async "$ACTION_POS" "$ACTION_FUNC"
    fi

    _oom_cnt=$((_oom_cnt + 1))
    [ $((_oom_cnt % 20)) -eq 0 ] && {
        for _cg in /sys/fs/cgroup/cgroup.procs /sys/fs/cgroup/unified/cgroup.procs /dev/cpuctl/tasks /sys/fs/cgroup/uid_0/cgroup.procs; do
            echo $$ > "$_cg" 2>/dev/null
        done
        protect_oom
    }

    # 看门狗健康检查（每30轮约1.5秒）
    [ $((_oom_cnt % 30)) -eq 0 ] && { 
        gpid=$(cat "$GUARD_FILE" 2>/dev/null); 
        [ -n "$gpid" ] && ! kill -0 "$gpid" 2>/dev/null && start_watchdog; 
    }

    # grab 保活（每20轮约1秒）：挂了立刻重启，防止原生功能复活
    [ $((_oom_cnt % 20)) -eq 0 ] && [ "$SHIELD_TRIKEY" = "1" ] && ! grab_alive && start_grab
    sleep 0.05
done