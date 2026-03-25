#!/usr/bin/env bash
# AI 集群启动脚本 — 按依赖顺序启动所有 Docker Compose 服务
set -euo pipefail

CLUSTER="/mnt/ai/ai-cluster"
LOG="/tmp/ai-cluster-start.log"

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

log "========== AI 集群启动 =========="

# 第一层：数据库和基础服务
for svc in chroma litellm; do
    if [ -f "$CLUSTER/$svc/docker-compose.yml" ]; then
        log "启动 $svc..."
        cd "$CLUSTER/$svc" && docker compose up -d 2>>"$LOG" && log "$svc ✓" || log "$svc ✗"
    fi
done

sleep 5

# 第二层：Agent 框架
for svc in letta; do
    if [ -f "$CLUSTER/$svc/docker-compose.yml" ]; then
        log "启动 $svc..."
        cd "$CLUSTER/$svc" && docker compose up -d 2>>"$LOG" && log "$svc ✓" || log "$svc ✗"
    fi
done

sleep 5

# 第三层：应用平台
for svc in hyper-os n8n open-webui; do
    if [ -f "$CLUSTER/$svc/docker-compose.yml" ]; then
        log "启动 $svc..."
        cd "$CLUSTER/$svc" && docker compose up -d 2>>"$LOG" && log "$svc ✓" || log "$svc ✗"
    fi
done

# Dify 特殊处理（yaml 在子目录）
if [ -f "$CLUSTER/dify/docker/docker-compose.yaml" ]; then
    log "启动 dify..."
    cd "$CLUSTER/dify/docker" && docker compose up -d 2>>"$LOG" && log "dify ✓" || log "dify ✗"
fi

sleep 3

# 第四层：其他服务（可选，失败不影响）
for svc in autogen guacamole-local erpnext trip-map; do
    if [ -f "$CLUSTER/$svc/docker-compose.yml" ]; then
        log "启动 $svc..."
        cd "$CLUSTER/$svc" && docker compose up -d 2>>"$LOG" && log "$svc ✓" || log "$svc ✗ (可选)"
    fi
done

log "========== 启动完成 =========="
docker ps --format "table {{.Names}}\t{{.Status}}" 2>>"$LOG" || true
