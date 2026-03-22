{ config, pkgs, inputs, lib, ... }: {
  # --- 1. Ollama 推理後端 (NVIDIA CUDA 加速) ---
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
    host = "0.0.0.0";
    port = 11434;
    home = "/mnt/ai/ollama";
    environmentVariables = {
      OLLAMA_KEEP_ALIVE = "30m";   # 30 分鐘無調用才卸載模型（冷啟動要 50 秒太慢）
    };
  };

  # 開放防火牆端口
  networking.firewall.allowedTCPPorts = [ 11434 18789 8283 3000 5678 8000 7890 9099 ];

  # --- 2. OpenClaw 閘道器配置 ---
  imports = [ 
    inputs.openclaw.nixosModules.openclaw-gateway 
  ];

  services.openclaw-gateway = {
    enable = true;
    port = 18789;
    package = inputs.openclaw.packages.${pkgs.system}.default;
  };

  # OpenClaw 守護進程 (聲明式重構版)
  systemd.services.openclaw-gateway = {
    path = [ pkgs.lsof pkgs.nodejs_22 pkgs.coreutils ];
    after = [ "network.target" "ollama.service" ];
    
    environment = {
      HOME = lib.mkForce "/var/lib/openclaw";
      OPENCLAW_NIX_MODE = lib.mkForce "1";
      OPENCLAW_CONFIG_PATH = lib.mkForce (pkgs.writeText "openclaw-config.json" ''
        {
          "gateway": { "mode": "local", "port": 18789 },
          "models": {
            "default": "qwen3:8b",
            "providers": { "ollama": { "base_url": "http://127.0.0.1:11434", "enabled": true } }
          }
        }
      '');
    };
    
    serviceConfig = {
      User = lib.mkForce "root";
      ExecStartPre = lib.mkForce (pkgs.writeShellScript "openclaw-pre-start" ''
        mkdir -p /var/lib/openclaw
        chown -R root:root /var/lib/openclaw
      '');
      ExecStart = lib.mkForce "${inputs.openclaw.packages.${pkgs.system}.default}/bin/openclaw gateway --port 18789 --allow-unconfigured";
      Restart = lib.mkForce "always";
      StateDirectory = lib.mkForce "openclaw";
      WorkingDirectory = lib.mkForce "/var/lib/openclaw";
    };
  };

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