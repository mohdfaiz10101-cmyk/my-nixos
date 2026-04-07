{ config, pkgs, inputs, lib, ... }: {
  # --- 1. Ollama 推理後端 (NVIDIA CUDA 加速) ---
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
    host = "0.0.0.0";
    port = 11434;
    home = "/mnt/ai/ollama";
    environmentVariables = {
      OLLAMA_KEEP_ALIVE = "5m";          # 5 分钟无调用卸载（方案 A 优化，平衡冷启动与内存释放）
      OLLAMA_NUM_PARALLEL = "4";         # 并发处理 4 个请求（提高吞吐量）
      OLLAMA_MAX_LOADED_MODELS = "2";    # 最多加载 2 个模型（GPU 8GB 限制）
      OLLAMA_GPU_OVERHEAD = "200";       # GPU 内存开销预留 200MB
    };
  };

  # 開放防火牆端口
  networking.firewall.allowedTCPPorts = [ 11434 18789 8283 3000 5678 8000 7890 9099 9000 7681 ];

  # --- 2. OpenClaw 閘道器配置 ---



  # --- 3. Dashboard 服務 ---
  systemd.services.nixos-dashboard = let
    pythonEnv = pkgs.python313.withPackages (ps: [ ps.flask ps.requests ]);
  in {
    description = "NixOS System Dashboard";
    after = [ "network.target" "docker.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      User = "charlie";
      ExecStart = "${pythonEnv}/bin/python3 /etc/nixos/dashboard/app.py";
      Restart = "on-failure";
      RestartSec = "5s";
      Environment = "HOME=/home/charlie";
    };
  };

  # --- 4. Letta + Obsidian 自動同步 ---
  systemd.services.letta-sync-obsidian = {
    description = "Sync Letta memory to Obsidian";
    after = [ "network.target" ];
    path = [ pkgs.bash pkgs.curl pkgs.jq ];
    serviceConfig = {
      Type = "oneshot";
      User = "charlie";
      ExecStart = "/run/current-system/sw/bin/bash -c 'cd /etc/nixos && nix-shell -p python313Packages.requests --run \"python3 /etc/nixos/scripts/letta-obsidian-sync.py\"'";
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  systemd.timers.letta-sync-obsidian = {
    description = "Run Letta sync every hour";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "1h";
      AccuracySec = "1min";
    };
  };

  environment.systemPackages = with pkgs; [ ollama ]
    ++ [ pkgs.noto-fonts pkgs.noto-fonts-cjk-serif pkgs.noto-fonts-cjk-sans pkgs.noto-fonts-color-emoji ];
}