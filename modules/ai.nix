{ config, pkgs, inputs, lib, ... }: {
  # --- 1. Ollama 推理後端 (NVIDIA CUDA 加速) --- 临时禁用以节省磁盘空间
  # services.ollama = {
  #   enable = true;
  #   package = pkgs.ollama-cuda;
  #   host = "0.0.0.0";
  #   port = 11434;
  #   home = "/mnt/ai/ollama";
  #   environmentVariables = {
  #     OLLAMA_KEEP_ALIVE = "5m";
  #     OLLAMA_NUM_PARALLEL = "4";
  #     OLLAMA_MAX_LOADED_MODELS = "2";
  #     OLLAMA_GPU_OVERHEAD = "200";
  #   };
  # };

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
    path = [ (pkgs.python3.withPackages (ps: [ ps.requests ])) pkgs.curl pkgs.jq ];
    serviceConfig = {
      Type = "oneshot";
      User = "charlie";
      ExecStart = "${pkgs.python3.withPackages (ps: [ ps.requests ])}/bin/python3 /etc/nixos/scripts/letta-obsidian-sync.py";
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

  # 注：ollama-cuda, noto-fonts 包已移至 modules/packages.nix
}
