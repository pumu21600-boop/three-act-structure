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

# ====== 如果父进程不是init，用setsid重新启动自己 ======
if [ "$PPID" != "1" ] && [ "$1" != "--daemon" ]; then
    # 杀掉所有旧的 tri_key 进程
    for old in $(pgrep -f tri_key_monitor 2>/dev/null); do
        [ "$old" != "$$" ] && kill -9 "$old" 2>/dev/null
    done
    sleep 0.5
    rm -f "$PID_FILE" "$GUARD_FILE"
    setsid nohup "$SELF_PATH" --daemon > /dev/null 2>&1 &
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

# ====== 进程保护 ======
echo $$ > /sys/fs/cgroup/cgroup.procs 2>/dev/null
protect_oom() {
    echo -1000 > /proc/$$/oom_score_adj 2>/dev/null
    echo -17 > /proc/$$/oom_adj 2>/dev/null
}
echo $$ > /sys/fs/cgroup/cgroup.procs 2>/dev/null
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

# ====== 屏蔽三段式原功能 ======
apply_shield() {
    if [ "$1" = "1" ]; then
        chmod 0200 /proc/tristatekey/tri_state 2>/dev/null
    else
        chmod 0644 /proc/tristatekey/tri_state 2>/dev/null
    fi
}

# ====== 防抖 ======
read_stable_mode() {
    m1=$(cat /proc/tristatekey/tri_state 2>/dev/null)
    sleep 0.08
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
        pm hide "$pkg" >/dev/null 2>&1
        am force-stop "$pkg" >/dev/null 2>&1
        log "  killed(hide+stop): $pkg"
    else
        am force-stop "$pkg" >/dev/null 2>&1
        log "  force-stop: $pkg"
    fi
}

# ====== 三重唤醒 ======
force_start() {
    pkg="$1"; intent="$2"
    is_persistent_app "$pkg" && pm unhide "$pkg" >/dev/null 2>&1
    am set-inactive "$pkg" false >/dev/null 2>&1
    cmd appops set "$pkg" RUN_IN_BACKGROUND allow >/dev/null 2>&1
    result=$(am start $intent 2>&1)
    if ! echo "$result" | grep -q "Starting:"; then
        log "  ⚠ am start异常: $(echo "$result" | head -1)"
        return 1
    fi
    waited=0
    while [ $waited -lt 20 ]; do
        pidof "$pkg" >/dev/null 2>&1 && return 0
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
    echo 0 > /sys/class/leds/led:torch_0/brightness 2>/dev/null
    echo 0 > /sys/class/leds/led:switch_0/brightness 2>/dev/null
    echo 500 > /sys/class/leds/led:torch_0/brightness 2>/dev/null
    echo 1 > /sys/class/leds/led:switch_0/brightness 2>/dev/null
    log "  🔦 手电筒已开启"
}
flashlight_off() {
    echo 0 > /sys/class/leds/led:torch_0/brightness 2>/dev/null
    echo 0 > /sys/class/leds/led:switch_0/brightness 2>/dev/null
    log "  🔦 手电筒已关闭"
}

# ====== 独立看门狗（setsid 创建独立session，PPID=init）======
start_watchdog() {
    old_guard=$(cat "$GUARD_FILE" 2>/dev/null)
    [ -n "$old_guard" ] && kill -9 "$old_guard" 2>/dev/null
    setsid nohup /data/local/tmp/tri_key/tri_watchdog.sh > /dev/null 2>&1 &
    echo $! > "$GUARD_FILE"
}

# ====== 异步action执行器 ======
RUNNER_PID=""

do_action_async() {
    pos="$1"; func="$2"

    [ -n "$RUNNER_PID" ] && kill -0 "$RUNNER_PID" 2>/dev/null && {
        kill -9 "$RUNNER_PID" 2>/dev/null
        wait "$RUNNER_PID" 2>/dev/null
        log "  ⊘ 取消旧action"
    }

    (
        log "→ ${pos} ${func}"

        case "$func" in
            record)
                force_start "com.coloros.soundrecorder" \
                    "-a com.oplus.soundrecorder.open_quick_recording -n com.coloros.soundrecorder/oplus.multimedia.soundrecorder.slidebar.TransparentActivity -f 0x14000000"
                set_active_app "com.coloros.soundrecorder" ;;
            screenrecord)
                force_start "com.oplus.screenrecorder" \
                    "-a oplus.intent.action.SCREENRECORDER_START -n com.oplus.screenrecorder/.MainActivity -f 0x14000000"
                set_active_app "com.oplus.screenrecorder" ;;
            screenshot)
                input keyevent KEYCODE_SYSRQ >/dev/null 2>&1 ;;
            ai_chat)
                force_start "com.heytap.speechassist" \
                    "-n com.heytap.speechassist/.aichatlive.ui.AIChatLiveAiActivity -f 0x14000000"
                set_active_app "com.heytap.speechassist" ;;
            music_recognize)
                force_start "com.coloros.colordirectservice" \
                    "-n com.coloros.colordirectservice/com.coloros.directui.identifymusic.RecognizeMusicPermissionActivity -f 0x14000000"
                set_active_app "com.coloros.colordirectservice" ;;
            flashlight)
                flashlight_on; set_active_app "__flashlight__" ;;
            wechat_scan)
                quick_launch "-n com.tencent.mm/.plugin.scanner.ui.BaseScanUI -f 0x14000000"
                set_active_app "com.tencent.mm" ;;
            wechat_pay)
                quick_launch "-n com.tencent.mm/.plugin.offline.ui.WalletOfflineCoinPurseUI -f 0x14000000"
                set_active_app "com.tencent.mm" ;;
            alipay_scan)
                quick_launch '-d alipayqr://platformapi/startapp?saId=10000007'
                set_active_app "com.eg.android.AlipayGphone" ;;
            alipay_pay)
                quick_launch '-d alipayqr://platformapi/startapp?saId=20000056'
                set_active_app "com.eg.android.AlipayGphone" ;;
            custom)
                [ -n "$CUSTOM_CMD" ] && eval "$CUSTOM_CMD" >/dev/null 2>&1 ;;
            camera_open)
                am force-stop com.oplus.camera 2>/dev/null
                am start -W com.oplus.camera/.Camera >/dev/null 2>&1 &
                log "  📷 打开相机" ;;
            off)
                active_pkg=$(get_active_app)
                if [ "$active_pkg" = "__flashlight__" ]; then
                    flashlight_off; clear_active_app
                elif [ -n "$active_pkg" ]; then
                    force_kill_app "$active_pkg"; clear_active_app
                else
                    flashlight_off
                    for pkg in com.coloros.soundrecorder com.oplus.screenrecorder \
                        com.heytap.speechassist com.coloros.colordirectservice \
                        com.tencent.mm com.eg.android.AlipayGphone com.oplus.camera; do
                        pidof "$pkg" >/dev/null 2>&1 && force_kill_app "$pkg"
                    done
                fi ;;
        esac
    ) &
    RUNNER_PID=$!
}

# ====== 初始化 ======
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
    mode=$(cat /proc/tristatekey/tri_state 2>/dev/null)

    [ -z "$mode" ] && { sleep 0.1; continue; }

    if [ "$mode" != "$LAST_MODE" ]; then
        stable_mode=$(read_stable_mode)
        if [ -z "$stable_mode" ] || [ "$stable_mode" != "$mode" ]; then
            # 不更新LAST_MODE，让状态稳定后重试
            sleep 0.2
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
    [ $((_oom_cnt % 20)) -eq 0 ] && echo $$ > /sys/fs/cgroup/cgroup.procs 2>/dev/null
protect_oom

    # 看门狗健康检查（每30轮约4.5秒）
    [ $((_oom_cnt % 30)) -eq 0 ] && { 
        gpid=$(cat "$GUARD_FILE" 2>/dev/null); 
        [ -n "$gpid" ] && ! kill -0 "$gpid" 2>/dev/null && start_watchdog; 
    }
    sleep 0.15
done