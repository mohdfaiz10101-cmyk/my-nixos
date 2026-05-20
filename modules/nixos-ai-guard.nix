{ config, pkgs, ... }:

{
  # ========== NixOS GUI Guardian ==========
  # 每30分钟检测GUI状态，异常自动修复
  # 仅在 08:00-23:00 运行

  systemd.services.nixos-gui-guardian = {
    description = "NixOS GUI Guardian - 自动检测修复图形界面";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScriptBin "nixos-gui-guardian" ''
        #!/usr/bin/env bash
        # nixos-gui-guardian — NixOS GUI 状态巡检脚本
        # 每30分钟检测一次，异常自动修复

        set -euo pipefail

        FIX_MODE="--fix"
        LOG="/var/log/nixos-gui-guardian.log"
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

        log() {
            echo "[$TIMESTAMP] $1" | tee -a "$LOG"
        }

        log_ok()   { echo "[$TIMESTAMP] ✅ $1" | tee -a "$LOG"; }
        log_fail() { echo "[$TIMESTAMP] ❌ $1" | tee -a "$LOG"; }
        log_warn() { echo "[$TIMESTAMP] ⚠️  $1" | tee -a "$LOG"; }

        # 检查 root 权限
        if [ "$(id -u)" -ne 0 ]; then
            echo "此脚本需要 root 权限，请使用 sudo"
            exit 1
        fi

        # 1. 检测是否有图形会话
        if loginctl list-sessions 2>/dev/null | grep -q "seat0"; then
            log "✅ GUI 会话正常"
            exit 0
        fi

        log_warn "无活跃图形会话"

        # 2. 检查 SDDM
        if ! systemctl is-active sddm >/dev/null 2>&1; then
            log_warn "SDDM 未运行"

            if [ "$FIX_MODE" = "--fix" ]; then
                log "🔧 尝试启动 SDDM..."
                systemctl start sddm 2>&1 | tee -a "$LOG" || true
                sleep 3

                if systemctl is-active sddm >/dev/null 2>&1; then
                    log_ok "SDDM 启动成功"
                else
                    log_fail "SDDM 启动失败"
                    log "   检查配置: sudo nixos-rebuild dry-build"
                fi
            fi
        else
            log_ok "SDDM 运行中"
        fi

        # 3. 检查 kernel cmdline
        if cat /proc/cmdline 2>/dev/null | grep -q "nomodeset"; then
            log_fail "检测到 nomodeset — 图形输出受限"
            log "   当前 generation: $(nix-env --list-generations 2>/dev/null | grep '\*' | awk '{print $1}' || echo 'unknown')"

            if [ "$FIX_MODE" = "--fix" ]; then
                log "🔧 尝试回滚..."
                nixos-rebuild switch --rollback 2>&1 | tee -a "$LOG" || true
            fi
        fi

        # 4. 检查 Hyprland 用户服务
        if sudo -u charlie systemctl --user is-active hyprland 2>/dev/null; then
            log_ok "Hyprland 运行中"
        else
            log_warn "Hyprland 未运行"
        fi

        # 5. 检查 Waybar
        if sudo -u charlie systemctl --user is-active waybar 2>/dev/null; then
            log_ok "Waybar 运行中"
        else
            log_warn "Waybar 未运行"
        fi

        log "巡检完成"
      ''}/bin/nixos-gui-guardian";
    };
  };

  systemd.timers.nixos-gui-guardian = {
    description = "每30分钟检测GUI状态";
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "30min";
      # 只在08:00-23:00运行
      OnCalendar = "08:00-23:00:00/30";
    };
    wantedBy = [ "timers.target" ];
  };

  # ========== NixOS Config Check（配置自检工具）==========

  environment.systemPackages = with pkgs; [
    (writeShellScriptBin "nixos-config-check" ''
      #!/usr/bin/env bash
      # NixOS 配置自检工具

      echo "=== NixOS 配置自检 ==="
      echo ""

      echo "📋 Generation 列表:"
      sudo nix-env --list-generations 2>/dev/null || echo "  (无法获取)"
      echo ""

      echo "📋 Kernel Cmdline:"
      cat /proc/cmdline 2>/dev/null || echo "  (无法获取)"
      echo ""

      echo "📋 SDDM 状态:"
      systemctl is-active sddm 2>/dev/null || echo "  (无法获取)"
      echo ""

      echo "📋 NetworkManager 状态:"
      systemctl is-active NetworkManager 2>/dev/null || echo "  (无法获取)"
      echo ""

      echo "📋 Docker 状态:"
      systemctl is-active docker 2>/dev/null || echo "  (无法获取)"
      echo ""

      echo "📋 SSH 状态:"
      systemctl is-active sshd 2>/dev/null || echo "  (无法获取)"
      echo ""

      echo "📋 磁盘使用:"
      df -h 2>/dev/null | head -10 || echo "  (无法获取)"
      echo ""

      echo "📋 最近 rebuild 日志:"
      ls -lt /tmp/nixos-rebuild-safe-*.log 2>/dev/null | head -3 || echo "  (无日志)"
    '')

    # ========== AI 修复引擎 ==========
    (writeShellScriptBin "nixos-ai-fix-engine" ''
      #!/usr/bin/env bash
      # nixos-ai-fix-engine — NixOS AI 错误修复引擎
      # 用法: nixos-ai-fix-engine [error_log_path]

      set -euo pipefail

      ERROR_LOG="''${1:-/tmp/nixos-rebuild-safe-*.log}"
      MEMORY="/home/charlie/.claude/projects/-home-charlie/memory/lessons-learned.md"
      LOG="/var/log/nixos-ai-fix-engine.log"
      TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

      RED='\033[0;31m'
      GREEN='\033[0;32m'
      YELLOW='\033[1;33m'
      NC='\033[0m'

      log() { echo "[$TIMESTAMP] $1" | tee -a "$LOG"; }
      log_ok()   { echo -e "$GREEN[OK]$NC $1" | tee -a "$LOG"; }
      log_fail() { echo -e "$RED[FAIL]$NC $1" | tee -a "$LOG"; }
      log_warn() { echo -e "$YELLOW[WARN]$NC $1" | tee -a "$LOG"; }

      if [ "$(id -u)" -ne 0 ]; then
          log_warn "部分修复需要 root，尝试 sudo..."
          SUDO="sudo"
      else
          SUDO=""
      fi

      # 查找最新的错误日志
      if [ "$ERROR_LOG" = "/tmp/nixos-rebuild-safe-*.log" ]; then
          LATEST_LOG=$(ls -t /tmp/nixos-rebuild-safe-*.log 2>/dev/null | head -1)
          if [ -z "$LATEST_LOG" ]; then
              log_fail "未找到错误日志"
              exit 1
          fi
          ERROR_LOG="$LATEST_LOG"
      fi

      log "🔍 分析错误日志: $ERROR_LOG"
      ERROR_CONTENT=$(cat "$ERROR_LOG" 2>/dev/null || echo "")

      # 已知错误模式库
      declare -A PATTERNS
      declare -A FIXES
      declare -A CONFIDENCE

      PATTERNS["nomodeset_leak"]="nomodeset.*kernel|kernel.*nomodeset|boot.kernelParams.*nomodeset"
      FIXES["nomodeset_leak"]="修复 specialisation mkForce 覆盖"
      CONFIDENCE["nomodeset_leak"]=95

      PATTERNS["sddm_failed"]="sddm.*fail|display.manager.*error|sddm.*service.*failed"
      FIXES["sddm_failed"]="检查 SDDM 配置或回滚"
      CONFIDENCE["sddm_failed"]=90

      PATTERNS["nvidia_error"]="nvidia.*error|nouveau.*fail|gpu.*error|drm.*error"
      FIXES["nvidia_error"]="切换显卡驱动模式"
      CONFIDENCE["nvidia_error"]=85

      PATTERNS["network_timeout"]="network.*timeout|dhcp.*fail|NetworkManager.*error"
      FIXES["network_timeout"]="重启 NetworkManager"
      CONFIDENCE["network_timeout"]=80

      # 错误分类
      MATCHED=""
      MAX_CONFIDENCE=0

      for pattern_name in "''${!PATTERNS[@]}"; do
          pattern="''${PATTERNS[$pattern_name]}"
          confidence="''${CONFIDENCE[$pattern_name]}"

          if echo "$ERROR_CONTENT" | grep -qiE "$pattern" 2>/dev/null; then
              if [ "$confidence" -gt "$MAX_CONFIDENCE" ]; then
                  MATCHED="$pattern_name"
                  MAX_CONFIDENCE="$confidence"
              fi
          fi
      done

      if [ -n "$MATCHED" ]; then
          log "✅ 匹配错误模式: $MATCHED (置信度: ''${MAX_CONFIDENCE}%)"

          if [ "$MAX_CONFIDENCE" -ge 90 ]; then
              log_ok "置信度≥90%，执行自动修复..."

              case "$MATCHED" in
                  "nomodeset_leak")
                      if grep -q "boot.kernelParams.*mkForce \[\]" /etc/nixos/configuration.nix 2>/dev/null; then
                          $SUDO sed -i 's/boot.kernelParams.*mkForce \[\]/boot.kernelParams = lib.mkAfter ["nomodeset" "systemd.unit=multi-user.target"];/' /etc/nixos/configuration.nix
                          log_ok "已修复 kernelParams 配置"
                      fi
                      ;;
                  "sddm_failed")
                      $SUDO systemctl restart sddm 2>/dev/null || true
                      ;;
              esac
          fi

          # 记录到记忆
          echo "" >> "$MEMORY"
          echo "## $(date '+%Y-%m-%d %H:%M') — AI自动修复" >> "$MEMORY"
          echo "**错误模式**: $MATCHED" >> "$MEMORY"
          echo "**置信度**: ''${MAX_CONFIDENCE}%" >> "$MEMORY"
          echo "" >> "$MEMORY"
      else
          log_warn "未匹配已知错误模式"
      fi
    '')

    # ========== 更新检测器 ==========
    (writeShellScriptBin "nixos-update-checker" ''
      #!/usr/bin/env bash
      # nixos-update-checker — NixOS 更新检测 + 安全补丁提醒

      set -euo pipefail

      AUTO_TASK="''${1:---no-auto-task}"
      CONFIG_DIR="/etc/nixos"
      MEMORY="/home/charlie/.claude/projects/-home-charlie/memory/lessons-learned.md"
      OP_TASKS="/home/charlie/op-tasks.md"
      LOG="/var/log/nixos-update-checker.log"
      TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

      log() { echo "[$TIMESTAMP] $1" | tee -a "$LOG"; }
      log_ok()   { echo -e "\033[0;32m✅ $1\033[0m" | tee -a "$LOG"; }
      log_warn() { echo -e "\033[1;33m⚠️  $1\033[0m" | tee -a "$LOG"; }
      log_info() { echo -e "\033[0;34mℹ️  $1\033[0m" | tee -a "$LOG"; }

      cd "$CONFIG_DIR" 2>/dev/null || exit 1

      log "📦 NixOS 更新检测开始"

      # 检查 nixpkgs 版本
      CURRENT_DATE=$(grep "nixpkgs.url" flake.nix | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || echo "unknown")
      log "   当前版本: $CURRENT_DATE"

      # 检查 flake.lock 年龄
      if [ -f flake.lock ]; then
          LOCK_AGE=$(( ( $(date +%s) - $(stat -c %Y flake.lock 2>/dev/null || stat -f %m flake.lock 2>/dev/null || echo 0) ) / 86400 ))
          log "   flake.lock 年龄: $LOCK_AGE 天"

          if [ "$LOCK_AGE" -ge 30 ]; then
              log_warn "flake.lock 超过30天未更新"
          fi
      fi

      # 检查安全公告
      SECURITY_ISSUES=""
      if command -v curl &>/dev/null; then
          SECURITY_FEED=$(curl -s "https://nixos.org/blog/feed.xml" 2>/dev/null | grep -oE "CVE-[0-9-]+" | sort -u | head -5 || echo "")

          if [ -n "$SECURITY_FEED" ]; then
              log_warn "发现安全公告: $SECURITY_FEED"
              SECURITY_ISSUES="$SECURITY_FEED"
          else
              log_ok "未发现安全公告"
          fi
      fi

      # 自动创建任务
      if [ "$AUTO_TASK" = "--auto-task" ] && [ -n "$SECURITY_ISSUES" ]; then
          TASK_DATE=$(date '+%Y-%m-%d')
          TASK_TITLE="NIXOS-SECURITY-UPDATE — 安全更新: $SECURITY_ISSUES"

          if ! grep -q "$TASK_TITLE" "$OP_TASKS" 2>/dev/null; then
              echo "- [ ] [OP] [$TASK_DATE] $TASK_TITLE" >> "$OP_TASKS"
              log_ok "已创建安全更新任务"
          fi
      fi

      log "更新检测完成"
    '')

    # ========== 决策引擎 ==========
    (writeShellScriptBin "nixos-decision-engine" ''
      #!/usr/bin/env bash
      # nixos-decision-engine — NixOS AI 决策引擎

      set -euo pipefail

      COMMAND="''${1:-full-check}"
      MEMORY="/home/charlie/.claude/projects/-home-charlie/memory/lessons-learned.md"
      LOG="/var/log/nixos-decision-engine.log"
      TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

      log() { echo "[$TIMESTAMP] $1" | tee -a "$LOG"; }
      log_ok()   { echo -e "\033[0;32m✅ $1\033[0m" | tee -a "$LOG"; }
      log_fail() { echo -e "\033[0;31m❌ $1\033[0m" | tee -a "$LOG"; }
      log_warn() { echo -e "\033[1;33m⚠️  $1\033[0m" | tee -a "$LOG"; }
      log_info() { echo -e "\033[0;34mℹ️  $1\033[0m" | tee -a "$LOG"; }

      collect_state() {
          # 收集系统状态
          LAST_REBUILD="unknown"
          LAST_REBUILD_LOG=$(ls -t /tmp/nixos-rebuild-safe-*.log 2>/dev/null | head -1)
          if [ -n "$LAST_REBUILD_LOG" ]; then
              if tail -5 "$LAST_REBUILD_LOG" | grep -q "所有检查通过"; then
                  LAST_REBUILD="success"
              elif tail -5 "$LAST_REBUILD_LOG" | grep -q "失败"; then
                  LAST_REBUILD="failed"
              fi
          fi

          CURRENT_GEN=$(nix-env --list-generations 2>/dev/null | grep '\*' | awk '{print $1}' || echo "unknown")
          UNCOMMITTED=0
          if [ -d /etc/nixos/.git ]; then
              cd /etc/nixos
              UNCOMMITTED=$(git status --porcelain 2>/dev/null | wc -l)
          fi

          echo "{\"last_rebuild\":\"$LAST_REBUILD\",\"current_generation\":\"$CURRENT_GEN\",\"uncommitted_changes\":$UNCOMMITTED}"
      }

      make_decision() {
          local state="$1"
          local last_rebuild=$(echo "$state" | grep -o '"last_rebuild":"[^"]*"' | cut -d'"' -f4)
          local uncommitted=$(echo "$state" | grep -o '"uncommitted_changes":[0-9]*' | awk '{print $2}')

          if [ "$uncommitted" -gt 0 ] 2>/dev/null; then
              echo "rebuild_recommended"
          elif [ "$last_rebuild" = "failed" ]; then
              echo "analyze_failure"
          else
              echo "no_action"
          fi
      }

      case "$COMMAND" in
          "full-check")
              STATE=$(collect_state)
              DECISION=$(make_decision "$STATE")
              log "决策: $DECISION"
              echo "$DECISION"
              ;;
          *)
              echo "用法: $0 {full-check}"
              ;;
      esac
    '')

    # ========== LLM 分析器 ==========
    (writeShellScriptBin "nixos-llm-analyzer" ''
      #!/usr/bin/env bash
      # nixos-llm-analyzer — NixOS LLM 错误分析器

      set -euo pipefail

      ERROR_LOG="''${1:-}"
      PROVIDER="''${2:---provider glm}"
      MEMORY="/home/charlie/.claude/projects/-home-charlie/memory/lessons-learned.md"
      LOG="/var/log/nixos-llm-analyzer.log"
      TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

      log() { echo "[$TIMESTAMP] $1" | tee -a "$LOG"; }
      log_ok()   { echo -e "\033[0;32m✅ $1\033[0m" | tee -a "$LOG"; }
      log_fail() { echo -e "\033[0;31m❌ $1\033[0m" | tee -a "$LOG"; }
      log_info() { echo -e "\033[0;34mℹ️  $1\033[0m" | tee -a "$LOG"; }

      # 查找错误日志
      if [ -z "$ERROR_LOG" ]; then
          ERROR_LOG=$(ls -t /tmp/nixos-rebuild-safe-*.log 2>/dev/null | head -1)
          if [ -z "$ERROR_LOG" ]; then
              log_fail "未找到错误日志"
              exit 1
          fi
      fi

      log "🔍 LLM 分析错误: $ERROR_LOG"
      ERROR_CONTENT=$(tail -50 "$ERROR_LOG")
      ERROR_HASH=$(echo "$ERROR_CONTENT" | md5sum | cut -d' ' -f1)

      # 检查是否已分析
      if grep -q "$ERROR_HASH" "$MEMORY" 2>/dev/null; then
          log_info "此错误已分析过"
          exit 0
      fi

      # 构建 Prompt
      PROMPT="你是一个 NixOS 系统管理员专家。分析以下错误日志，提供：
1. 错误原因（简洁）
2. 修复步骤（具体命令）
3. 预防措施

错误日志：
\`\`\`bash
$(tail -50 "$ERROR_LOG")
\`\`\`"

      # 调用 LLM（GLM）
      log_info "调用 GLM 分析..."
      RESPONSE=""

      if command -v opencode &>/dev/null; then
          RESPONSE=$(opencode --model glm-4-flash -p "$PROMPT" 2>/dev/null | head -100)
      elif command -v glm &>/dev/null; then
          RESPONSE=$(glm "$PROMPT" 2>/dev/null | head -100)
      else
          log_warn "glm 不可用，跳过 LLM 分析"
          exit 0
      fi

      if [ -n "$RESPONSE" ]; then
          log_ok "LLM 分析完成"
          echo "$RESPONSE"

          # 记录到记忆
          echo "" >> "$MEMORY"
          echo "## $(date '+%Y-%m-%d %H:%M') — LLM 错误分析" >> "$MEMORY"
          echo "**错误哈希**: $ERROR_HASH" >> "$MEMORY"
          echo "" >> "$MEMORY"
          echo "\`\`\`" >> "$MEMORY"
          echo "$RESPONSE" | head -50 >> "$MEMORY"
          echo "\`\`\`" >> "$MEMORY"
      else
          log_fail "LLM 无响应"
      fi
    '')
  ];
}
