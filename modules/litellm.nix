{ config, pkgs, lib, ... }:

{
  # --- LiteLLM Docker Compose Service ---
  # 说明：当前使用 Docker Compose 部署（/mnt/ai/ai-cluster/litellm/docker-compose.yml）
  # 评估：是否迁移到 systemd 原生服务
  #
  # 配置分析：
  # - 服务：redis + litellm
  # - 网络：host 模式（litellm）+ bridge（redis）
  # - 端口：6379（redis）、4000（litellm）
  # - 依赖：litellm 依赖 redis（healthcheck）
  # - 健康检查：redis-cli ping + /health/readiness
  # - 重启策略：unless-stopped
  #
  # 迁移难度评估：
  # - 需要创建 2 个独立 systemd service（redis + litellm）
  # - 需要处理 host 网络模式（systemd 与 Docker 网络隔离）
  # - 需要迁移 volume 挂载和 env_file
  # - 需要实现 healthcheck 机制
  # - 健康检查命令：redis-cli ping、curl http://localhost:4000/health/readiness
  #
  # 建议：
  # ✅ 保留 Docker Compose（推荐）- 工作稳定，管理简单
  # ⚠️ 迁移到 systemd - 复杂度高，收益有限
  #
  # 如果决定迁移，需要：
  # 1. 创建 /etc/nixos/modules/litellm-redis.nix（redis 服务）
  # 2. 创建 /etc/nixos/modules/litellm-api.nix（litellm 服务）
  # 3. 迁移 env_file 到 NixOS secrets（sops-nix）
  # 4. 迁移 volume 到 systemd DynamicUser 或独立目录
  # 5. 实现服务依赖（requires = [ "redis.service" ] + after）
  # 6. 添加 healthcheck（systemd restart 机制或外部脚本）
}
