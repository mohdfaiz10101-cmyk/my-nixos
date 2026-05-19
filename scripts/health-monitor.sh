#!/usr/bin/env bash
# 健康监控 + Telegram 报警
set -euo pipefail

TG_BOT_TOKEN="8797063873:AAGvApEP9frmA74b6nmxODHshzo1TwJR5ks"
TG_CHAT_ID="5036541266"
ALERT_FILE="/run/health-alert-sent"

send_alert() {
    local msg="$1"
    # 防止重复报警（10分钟内同一消息只发一次）
    local hash=$(echo "$msg" | md5sum | cut -d' ' -f1)
    if [ -f "$ALERT_FILE-$hash" ] && [ $(($(date +%s) - $(stat -c %Y "$ALERT_FILE-$hash"))) -lt 600 ]; then
        return
    fi
    local HOST_NAME=$(cat /etc/hostname 2>/dev/null || echo "nixos")
    curl -s --connect-timeout 5 --max-time 10 "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d chat_id="$TG_CHAT_ID" \
        -d text="🚨 ${HOST_NAME}: $msg" \
        -d parse_mode="Markdown" > /dev/null 2>&1 || true
    touch "$ALERT_FILE-$hash" 2>/dev/null || true
}

# 检查磁盘使用率（移除/boot，根分区已覆盖）
for mount in / /mnt/ai; do
    usage=$(timeout 3 df "$mount" 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}')
    if [ -n "$usage" ] && [ "$usage" -gt 90 ]; then
        send_alert "磁盘 $mount 使用率 ${usage}%！"
    fi
done

# 检查核心 Docker 容器（用端口探测替代容器名匹配，更可靠）
check_port() {
    timeout 3 curl -s --connect-timeout 2 --max-time 3 "http://localhost:$1" > /dev/null 2>&1
}

# LiteLLM: 端口 4000
if ! check_port 4000; then
    send_alert "LiteLLM (:4000) 未响应！尝试恢复..."
    cd /mnt/ai-cluster/litellm && docker compose up -d 2>/dev/null
fi

# Letta: 端口 8283
if ! check_port 8283; then
    send_alert "Letta (:8283) 未响应！尝试恢复..."
    cd /mnt/ai/ai-cluster/letta && docker compose up -d 2>/dev/null
fi

# ChromaDB: 内部端口，检查容器状态
if ! docker ps --filter "name=letta-chromadb" --filter "status=running" --format "{{.Names}}" 2>/dev/null | grep -q letta-chromadb; then
    send_alert "ChromaDB 容器未运行！尝试恢复..."
    cd /mnt/ai/ai-cluster/letta && docker compose up -d chromadb 2>/dev/null
fi

# 检查 Ollama
if ! timeout 5 curl -s --connect-timeout 3 --max-time 5 http://localhost:11434/api/tags > /dev/null 2>&1; then
    send_alert "Ollama 服务未响应！"
fi

# 检查内存
mem_avail=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
if [ "$mem_avail" -lt 1024 ]; then
    send_alert "可用内存不足: ${mem_avail}MB！"
fi
