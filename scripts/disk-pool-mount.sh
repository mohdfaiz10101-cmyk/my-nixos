#!/usr/bin/env bash
# ============================================================
# 磁盘池管理脚本（精简版）
# 
# 2026-05-09 重构：
#   - 底层 POOL 磁盘挂载 → 移交给 NixOS storage.nix 声明式管理
#   - 本脚本只负责：mergerfs 合并 + SnapRAID 配置 + 热插拔检测
# ============================================================

set -uo pipefail

POOL_MOUNT_BASE="/mnt/pool-disks"
POOL_MERGED="/mnt/pool"
LOG_TAG="disk-pool"
LOCK_FILE="/run/disk-pool.lock"

# 池成员（硬编码，NixOS 声明式挂载的 POOL 盘）
# 新增 POOL 盘时在这里添加，同时更新 storage.nix
POOL_MEMBERS=(
  "/mnt/pool-disks/POOL-D1"
  "/mnt/pool-disks/POOL-E1"
)

log() { echo "[disk-pool] $1"; logger -t "$LOG_TAG" "$1"; }

acquire_lock() {
    exec 200>"$LOCK_FILE"
    flock -n 200 || { log "另一个实例正在运行，跳过"; exit 0; }
}

# 扫描 POOL- 标签的分区（仅用于热插拔检测）
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

# 检查池成员是否都已挂载
check_members_ready() {
    local all_ready=true
    for dir in "${POOL_MEMBERS[@]}"; do
        if ! mountpoint -q "$dir" 2>/dev/null; then
            log "池成员未就绪: $dir"
            all_ready=false
        fi
    done
    $all_ready
}

# MergerFS 合并
merge_pool() {
    if ! check_members_ready; then
        log "池成员未全部就绪，跳过合并"
        return 1
    fi

    # 已合并则先卸载
    if mountpoint -q "$POOL_MERGED" 2>/dev/null; then
        umount "$POOL_MERGED" 2>/dev/null || true
    fi

    mkdir -p "$POOL_MERGED"

    # 构建 MergerFS 路径（冒号分隔）
    local merged_path
    merged_path=$(IFS=:; echo "${POOL_MEMBERS[*]}")

    if mergerfs \
        -o defaults,allow_other,use_ino,category.create=mfs,moveonenospc=true,dropcacheonclose=true,cache.files=partial,minfreespace=10G,fsname=pool \
        "$merged_path" "$POOL_MERGED"; then
        log "MergerFS 合并成功: ${#POOL_MEMBERS[@]} 个盘 → $POOL_MERGED"
        local total avail
        total=$(df -h "$POOL_MERGED" | awk 'NR==2{print $2}')
        avail=$(df -h "$POOL_MERGED" | awk 'NR==2{print $4}')
        log "池总容量: $total，可用: $avail"
    else
        log "MergerFS 合并失败"
        return 1
    fi
}

# 兼容符号链接
create_compat_links() {
    mkdir -p "$POOL_MERGED"/{data,storage,archive,downloads,projects,media,backup}

    for link_pair in \
        "/mnt/data:$POOL_MERGED/data" \
        "/mnt/storage:$POOL_MERGED/storage" \
        "/mnt/archive:$POOL_MERGED/archive"; do

        local link_path="${link_pair%%:*}"
        local target="${link_pair##*:}"

        if mountpoint -q "$link_path" 2>/dev/null; then
            continue
        fi
        if [[ -d "$link_path" ]] && [[ -z "$(ls -A "$link_path" 2>/dev/null)" ]]; then
            rmdir "$link_path" 2>/dev/null || true
        fi
        if [[ ! -e "$link_path" ]]; then
            ln -sf "$target" "$link_path" 2>/dev/null && \
                log "兼容链接: $link_path → $target"
        fi
    done
}

# 生成 SnapRAID 配置
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

        # 数据盘（只包含 POOL_MEMBERS 中的盘）
        idx=1
        for dir in "${POOL_MEMBERS[@]}"; do
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
    echo "===== 磁盘池状态 ====="
    echo ""

    echo "池成员（声明式挂载）:"
    for dir in "${POOL_MEMBERS[@]}"; do
        local mounted="✗"
        mountpoint -q "$dir" 2>/dev/null && mounted="✓"
        printf "  %s %s\n" "$mounted" "$dir"
    done

    echo ""
    echo "发现的额外 POOL 盘（未纳入池）:"
    discover_pool_disks | while IFS='|' read -r dev label fstype; do
        local mp="$POOL_MOUNT_BASE/$label"
        local managed=false
        for dir in "${POOL_MEMBERS[@]}"; do
            [[ "$dir" == "$mp" ]] && managed=true && break
        done
        if ! $managed; then
            local mounted="✗"
            mountpoint -q "$mp" 2>/dev/null && mounted="✓"
            printf "  %s %-10s %-6s %-20s\n" "$mounted" "$label" "$fstype" "$dev"
        fi
    done

    echo ""
    if mountpoint -q "$POOL_MERGED" 2>/dev/null; then
        echo "合并池 $POOL_MERGED:"
        df -h "$POOL_MERGED" | awk 'NR==2{printf "  容量: %s  已用: %s  可用: %s  使用率: %s\n", $2, $3, $4, $5}'
    else
        echo "合并池未挂载"
    fi
    echo ""
}

# === 主逻辑 ===
case "${1:-status}" in
    start)
        acquire_lock
        log "========== 磁盘池启动 =========="

        # 1. 检查底层盘就绪（由 NixOS 声明式挂载）
        if ! check_members_ready; then
            log "等待底层盘就绪..."
            sleep 5
            check_members_ready || log "部分底层盘仍未就绪，尝试继续"
        fi

        # 2. MergerFS 合并
        merge_pool

        # 3. 兼容链接
        create_compat_links

        # 4. SnapRAID 配置
        generate_snapraid_conf

        log "========== 磁盘池就绪 =========="
        show_status
        ;;

    stop)
        log "停止磁盘池..."
        umount "$POOL_MERGED" 2>/dev/null || true
        log "磁盘池已停止"
        ;;

    rescan)
        acquire_lock
        log "重新扫描..."
        # 检查是否有新的 POOL 盘未被 NixOS 管理
        discover_pool_disks | while IFS='|' read -r dev label fstype; do
            local mp="$POOL_MOUNT_BASE/$label"
            local managed=false
            for dir in "${POOL_MEMBERS[@]}"; do
                [[ "$dir" == "$mp" ]] && managed=true && break
            done
            if ! $managed && ! mountpoint -q "$mp" 2>/dev/null; then
                log "发现新盘: $label ($dev)，请将其加入 storage.nix 的 POOL_MEMBERS 并 nixos-rebuild"
            fi
        done
        # 重新合并（如果池已变化）
        merge_pool
        ;;

    status|s)
        show_status
        ;;

    label-guide)
        echo ""
        echo "给磁盘打标签（入池）:"
        echo "  NTFS: sudo ntfslabel /dev/sdXN POOL-名字"
        echo "  ext4: sudo e2label /dev/sdXN POOL-名字"
        echo ""
        echo "打完标签后:"
        echo "  1. 将新盘加入 storage.nix 的 fileSystems"
        echo "  2. 将目录加入本脚本的 POOL_MEMBERS 数组"
        echo "  3. sudo nixos-rebuild switch"
        echo ""
        ;;

    *)
        echo "用法: $(basename "$0") <命令>"
        echo "  start        合并池 (底层盘由 NixOS 挂载)"
        echo "  stop         停止池"
        echo "  rescan       扫描新盘"
        echo "  status       查看状态"
        echo "  label-guide  打标签教程"
        ;;
esac
