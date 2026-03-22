# modules/proxy.nix — mihomo 手動代理方案（無 TUN）
# mihomo 開機自啟，HTTP/SOCKS5 代理 port 7890
# 節點管理用 metacubexd Web UI: http://127.0.0.1:9090/ui
{ config, pkgs, lib, ... }:
let
  # xray 配置（vless+ws+tls 新加坡/美國節點，監聽 7890）
  xrayConfig = pkgs.writeText "xray-config.json" (builtins.toJSON {
    log = {
      loglevel = "error";  # 只記錄嚴重錯誤，忽略正常的 broken pipe 警告
    };
    inbounds = [
      {
        port = 7890;
        protocol = "http";
        listen = "127.0.0.1";
      }
      {
        port = 7891;
        protocol = "socks";
        listen = "127.0.0.1";
        settings.udp = true;
      }
    ];
    outbounds = [{
      protocol = "vless";
      settings.vnext = [{
        address = "cfyes.lxy1015.top";
        port = 443;
        users = [{
          id = "f99d11dd-5f7c-49a3-8ab7-80272d9b887e";
          encryption = "none";
        }];
      }];
      streamSettings = {
        network = "ws";
        security = "tls";
        tlsSettings.serverName = "lx-us1.lxy1015.top";
        wsSettings = {
          path = "/liangxin/us";
          headers.Host = "lx-us1.lxy1015.top";
        };
      };
    }];
  });

  # 訂閱下載腳本：自動追加 &flag=meta 取得 mihomo 格式
  proxySub = pkgs.writeShellScriptBin "proxy-sub" ''
    set -euo pipefail
    SUB_URL="''${1:-}"
    CONFIG="/etc/mihomo/config.yaml"
    if [ -z "$SUB_URL" ]; then
      echo "用法: sudo proxy-sub <訂閱URL>"
      exit 1
    fi
    # 自動追加 flag=meta 參數
    if echo "$SUB_URL" | grep -q '?'; then
      SUB_URL="$SUB_URL&flag=meta"
    else
      SUB_URL="$SUB_URL?flag=meta"
    fi
    echo "正在下載訂閱配置..."
    ${pkgs.curl}/bin/curl -sL "$SUB_URL" -o "$CONFIG.tmp"
    if [ ! -s "$CONFIG.tmp" ]; then
      echo "下載失敗：空文件"
      rm -f "$CONFIG.tmp"
      exit 1
    fi
    if ! grep -q "proxies:" "$CONFIG.tmp"; then
      echo "錯誤：下載的配置不包含 proxies 段，可能格式不對"
      rm -f "$CONFIG.tmp"
      exit 1
    fi
    mv "$CONFIG.tmp" "$CONFIG"
    # Docker 容器需要通過代理訪問外部 API，確保 allow-lan 開啟
    ${pkgs.gnused}/bin/sed -i 's/^allow-lan: false/allow-lan: true/' "$CONFIG"
    chmod 600 "$CONFIG"
    echo "配置已更新: $CONFIG"
    echo "重啟 mihomo..."
    systemctl restart mihomo
    sleep 2
    if systemctl is-active --quiet mihomo; then
      echo "mihomo 運行中。測試代理..."
      if ${pkgs.curl}/bin/curl -o /dev/null -s -m 10 --proxy http://127.0.0.1:7890 https://www.google.com; then
        echo "代理正常工作！"
      else
        echo "警告：代理已啟動但無法連接 Google，請檢查節點"
      fi
    else
      echo "錯誤：mihomo 啟動失敗，請檢查: journalctl -u mihomo -e"
    fi
  '';
in
{
  # --- mihomo 備用（目前停用，節點不可用）---
  # 若需重新啟用：改為 enable = true 並停用 xray
  services.mihomo = {
    enable = false;
    configFile = "/etc/mihomo/config.yaml";
    webui = pkgs.metacubexd;
    tunMode = false;
  };

  # 確保 mihomo 配置目錄存在
  systemd.tmpfiles.rules = [
    "d /etc/mihomo 0700 root root - -"
  ];

  environment.systemPackages = [
    proxySub
    pkgs.xray
  ];

  # --- xray vless+ws+tls 代理（開機自啟，監聽 7890）---
  systemd.services.xray = {
    description = "Xray VLESS Proxy";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.xray}/bin/xray run -c ${xrayConfig}";
      Restart = "on-failure";
      RestartSec = 5;
      LimitNOFILE = 65536;
      StandardOutput = "null";  # 完全禁用標準輸出
      StandardError = "null";   # 完全禁用錯誤輸出（包括 connection 日誌）
    };
  };

  # 開放 7890 給 Docker 容器訪問代理（allow-lan 需配合防火牆）
  networking.firewall.allowedTCPPorts = [ 7890 ];

  # 系統級代理環境變數（讓 git/curl 等自動走代理）
  networking.proxy = {
    httpProxy = "http://127.0.0.1:7890";
    httpsProxy = "http://127.0.0.1:7890";
    noProxy = "127.0.0.0/8,192.168.0.0/16,10.0.0.0/8,localhost,*.local,11434,18789";
  };
}
