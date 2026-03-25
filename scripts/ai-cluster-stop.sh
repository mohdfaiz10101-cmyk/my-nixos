#!/usr/bin/env bash
# AI 集群停止脚本
CLUSTER="/mnt/ai/ai-cluster"
for dir in "$CLUSTER"/*/; do
    if [ -f "$dir/docker-compose.yml" ] || [ -f "$dir/docker-compose.yaml" ]; then
        cd "$dir" && docker compose down 2>/dev/null || true
    fi
done
# Dify
cd "$CLUSTER/dify/docker" && docker compose down 2>/dev/null || true
