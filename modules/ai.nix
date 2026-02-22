{ config, pkgs, inputs, lib, ... }: {
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
  };

  imports = [ 
    inputs.openclaw.nixosModules.openclaw-gateway 
  ];

  services.openclaw-gateway = {
    enable = true;
    port = 18789;
    package = inputs.openclaw.packages.${pkgs.system}.default;
  };

  systemd.services.openclaw-gateway = {
    path = [ pkgs.lsof pkgs.nodejs_22 pkgs.coreutils ];
    environment = {
      HOME = lib.mkForce "/var/lib/openclaw";
      OPENCLAW_NIX_MODE = lib.mkForce "1";
      OPENCLAW_CONFIG_PATH = lib.mkForce "/var/lib/openclaw/openclaw.json";
    };

    serviceConfig = {
      User = lib.mkForce "root";
      Group = lib.mkForce "root";
      
      # 增加啟動超時限制，給 1.4GB 記憶體加載留足時間
      TimeoutStartSec = 300;
      
      ExecStartPre = lib.mkForce (pkgs.writeShellScript "openclaw-pre-start" ''
        mkdir -p /var/lib/openclaw
        if [ ! -f /var/lib/openclaw/openclaw.json ]; then
          echo '{"gateway": {"mode": "local"}}' > /var/lib/openclaw/openclaw.json
        fi
      '');

      # 增加 --verbose 協助排錯
      ExecStart = lib.mkForce 
        "${inputs.openclaw.packages.${pkgs.system}.default}/bin/openclaw gateway --port 18789 --allow-unconfigured --force --verbose";
      
      Restart = lib.mkForce "always";
      RestartSec = lib.mkForce 10;
      StateDirectory = lib.mkForce "openclaw";
      WorkingDirectory = lib.mkForce "/var/lib/openclaw";
    };
  };
}
