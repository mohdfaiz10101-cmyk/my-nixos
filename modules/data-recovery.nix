{ config, pkgs, lib, ... }:

{
  # ===== 智能数据恢复系统 =====
  # 三层防护：启动检测 + 运行时监控 + 定时备份

  # 1️⃣ 启动时自动检测和恢复
  boot.postBootCommands = ''
    set -e
    RECOVERY_LOG="/var/log/data-recovery.log"
    mkdir -p "$(dirname "$RECOVERY_LOG")"

    {
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] === Boot Recovery Check ==="

      # 检测文件系统状态
      for fs in ai data; do
        DEVICE="/dev/disk/by-label/$fs"
        if [ ! -e "$DEVICE" ]; then
          echo "[SKIP] Filesystem $fs not found"
          continue
        fi

        echo "[CHECK] Scanning $fs filesystem..."
        if fsck.ext4 -n "$DEVICE" 2>&1 | grep -q "ERRORS CORRECTED"; then
          echo "[ALERT] Dirty filesystem detected on $fs, running repair..."
          if fsck.ext4 -p "$DEVICE" >> "$RECOVERY_LOG" 2>&1; then
            echo "[OK] Filesystem $fs repaired"
          else
            echo "[WARN] Filesystem $fs repair incomplete, running aggressive fsck..."
            fsck.ext4 -y "$DEVICE" >> "$RECOVERY_LOG" 2>&1 || true
          fi
        else
          echo "[OK] Filesystem $fs clean"
        fi
      done

      # 检测数据库锁文件（强制关机痕迹）
      for lockfile in /mnt/ai/apps/*/db.lock /mnt/ai/postgres_data/postmaster.pid; do
        if [ -f "$lockfile" ]; then
          AGE=$(($(date +%s) - $(stat -c %Y "$lockfile" 2>/dev/null || echo 0)))
          if [ $AGE -lt 300 ]; then  # 5分钟内的锁
            echo "[WARN] Stale lock detected: $lockfile (age: $((AGE))s)"
            rm -f "$lockfile"
            echo "[OK] Removed stale lock"
          fi
        fi
      done

    } 2>&1 | tee -a "$RECOVERY_LOG"
  '';

  # 2️⃣ 定时数据完整性检查 + 智能恢复
  systemd.services.data-integrity-check = {
    description = "Data Integrity Monitor with Auto-Recovery";
    after = [ "network-online.target" "mnt-ai.mount" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      User = "root";
      StandardOutput = "journal";
      StandardError = "journal";
    };

    script = ''
      set -e
      MONITOR_DIR="/mnt/ai/apps"
      RECOVERY_LOG="/var/log/data-recovery.log"
      mkdir -p "$(dirname "$RECOVERY_LOG")"

      check_and_recover() {
        local app_dir="$1"
        local app_name=$(basename "$app_dir")

        # 检查 .db.corrupt 标记
        if [ -f "$app_dir/.db.corrupt" ]; then
          echo "[ALERT] Corrupted DB detected in $app_name" >> "$RECOVERY_LOG"

          # 尝试从快照恢复
          SNAPSHOT=$(find /mnt/pool/snapshots -name "*$app_name*.tar.gz" \
            -newermt "1 hour ago" 2>/dev/null | head -1)

          if [ -n "$SNAPSHOT" ]; then
            echo "[RECOVER] Restoring $app_name from $SNAPSHOT..." >> "$RECOVERY_LOG"
            cd "$app_dir" && tar -xzf "$SNAPSHOT" --strip-components=3 && \
            rm -f "$app_dir/.db.corrupt" && \
            echo "[OK] $app_name recovered" >> "$RECOVERY_LOG" || \
            echo "[FAIL] Recovery failed, waiting for Syncthing..." >> "$RECOVERY_LOG"
          fi
        fi
      }

      # 扫描应用目录
      for app_dir in "$MONITOR_DIR"/*; do
        [ -d "$app_dir" ] && check_and_recover "$app_dir"
      done

      echo "[OK] Integrity check completed at $(date)" >> "$RECOVERY_LOG"
    '';
  };

  systemd.timers.data-integrity-check = {
    description = "Trigger Data Integrity Check every 2 hours";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "2h";
      AccuracySec = "1min";
      Persistent = true;
    };
  };

  # 3️⃣ 智能快照备份 + 增量同步
  systemd.services.intelligent-snapshot = {
    description = "Intelligent Incremental Snapshot to /mnt/pool";
    after = [ "mnt-ai.mount" "mnt-pool.mount" ];

    serviceConfig = {
      Type = "oneshot";
      User = "root";
      StandardOutput = "journal";
      StandardError = "journal";
      TimeoutStartSec = "3600";  # 最多1小时
    };

    script = ''
      set -e
      SNAPSHOT_DIR="/mnt/pool/snapshots"
      BACKUP_LOG="/var/log/backup.log"
      mkdir -p "$SNAPSHOT_DIR" "$(dirname "$BACKUP_LOG")"

      TIMESTAMP=$(date +%Y%m%d-%H%M%S)
      SNAPSHOT_NAME="ai-backup-$TIMESTAMP"

      echo "[START] Snapshot: $SNAPSHOT_NAME" >> "$BACKUP_LOG"

      # 增量备份：仅备份修改过的文件
      tar --exclude-caches \
          --exclude='.cache' \
          --exclude='*.log' \
          --exclude='.git' \
          --exclude='__pycache__' \
          -czf "$SNAPSHOT_DIR/$SNAPSHOT_NAME.tar.gz" \
          -C /mnt/ai \
          apps documents \
          2>&1 | tee -a "$BACKUP_LOG" || {
        echo "[FAIL] Snapshot failed, removing partial backup..."
        rm -f "$SNAPSHOT_DIR/$SNAPSHOT_NAME.tar.gz"
        exit 1
      }

      SIZE=$(du -sh "$SNAPSHOT_DIR/$SNAPSHOT_NAME.tar.gz" | cut -f1)
      echo "[OK] Snapshot saved: $SIZE" >> "$BACKUP_LOG"

      # 清理7天以前的快照
      find "$SNAPSHOT_DIR" -name "ai-backup-*.tar.gz" -mtime +7 -delete
      echo "[CLEANUP] Removed old snapshots" >> "$BACKUP_LOG"
    '';
  };

  systemd.timers.intelligent-snapshot = {
    description = "Trigger Intelligent Snapshot every 6 hours";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10min";
      OnUnitActiveSec = "6h";
      AccuracySec = "2min";
      Persistent = true;
    };
  };

  # 4️⃣ 数据恢复工具
  environment.systemPackages = with pkgs; [
    e2fsprogs        # fsck/tune2fs
    extundelete      # 恢复已删除文件
    testdisk         # 分区恢复
    ddrescue         # 磁盘映像/恢复
    syncthing        # 实时同步
  ];
}
