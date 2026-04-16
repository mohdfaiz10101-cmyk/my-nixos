#!/usr/bin/env bash
# 健康监控 + Telegram 报警
set -euo pipefail

TG_BOT_TOKEN="8797063873:AAGvApEP9frmA74b6nmxODHshzo1TwJR5ks"
TG_CHAT_ID="5036541266"
ALERT_FILE="/tmp/health-alert-sent"

send_alert() {
    local msg="$1"
    # 防止重复报警（10分钟内同一消息只发一次）
    local hash=$(echo "$msg" | md5sum | cut -d' ' -f1)
    if [ -f "$ALERT_FILE-$hash" ] && [ $(($(date +%s) - $(stat -c %Y "$ALERT_FILE-$hash"))) -lt 600 ]; then
        return
    fi
    curl -s "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d chat_id="$TG_CHAT_ID" \
        -d text="🚨 $(hostname): $msg" \
        -d parse_mode="Markdown" > /dev/null 2>&1 || true
    touch "$ALERT_FILE-$hash"
}

# 检查磁盘使用率
for mount in / /mnt/ai /boot; do
    usage=$(df "$mount" 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}')
    if [ -n "$usage" ] && [ "$usage" -gt 90 ]; then
        send_alert "磁盘 $mount 使用率 ${usage}%！"
    fi
done

# 检查核心 Docker 容器
for svc in chromadb letta litellm; do
    running=$(docker ps --filter "name=$svc" --format "{{.Names}}" 2>/dev/null | head -1)
    if [ -z "$running" ]; then
        send_alert "容器 *$svc* 未运行！尝试自动恢复..."
        # 尝试自动重启
        case "$svc" in
            chromadb) docker start letta-chromadb 2>/dev/null ;;
            letta) cd /mnt/ai/ai-cluster/letta && docker compose up -d 2>/dev/null ;;
            litellm) cd /mnt/ai/ai-cluster/litellm && docker compose up -d 2>/dev/null ;;
        esac
    fi
done

# 检查 Ollama
if ! curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    send_alert "Ollama 服务未响应！"
fi

# 检查内存
mem_avail=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
if [ "$mem_avail" -lt 1024 ]; then
    send_alert "可用内存不足: ${mem_avail}MB！"
fi
