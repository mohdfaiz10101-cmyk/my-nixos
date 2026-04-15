#!/usr/bin/env bash
# ============================================================
# 磁盘池自动发现 + 挂载 + 合并脚本
#
# 逻辑：
#   1. blkid 扫描所有分区，找标签以 POOL- 开头的
#   2. 按文件系统类型自动挂载（ext4/ntfs/btrfs）
#   3. MergerFS 合并所有已挂载的 POOL 盘
#   4. 旧路径 /mnt/data、/mnt/storage_1.8t 创建兼容符号链接
#
# 特性：
#   - 不绑定 UUID / 设备路径
#   - 插几个盘用几个盘
#   - NTFS / ext4 / btrfs 全自动识别
#   - 重装后 rebuild 即恢复
# ============================================================

set -uo pipefail

POOL_MOUNT_BASE="/mnt/pool-disks"
POOL_MERGED="/mnt/pool"
LOG_TAG="disk-pool"
LOCK_FILE="/run/disk-pool.lock"

log() { echo "[disk-pool] $1"; logger -t "$LOG_TAG" "$1"; }

# 获取锁，防止并发
acquire_lock() {
    exec 200>"$LOCK_FILE"
    flock -n 200 || { log "另一个实例正在运行，跳过"; exit 0; }
}

# 扫描所有 POOL- 标签的分区
discover_pool_disks() {
    blkid -o export 2>/dev/null | awk -v RS='\n\n' '
        /LABEL=POOL-/ {
            dev=""; label=""; fstype=""
            n = split($0, lines, "\n")
            for (i=1; i<=n; i++) {
                if (lines[i] ~ /^DEVNAME=/) { split(lines[i], a, "="); dev=a[2] }
                if (lines[i] ~ /^LABEL=/) { split(lines[i], a, "="); label=a[2] }
                if (lines[i] ~ /^TYPE=/) { split(lines[i], a, "="); fstype=a[2] }
            }
            if (dev != "" && label != "") print dev "|" label "|" fstype
        }
    ' 2>/dev/null || true
}

# 扫描 PARITY 标签的分区
discover_parity_disks() {
    blkid -o export 2>/dev/null | awk -v RS='\n\n' '
        /LABEL=PARITY-/ {
            dev=""; label=""; fstype=""
            n = split($0, lines, "\n")
            for (i=1; i<=n; i++) {
                if (lines[i] ~ /^DEVNAME=/) { split(lines[i], a, "="); dev=a[2] }
                if (lines[i] ~ /^LABEL=/) { split(lines[i], a, "="); label=a[2] }
                if (lines[i] ~ /^TYPE=/) { split(lines[i], a, "="); fstype=a[2] }
            }
            if (dev != "" && label != "") print dev "|" label "|" fstype
        }
    ' 2>/dev/null || true
}

# 挂载单个盘
mount_disk() {
    local dev="$1" label="$2" fstype="$3"
    local mountpoint="$POOL_MOUNT_BASE/$label"

    # 已挂载则跳过
    if mountpoint -q "$mountpoint" 2>/dev/null; then
        log "$label 已挂载在 $mountpoint"
        return 0
    fi

    mkdir -p "$mountpoint"

    local mount_opts=""
    case "$fstype" in
        ntfs|ntfs3)
            # ntfs3 内核驱动有 bug（脏卷卡死），优先用 ntfs-3g（FUSE）
            if ntfs-3g -o rw,noatime,uid=1000,gid=100,fmask=0022,dmask=0022 "$dev" "$mountpoint" 2>/dev/null; then
                log "已挂载: $label ($dev, ntfs-3g) → $mountpoint"
                return 0
            else
                log "挂载失败: $label ($dev, ntfs-3g)"
                return 1
            fi
            ;;
        ext4)
            mount_opts="-t ext4 -o rw,noatime"
            ;;
        btrfs)
            mount_opts="-t btrfs -o rw,noatime,compress=zstd"
            ;;
        exfat)
            mount_opts="-t exfat -o rw,noatime,uid=1000,gid=100"
            ;;
        *)
            mount_opts="-o rw,noatime"
            ;;
    esac

    # ntfs 已在 case 中处理并 return
    if mount $mount_opts "$dev" "$mountpoint" 2>/dev/null; then
        log "已挂载: $label ($dev, $fstype) → $mountpoint"
        return 0
    else
        log "挂载失败: $label ($dev, $fstype)"
        return 1
    fi
}

# MergerFS 合并所有已挂载的 POOL 盘
merge_pool() {
    # 收集所有已挂载的 POOL 目录
    local pool_dirs=()
    for dir in "$POOL_MOUNT_BASE"/POOL-*; do
        if [[ -d "$dir" ]] && mountpoint -q "$dir" 2>/dev/null; then
            pool_dirs+=("$dir")
        fi
    done

    if [[ ${#pool_dirs[@]} -eq 0 ]]; then
        log "没有发现已挂载的 POOL 盘，跳过合并"
        return 0
    fi

    # 已合并则先卸载
    if mountpoint -q "$POOL_MERGED" 2>/dev/null; then
        umount "$POOL_MERGED" 2>/dev/null || true
    fi

    mkdir -p "$POOL_MERGED"

    # 构建 MergerFS 挂载路径（用冒号分隔）
    local merged_path
    merged_path=$(IFS=:; echo "${pool_dirs[*]}")

    # MergerFS 策略：
    #   create = mfs   → 新文件写到剩余空间最多的盘
    #   search = ff    → 搜索文件按首次找到
    #   moveonenospc   → 盘满了自动移到其他盘
    #   cache.files    → 启用文件缓存提升性能
    if mergerfs \
        -o defaults,allow_other,use_ino,category.create=mfs,moveonenospc=true,dropcacheonclose=true,cache.files=partial,minfreespace=10G,fsname=pool \
        "$merged_path" "$POOL_MERGED"; then
        log "MergerFS 合并成功: ${#pool_dirs[@]} 个盘 → $POOL_MERGED"

        # 显示池信息
        local total avail
        total=$(df -h "$POOL_MERGED" | awk 'NR==2{print $2}')
        avail=$(df -h "$POOL_MERGED" | awk 'NR==2{print $4}')
        log "池总容量: $total，可用: $avail"
    else
        log "MergerFS 合并失败"
        return 1
    fi
}

# 创建兼容符号链接（旧路径 → 池中的目录）
create_compat_links() {
    # /mnt/pool 下按用途创建目录
    mkdir -p "$POOL_MERGED"/{data,storage,archive,downloads,projects,media,backup}

    # 如果旧路径是真正的挂载点，不动它
    # 如果旧路径不存在或是普通目录，创建链接
    for link_pair in \
        "/mnt/data:$POOL_MERGED/data" \
        "/mnt/storage:$POOL_MERGED/storage" \
        "/mnt/archive:$POOL_MERGED/archive"; do

        local link_path="${link_pair%%:*}"
        local target="${link_pair##*:}"

        # 跳过已有的挂载点
        if mountpoint -q "$link_path" 2>/dev/null; then
            continue
        fi

        # 如果是空目录，替换为链接
        if [[ -d "$link_path" ]] && [[ -z "$(ls -A "$link_path" 2>/dev/null)" ]]; then
            rmdir "$link_path" 2>/dev/null || true
        fi

        if [[ ! -e "$link_path" ]]; then
            ln -sf "$target" "$link_path" 2>/dev/null && \
                log "兼容链接: $link_path → $target"
        fi
    done
}

# 生成 SnapRAID 配置（如果有 PARITY 盘）
generate_snapraid_conf() {
    local parity_disks
    parity_disks=$(discover_parity_disks)

    if [[ -z "$parity_disks" ]]; then
        return
    fi

    local conf="/etc/snapraid.conf"
    local idx=0

    {
        echo "# 自动生成 - disk-pool-mount.sh"
        echo ""

        # 校验盘
        while IFS='|' read -r dev label fstype; do
            local mountpoint="$POOL_MOUNT_BASE/$label"
            if mountpoint -q "$mountpoint" 2>/dev/null; then
                if [[ $idx -eq 0 ]]; then
                    echo "parity $mountpoint/snapraid.parity"
                else
                    echo "$idx-parity $mountpoint/snapraid.parity"
                fi
                ((idx++))
            fi
        done <<< "$parity_disks"

        echo ""

        # 数据盘
        idx=1
        for dir in "$POOL_MOUNT_BASE"/POOL-*; do
            if [[ -d "$dir" ]] && mountpoint -q "$dir" 2>/dev/null; then
                local name
                name=$(basename "$dir")
                echo "data d${idx} $dir"
                ((idx++))
            fi
        done

        echo ""
        echo "content /var/snapraid/content"
        echo "exclude *.tmp"
        echo "exclude /tmp/"
        echo "exclude .Trash*/"
    } > "$conf"

    mkdir -p /var/snapraid
    log "SnapRAID 配置已生成: $conf"
}

# 状态显示
show_status() {
    echo ""
    echo "━━━━━━━━━━ 磁盘池状态 ━━━━━━━━━━"
    echo ""

    echo "发现的 POOL 盘:"
    discover_pool_disks | while IFS='|' read -r dev label fstype; do
        local mounted="✗"
        local mp="$POOL_MOUNT_BASE/$label"
        mountpoint -q "$mp" 2>/dev/null && mounted="✓"
        printf "  %s %-10s %-6s %-20s %s\n" "$mounted" "$label" "$fstype" "$dev" "$mp"
    done

    echo ""
    echo "发现的 PARITY 盘:"
    discover_parity_disks | while IFS='|' read -r dev label fstype; do
        local mounted="✗"
        local mp="$POOL_MOUNT_BASE/$label"
        mountpoint -q "$mp" 2>/dev/null && mounted="✓"
        printf "  %s %-10s %-6s %-20s %s\n" "$mounted" "$label" "$fstype" "$dev" "$mp"
    done

    echo ""
    if mountpoint -q "$POOL_MERGED" 2>/dev/null; then
        echo "合并池 $POOL_MERGED:"
        df -h "$POOL_MERGED" | awk 'NR==2{printf "  总容量: %s  已用: %s  可用: %s  使用率: %s\n", $2, $3, $4, $5}'
    else
        echo "合并池未挂载"
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# === 主逻辑 ===
case "${1:-status}" in
    start)
        acquire_lock
        log "========== 磁盘池启动 =========="

        # 1. 发现并挂载 POOL 盘
        discover_pool_disks | while IFS='|' read -r dev label fstype; do
            mount_disk "$dev" "$label" "$fstype" || true
        done

        # 2. 发现并挂载 PARITY 盘
        discover_parity_disks | while IFS='|' read -r dev label fstype; do
            mount_disk "$dev" "$label" "$fstype" || true
        done

        # 3. MergerFS 合并
        merge_pool

        # 4. 兼容链接
        create_compat_links

        # 5. SnapRAID 配置
        generate_snapraid_conf

        log "========== 磁盘池就绪 =========="
        show_status
        ;;

    stop)
        log "停止磁盘池..."
        umount "$POOL_MERGED" 2>/dev/null || true
        for dir in "$POOL_MOUNT_BASE"/POOL-* "$POOL_MOUNT_BASE"/PARITY-*; do
            umount "$dir" 2>/dev/null || true
        done
        log "磁盘池已停止"
        ;;

    rescan)
        acquire_lock
        log "重新扫描磁盘..."
        new_found=false
        discover_pool_disks | while IFS='|' read -r dev label fstype; do
            mp="$POOL_MOUNT_BASE/$label"
            if ! mountpoint -q "$mp" 2>/dev/null; then
                mount_disk "$dev" "$label" "$fstype" && new_found=true
            fi
        done

        # 如果发现新盘，重新合并
        if [[ "$new_found" == "true" ]]; then
            merge_pool
        fi
        ;;

    status|s)
        show_status
        ;;

    label-guide)
        echo ""
        echo "━━━━━━ 给磁盘打标签（入池） ━━━━━━"
        echo ""
        echo "NTFS 分区:"
        echo "  sudo ntfslabel /dev/sdXN POOL-名字"
        echo ""
        echo "ext4 分区:"
        echo "  sudo e2label /dev/sdXN POOL-名字"
        echo ""
        echo "校验盘:"
        echo "  sudo ntfslabel /dev/sdXN PARITY-1"
        echo ""
        echo "示例（你的盘）:"
        echo "  sudo ntfslabel /dev/sda4 POOL-A1"
        echo "  sudo ntfslabel /dev/sdb1 POOL-B1"
        echo "  sudo e2label /dev/sdd1 POOL-D1"
        echo "  sudo ntfslabel /dev/sde1 POOL-E1"
        echo "  sudo ntfslabel /dev/sdd2 PARITY-1"
        echo ""
        echo "打完标签后重启，或运行:"
        echo "  sudo systemctl restart disk-pool"
        echo ""
        ;;

    *)
        echo "用法: $(basename "$0") <命令>"
        echo "  start        启动磁盘池"
        echo "  stop         停止磁盘池"
        echo "  rescan       扫描新盘"
        echo "  status       查看状态"
        echo "  label-guide  查看打标签教程"
        ;;
esac
