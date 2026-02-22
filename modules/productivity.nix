{ config, pkgs, lib, ... }: {
  # 容錯處理：如果 nixpkgs 真的抓不到 utools，就改裝 appimage-run
  environment.systemPackages = let
    pkgNames = [ "utools" "uTools" "utools-bin" ];
    foundPkg = lib.findFirst (name: builtins.hasAttr name pkgs) null pkgNames;
  in if foundPkg != null then [ pkgs.${foundPkg} ] else [ pkgs.appimage-run pkgs.wget ];

  systemd.services.openclaw-local-patch = {
    description = "Patch OpenClaw for local Ollama";
    before = [ "openclaw-gateway.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "openclaw-patch" ''
        mkdir -p /var/lib/openclaw/data
        cat > /var/lib/openclaw/openclaw.json <<INNER_EOF
{
  "gateway": { "mode": "local", "port": 18789 },
  "models": {
    "default": "llama3",
    "providers": { "ollama": { "base_url": "http://127.0.0.1:11434", "enabled": true } }
  }
}
INNER_EOF
        chown -R root:root /var/lib/openclaw
      '';
    };
  };
}
