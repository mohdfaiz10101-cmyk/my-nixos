#!/usr/bin/env bash
# LiteLLM 健康检查 + 自动拉起脚本
# 每 5 分钟检查一次，如果不健康则尝试重启服务

set -euo pipefail

LITELLM_URL="http://localhost:4000/health/liveliness"
LOG_FILE="/var/log/litellm-healthcheck.log"
MAX_RETRIES=3

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

check_health() {
    curl -s -f "$LITELLM_URL" -m 5 > /dev/null 2>&1
}

restart_litellm() {
    log "❌ LiteLLM 不健康，尝试重启..."

    # 检查 Docker 是否运行
    if ! systemctl is-active docker > /dev/null 2>&1; then
        log "⚠️  Docker 未运行，尝试启动..."
        systemctl start docker
        sleep 3
    fi

    # 检查 litellm 服务是否存在
    if systemctl list-unit-files | grep -q "litellm.service"; then
        log "🔄 重启 litellm.service..."
        systemctl restart litellm
        sleep 15
    else
        log "⚠️  litellm.service 未配置，尝试手动启动容器..."
        cd /mnt/ai-cluster/litellm 2>/dev/null || cd /mnt/ai/ai-cluster/litellm 2>/dev/null || {
            log "❌ LiteLLM 目录不存在，无法启动"
            exit 1
        }
        docker compose up -d
        sleep 15
    fi
}

verify_recovery() {
    local retries=0
    while [ $retries -lt $MAX_RETRIES ]; do
        if check_health; then
            log "✅ LiteLLM 恢复正常"
            return 0
        fi
        retries=$((retries + 1))
        log "⏳ 等待恢复（重试 $retries/$MAX_RETRIES）..."
        sleep 10
    done

    log "❌ 重启后仍不健康，请手动检查日志：journalctl -u litellm -n 50"
    return 1
}

# === 主流程 ===

if check_health; then
    # 健康状态不输出日志（避免日志膨胀）
    exit 0
fi

log "⚠️  LiteLLM 健康检查失败"

# 尝试重启
restart_litellm

# 验证恢复
verify_recovery
