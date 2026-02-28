#!/usr/bin/env bash
# 窗口假死/卡住检测器 — 每 10 秒扫描一次，假死时弹通知
# 原理：检查前台窗口进程是否 D 状态（不可中断）或 CPU 100% 持续 > 30 秒
# 部署：systemd user timer 或 zsh 后台启动

INTERVAL=10
CPU_THRESHOLD=95      # CPU% 超过此值视为可疑
CPU_STUCK_COUNT=3     # 连续 N 次检测到高 CPU 才报警（防误报）
NOTIFIED_PIDS=""      # 已通知的 PID（避免重复弹窗）

declare -A cpu_strikes  # PID → 连续高 CPU 次数

log() { echo "[$(date '+%H:%M:%S')] $*"; }

get_focused_window_pid() {
    # Wayland: 通过 GNOME Shell D-Bus 获取活跃窗口 PID
    local pid
    pid=$(gdbus call --session \
        --dest org.gnome.Shell \
        --object-path /org/gnome/Shell \
        --method org.gnome.Shell.Eval \
        "global.display.focus_window ? global.display.focus_window.get_pid() : 0" \
        2>/dev/null | grep -oP "'(\d+)'" | tr -d "'")
    echo "${pid:-0}"
}

get_all_window_pids() {
    # 获取所有可见窗口的 PID
    gdbus call --session \
        --dest org.gnome.Shell \
        --object-path /org/gnome/Shell \
        --method org.gnome.Shell.Eval \
        "global.get_window_actors().map(a => a.meta_window.get_pid()).filter(p => p > 0).join(',')" \
        2>/dev/null | grep -oP "'([0-9,]+)'" | tr -d "'" | tr ',' '\n' | sort -u
}

check_process_state() {
    local pid=$1
    [[ -f "/proc/$pid/status" ]] || return 1

    local state name
    state=$(awk '/^State:/ {print $2}' "/proc/$pid/status" 2>/dev/null)
    name=$(awk '/^Name:/ {print $2}' "/proc/$pid/status" 2>/dev/null)

    # D = 不可中断睡眠（通常是 I/O 卡住）
    if [[ "$state" == "D" ]]; then
        echo "D:$name"
        return 0
    fi

    # 检查 CPU 使用率
    local cpu
    cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null | awk '{printf "%d", $1}')
    if [[ "${cpu:-0}" -ge "$CPU_THRESHOLD" ]]; then
        echo "CPU:$name:$cpu"
        return 0
    fi

    echo "OK:$name"
    return 1
}

notify_freeze() {
    local pid=$1 name=$2 reason=$3

    # 避免重复通知同一个 PID
    if echo "$NOTIFIED_PIDS" | grep -qw "$pid"; then
        return
    fi
    NOTIFIED_PIDS="$NOTIFIED_PIDS $pid"

    local title body icon
    case "$reason" in
        D)
            title="应用假死"
            body="$name (PID $pid) 处于不可中断状态，可能 I/O 卡住"
            icon="dialog-warning"
            ;;
        CPU)
            title="应用疑似卡死"
            body="$name (PID $pid) CPU 持续 100%，可能已无响应"
            icon="dialog-warning"
            ;;
    esac

    notify-send -u critical -i "$icon" "$title" "$body" \
        -a "Freeze Detector" \
        --action="kill=强制结束" 2>/dev/null &

    log "ALERT: $title — $body"
}

clear_notification() {
    local pid=$1
    NOTIFIED_PIDS=$(echo "$NOTIFIED_PIDS" | sed "s/\b$pid\b//g")
    unset "cpu_strikes[$pid]"
}

main_loop() {
    log "假死检测器启动（间隔 ${INTERVAL}s，CPU阈值 ${CPU_THRESHOLD}%）"

    while true; do
        # 获取所有窗口 PID
        local pids
        pids=$(get_all_window_pids 2>/dev/null)

        for pid in $pids; do
            [[ "$pid" -gt 0 ]] 2>/dev/null || continue
            [[ -d "/proc/$pid" ]] || continue

            local result
            result=$(check_process_state "$pid")
            local state="${result%%:*}"
            local rest="${result#*:}"
            local name="${rest%%:*}"

            case "$state" in
                D)
                    notify_freeze "$pid" "$name" "D"
                    ;;
                CPU)
                    local cpu="${rest##*:}"
                    cpu_strikes[$pid]=$(( ${cpu_strikes[$pid]:-0} + 1 ))
                    if [[ ${cpu_strikes[$pid]} -ge $CPU_STUCK_COUNT ]]; then
                        notify_freeze "$pid" "$name" "CPU"
                    fi
                    ;;
                OK)
                    # 进程恢复正常，清除计数和通知记录
                    if [[ ${cpu_strikes[$pid]:-0} -gt 0 ]] || echo "$NOTIFIED_PIDS" | grep -qw "$pid"; then
                        clear_notification "$pid"
                    fi
                    ;;
            esac
        done

        # 清理已退出进程的记录
        for pid in ${!cpu_strikes[@]}; do
            [[ -d "/proc/$pid" ]] || unset "cpu_strikes[$pid]"
        done

        sleep "$INTERVAL"
    done
}

main_loop
