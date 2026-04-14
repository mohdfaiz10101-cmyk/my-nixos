{ config, pkgs, lib, ... }:

let
  cfg = config.services.litellm-docker;
in

{
  options.services.litellm-docker = {
    enable = lib.mkEnableOption "LiteLLM API Gateway (Docker Compose)";

    composeDir = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/ai-cluster/litellm";
      description = "LiteLLM docker-compose 所在目录（需包含 docker-compose.yml）";
      example = "/home/charlie/litellm";
    };

    port = lib.mkOption {
      type = lib.types.int;
      default = 4000;
      description = "LiteLLM 服务端口";
    };
  };

  config = lib.mkIf cfg.enable {

    # === systemd 服务定义 ===
    systemd.services.litellm = {
      description = "LiteLLM API Gateway (Docker)";
      documentation = [ "https://docs.litellm.ai" ];

      # 启动顺序：Docker → LiteLLM
      after = [
        "docker.service"
        "network-online.target"
      ];
      wants = [
        "docker.service"
        "network-online.target"
      ];

      # 开机自启
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        # === 基础配置 ===
        Type = "simple";
        Restart = "on-failure";
        RestartSec = "10s";
        RestartMaxDelaySec = "300s";  # 最大重试延迟 5 分钟
        StartLimitBurst = 5;          # 5 次失败后放弃
        StartLimitIntervalSec = "600s"; # 10 分钟内

        # === 工作目录（docker-compose 脚本位置） ===
        WorkingDirectory = cfg.composeDir;

        # === 前置检查 ===
        ExecStartPre = [
          # 检查 docker-compose.yml 存在
          "${pkgs.bash}/bin/bash -c 'test -f ${cfg.composeDir}/docker-compose.yml || (echo \"LiteLLM docker-compose.yml 未找到: ${cfg.composeDir}/docker-compose.yml\"; exit 1)'"

          # 确保容器镜像已拉取（可选，失败不中止）
          "-${pkgs.docker}/bin/docker pull litellm/litellm:latest"
        ];

        # === 启动命令 ===
        ExecStart = "${pkgs.docker-compose}/bin/docker-compose -f docker-compose.yml up";

        # === 停止命令（使用 lib.mkForce 覆盖自动生成的 preStop） ===
        ExecStop = lib.mkForce "${pkgs.docker-compose}/bin/docker-compose -f docker-compose.yml down";

        # === 日志配置 ===
        StandardOutput = "journal";
        StandardError = "journal";

        # === 用户权限 ===
        # 使用 root 确保 Docker socket 访问权限
        User = "root";
        Group = "docker";

        # === 超时配置 ===
        TimeoutStartSec = "300s";  # 启动超时 5 分钟（docker pull 可能耗时）
        TimeoutStopSec = "60s";    # 停止超时 1 分钟

        # === 环境隔离 ===
        PrivateTmp = false;  # 需要访问 docker socket，不隔离 /tmp
        NoNewPrivileges = false;
      };

      # === 启动前检查（Bash 脚本验证） ===
      preStart = ''
        echo "[LiteLLM] 启动前检查..."

        # 检查 1：Docker 是否运行
        if ! ${pkgs.docker}/bin/docker ps > /dev/null 2>&1; then
          echo "[FAIL] Docker 未运行，无法启动 LiteLLM" >&2
          exit 1
        fi

        # 检查 2：docker-compose.yml 是否存在
        if [ ! -f "${cfg.composeDir}/docker-compose.yml" ]; then
          echo "[FAIL] docker-compose.yml 不存在: ${cfg.composeDir}/docker-compose.yml" >&2
          exit 1
        fi

        echo "[OK] 前置检查通过"
      '';

      # === 启动后健康检查 ===
      postStart = ''
        echo "[LiteLLM] 启动后健康检查..."

        # 给容器 15 秒启动时间
        sleep 15

        # 检查端口是否监听
        if ${pkgs.curl}/bin/curl -s http://localhost:${toString cfg.port}/health > /dev/null 2>&1; then
          echo "[OK] LiteLLM 健康检查通过（端口 ${toString cfg.port}）"
        else
          echo "[WARN] 健康检查未通过，可能仍在启动，等待 30 秒后重试..." >&2
          sleep 30
          if ${pkgs.curl}/bin/curl -s http://localhost:${toString cfg.port}/health > /dev/null 2>&1; then
            echo "[OK] 二次健康检查通过"
          else
            echo "[WARN] 二次健康检查失败，可能需要手动检查日志" >&2
          fi
        fi
      '';

    };
  };
}
