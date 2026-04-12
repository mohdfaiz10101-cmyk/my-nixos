#!/usr/bin/env bash
# Docker 路径硬防护脚本
# 用途：启动前检查 data-root 是否有效
# 集成到 systemd ExecStartPre，任何检查失败都阻止 Docker 启动

set -e

DOCKER_PATH="/var/lib/docker"
DAEMON_JSON="/etc/docker/daemon.json"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[OK]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1" >&2
}

# 检查 1：daemon.json 不应该存在（由 NixOS 管理）
if [ -f "$DAEMON_JSON" ]; then
    log_error "发现手动 daemon.json（$DAEMON_JSON），将被删除"
    if sudo rm "$DAEMON_JSON"; then
        log_info "已删除 $DAEMON_JSON"
    else
        log_error "无法删除 daemon.json（权限拒绝），Docker 启动可能失败"
        exit 1
    fi
fi

# 检查 2：/var/lib/docker 必须存在且可写
if [ ! -d "$DOCKER_PATH" ]; then
    log_warn "$DOCKER_PATH 不存在，正在创建..."
    if sudo mkdir -p "$DOCKER_PATH"; then
        log_info "已创建 $DOCKER_PATH"
    else
        log_error "无法创建 $DOCKER_PATH"
        exit 1
    fi
fi

if [ ! -w "$DOCKER_PATH" ]; then
    log_error "$DOCKER_PATH 不可写（权限检查失败）"
    exit 1
fi
log_info "$DOCKER_PATH 存在且可写"

# 检查 3：文件系统类型必须是 EXT4（不能是 NTFS/VFAT）
FS_TYPE=$(df -T "$DOCKER_PATH" | tail -1 | awk '{print $2}')
log_info "文件系统类型：$FS_TYPE"

if [[ "$FS_TYPE" == "ntfs" ]] || [[ "$FS_TYPE" == "vfat" ]] || [[ "$FS_TYPE" == "ntfs3" ]]; then
    log_error "❌ Docker 路径在 $FS_TYPE（不支持 POSIX 权限）"
    log_error "❌ 这会导致容器启动失败，请迁移 /var/lib/docker 到 EXT4 分区"
    exit 1
fi

if [ "$FS_TYPE" != "ext4" ] && [ "$FS_TYPE" != "btrfs" ] && [ "$FS_TYPE" != "xfs" ]; then
    log_warn "⚠️ 不确定的文件系统：$FS_TYPE（建议使用 ext4）"
fi

# 检查 4：磁盘空间（至少 5GB）
DISK_USAGE=$(df -B1 "$DOCKER_PATH" | tail -1 | awk '{print $4}')
DISK_USAGE_GB=$((DISK_USAGE / 1024 / 1024 / 1024))
MIN_DISK_GB=5

if [ "$DISK_USAGE_GB" -lt "$MIN_DISK_GB" ]; then
    log_error "❌ 磁盘空间不足（${DISK_USAGE_GB}GB < ${MIN_DISK_GB}GB）"
    exit 1
fi
log_info "磁盘空间：${DISK_USAGE_GB}GB（充足）"

log_info "所有检查通过，Docker 可以启动"
exit 0
