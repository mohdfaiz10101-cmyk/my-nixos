{ config, pkgs, inputs, lib, ... }: {
  # --- 1. Ollama 推理後端 (NVIDIA CUDA 加速) ---
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
    host = "0.0.0.0";
    port = 11434;
    home = "/mnt/ai/ollama";
  };

  # 開放防火牆端口
  networking.firewall.allowedTCPPorts = [ 11434 18789 8283 3000 5678 8000 ];

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

  environment.systemPackages = with pkgs; [ ollama ];
}