{ config, pkgs, lib, ... }:

{
  # --- Letta Docker Compose Service ---
  # 说明：当前使用 Docker Compose 部署（/mnt/ai/ai-cluster/letta/docker-compose.yml）
  # 评估：是否迁移到 systemd 原生服务
  #
  # 配置分析：
  # - 服务：letta + postgres + chromadb + n8n（4 个服务）
  # - 网络：bridge 模式（letta-net）
  # - 端口：8283/8284（letta）、5432（postgres）、8000（chromadb）、5678（n8n）
  # - 依赖：letta 依赖 postgres（healthcheck）
  # - 健康检查：pg_isready
  # - 重启策略：on-failure（letta）、unless-stopped（postgres/chromadb/n8n）
  # - 数据卷：letta-data、postgres-data、chroma-data、/mnt/ai/data/n8n
  #
  # 迁移难度评估：
  # - 需要创建 4 个独立 systemd service（letta + postgres + chromadb + n8n）
  # - 需要处理 bridge 网络（systemd 与 Docker 网络隔离）
  # - 需要迁移所有环境变量（LLM 配置、数据库配置、代理配置）
  # - 需要实现服务依赖链（postgres → letta）
  # - 需要实现健康检查机制
  # - 需要迁移数据卷（systemd DynamicUser 或独立目录）
  # - 需要处理 pgvector 扩展（PostgreSQL with vector support）
  #
  # 建议：
  # ✅ 保留 Docker Compose（推荐）- 工作稳定，4 服务管理简单
  # ⚠️ 迁移到 systemd - 极高复杂度，收益有限
  #
  # 如果决定迁移，需要：
  # 1. 创建 /etc/nixos/modules/letta-postgres.nix（PostgreSQL + pgvector）
  # 2. 创建 /etc/nixos/modules/letta-api.nix（letta 服务）
  # 3. 创建 /etc/nixos/modules/letta-chroma.nix（ChromaDB 服务）
  # 4. 创建 /etc/nixos/modules/letta-n8n.nix（n8n 服务）
  # 5. 迁移所有环境变量到 NixOS 配置
  # 6. 实现服务依赖链（postgres → letta）
  # 7. 添加健康检查（pg_isready + curl http://localhost:8283/）
  # 8. 迁移数据卷到 systemd StateDirectory
  # 9. 处理网络隔离（bridge 网络 vs systemd 本地访问）
}
