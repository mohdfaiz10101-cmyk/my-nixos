{ config, pkgs, lib, ... }:

let
  # MCP 配置文件路径
  mcpConfigPath = "/etc/nixos/modules/mcp-servers.json";
in
{
  # ==========================================
  # 1. 基础依赖与 MCP 工具链部署
  # ==========================================
  environment.systemPackages = with pkgs; [
    nodejs_20           # MCP server-filesystem 需要
    vector              # 结构化日志流管道 ✅ 可用
    osquery             # 系统状态 SQL 查询 ✅ 可用
    git
    curl
    jq
    (writeShellScriptBin "ai-system-info" ''
      echo "=== NixOS System Info for AI ==="
      echo "--- sys-info.txt ---"
      cat /var/lib/ai-context/sys-info.txt 2>/dev/null || echo "Not found"
      echo "--- live-errors.json (last 20 lines) ---"
      tail -20 /var/lib/ai-context/live-errors.json 2>/dev/null || echo "Not found"
      echo "--- dependency-graph.dot (first 50 lines) ---"
      head -50 /var/lib/ai-context/dependency-graph.dot 2>/dev/null || echo "Not found"
    '')
  ];

  # ==========================================
  # 2. 静态上下文捕获：NixOS 依赖图谱与状态快照
  # ==========================================
  systemd.services.ai-system-snapshot = {
    description = "Generate NixOS dependency graph and system snapshot for AI";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = pkgs.writeShellScript "ai-snapshot" ''
        mkdir -p /var/lib/ai-context
        # 导出当前的 NixOS 硬件与系统信息
        ${pkgs.nix-info}/bin/nix-info -m > /var/lib/ai-context/sys-info.txt
        # 导出当前系统的依赖关系图谱 (Graph-RAG 核心原料)
        ${pkgs.nix}/bin/nix-store --query --graph > /var/lib/ai-context/dependency-graph.dot
        # 复制当前激活的配置快照
        cp -rL /etc/nixos /var/lib/ai-context/active-config
        # 设置权限
        chmod -R 755 /var/lib/ai-context
      '';
    };
  };

  # 每小时自动更新一次系统全知视图
  systemd.timers.ai-system-snapshot = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
    };
  };

  # ==========================================
  # 3. 动态上下文捕获：Vector 实时日志流管道
  # ==========================================
  environment.etc."vector/vector.toml".text = ''
    [sources.journald_errors]
    type = "journald"
    include_units = [] # 监听所有服务
    current_boot_only = true
    exclude_units = ["ai-center"]

    [transforms.filter_errors]
    type = "filter"
    inputs = ["journald_errors"]
    condition = 'if .status == "failed" then true else .PRIORITY <= 4 end' # 仅捕获 Warning/Error/Failed

    [sinks.ai_context_stream]
    type = "file"
    inputs = ["filter_errors"]
    path = "/var/lib/ai-context/live-errors.json"
    encoding.codec = "json"
  '';

  systemd.services.vector = {
    description = "Vector Log Streaming for AI Context";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.vector}/bin/vector --config /etc/vector/vector.toml";
      Restart = "always";
      User = "root";
      # 确保 data_dir 存在
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /var/lib/vector /var/lib/ai-context";
    };
  };

  # ==========================================
  # 4. 自动化原子操作：声明式 AI 变更同步
  # ==========================================
  systemd.services.nixos-post-switch-ai-sync = {
    description = "NixOS Post-Switch Git Sync & AI Summary Generation";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "post-switch-git" ''
        cd /etc/nixos
        if [ -d .git ]; then
          ${pkgs.git}/bin/git add .
          # 调用本地轻量 LLM 自动总结本次 Nix 模块变更
          COMMIT_MSG=$(${pkgs.ollama}/bin/ollama run qwen2.5:7b "根据 git diff 简短总结这次 NixOS 配置改了什么，用一行字")
          ${pkgs.git}/bin/git commit -m "NixOS Auto-Switch: $COMMIT_MSG"
        fi
      '';
    };
  };

  # ==========================================
  # 5. MCP Server 配置（供 AI 客户端调用）
  # ==========================================
  # 注意：以下 MCP 服务需要 AI 客户端（如 Claude Desktop）配置
  # 配置文件路径：/etc/nixos/modules/mcp-servers.json
  environment.etc."nixos/mcp-servers.json".text = builtins.toJSON {
    nixos-filesystem = {
      command = "npx";
      args = [ "-y" "@modelcontextprotocol/server-filesystem" "/etc/nixos" "/var/lib/ai-context" ];
    };
    nixos-osquery = {
      # osquery MCP 需要自定义实现，暂时使用直接 osquery 命令
      command = "${pkgs.osquery}/bin/osqueryi";
      args = [ "--json" ];
    };
    local-rag-khoj = {
      # khoj 不在 nixpkgs，暂时注释，待后续添加
      # command = "khoj";
      # args = [ "--api" "localhost:8000" ];
    };
  };

  # ==========================================
  # 6. 系统信息导出脚本（供 AI 直接调用）
  # ==========================================
  # 已合并到上面的 environment.systemPackages
}
