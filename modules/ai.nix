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

  # 1. 設置 OpenClaw 守護進程
  systemd.services.openclaw-gateway = {
    path = [ pkgs.lsof pkgs.nodejs_22 pkgs.coreutils ];
    environment = {
      HOME = lib.mkForce "/var/lib/openclaw";
      OPENCLAW_NIX_MODE = lib.mkForce "1";
      OPENCLAW_CONFIG_PATH = lib.mkForce "/var/lib/openclaw/openclaw.json";
    };
    serviceConfig = {
      User = lib.mkForce "root";
      TimeoutStartSec = 300;
      ExecStartPre = lib.mkForce (pkgs.writeShellScript "openclaw-pre-start" ''
        mkdir -p /var/lib/openclaw
        if [ ! -f /var/lib/openclaw/openclaw.json ]; then
          echo '{"gateway": {"mode": "local"}}' > /var/lib/openclaw/openclaw.json
        fi
      '');
      ExecStart = lib.mkForce "${inputs.openclaw.packages.${pkgs.system}.default}/bin/openclaw gateway --port 18789 --allow-unconfigured --force";
      Restart = lib.mkForce "always";
      RestartSec = lib.mkForce 10;
      StateDirectory = lib.mkForce "openclaw";
      WorkingDirectory = lib.mkForce "/var/lib/openclaw";
    };
  };

  # 2. 佈署 Unstructured API (容器化)
  virtualisation.oci-containers.containers."unstructured-api" = {
    image = "downloads.unstructured.io/unstructured-io/unstructured-api:latest";
    ports = [ "8000:8000" ];
    extraOptions = [ "--pull=always" ];
  };
}
