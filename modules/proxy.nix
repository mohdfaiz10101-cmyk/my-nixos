# modules/proxy.nix — 3-Tier Proxy Failover System
# ┌─────────────────────────────────────────────────────────────┐
# │ Tier 2: Xray VLESS (Backup, user's US server) │
# │ Tier 1: Mihomo (Primary, free proxies from GitHub)          │
# │ Tier 3: Emergency fresh free proxy fetch + reconfigure     │
# │ Watchdog: every 30s, auto-detect failure, switch, self-heal│
# └─────────────────────────────────────────────────────────────┘
# Port 7890 (HTTP) / 7891 (SOCKS5) — only one service runs at a time
# Web UI: http://127.0.0.1:9091/ui (when mihomo is active)
{ config, pkgs, lib, ... }:
let
  secretsFile = ../secrets.nix;
  secrets = if builtins.pathExists secretsFile then import secretsFile else {
    vless-uuid = "";
    proxy-server-address = "";
    proxy-server-port = 443;
    proxy-tls-serverName = "";
    proxy-ws-path = "";
    proxy-ws-host = "";
  };
  # sops secrets paths (available at runtime after activation)
  sopsSecrets = config.sops.secrets;

  # Xray config generator — runs at service start with decrypted sops values
  xrayConfigGenerator = pkgs.writeShellScript "xray-config-gen" ''
    set -euo pipefail
    UUID=$(cat "${sopsSecrets.vless-uuid.path}")
    ADDR=$(cat "${sopsSecrets.proxy-server-address.path}")
    PORT=$(cat "${sopsSecrets.proxy-server-port.path}")
    TLS_SN=$(cat "${sopsSecrets.proxy-tls-serverName.path}")
    WS_PATH=$(cat "${sopsSecrets.proxy-ws-path.path}")
    WS_HOST=$(cat "${sopsSecrets.proxy-ws-host.path}")

    ${pkgs.jq}/bin/jq -n \
      --arg uuid "$UUID" \
      --arg addr "$ADDR" \
      --argjson port "$PORT" \
      --arg tls_sn "$TLS_SN" \
      --arg ws_path "$WS_PATH" \
      --arg ws_host "$WS_HOST" \
    '{
      log: { loglevel: "warning", access: "none" },
      dns: {
        servers: [
          { address: "8.8.8.8", domains: ["geosite:geolocation-!cn"] },
          { address: "1.1.1.1", domains: ["geosite:geolocation-!cn"] },
          { address: "223.5.5.5", domains: ["geosite:cn", "geosite:geolocation-cn"] },
          "localhost"
        ],
        queryStrategy: "UseIPv4"
      },
      inbounds: [
        { tag: "http-in", port: 7890, protocol: "http", listen: "0.0.0.0" },
        { tag: "socks-in", port: 7891, protocol: "socks", listen: "0.0.0.0", settings: { udp: true } }
      ],
      outbounds: [
        {
          tag: "proxy",
          protocol: "vless",
          settings: { vnext: [{ address: $addr, port: ($port | tonumber), users: [{ id: $uuid, encryption: "none" }] }] },
          streamSettings: {
            network: "ws",
            security: "tls",
            tlsSettings: { serverName: $tls_sn },
            wsSettings: { path: $ws_path, headers: { Host: $ws_host } }
          }
        },
        { tag: "direct", protocol: "freedom", settings: {} },
        { tag: "block", protocol: "blackhole", settings: {} }
      ],
      routing: {
        domainStrategy: "IPIfNonMatch",
        rules: [
          { type: "field", domain: ["geosite:category-ads-all"], outboundTag: "block" },
          { type: "field", ip: ["geoip:private","127.0.0.0/8","192.168.0.0/16","10.0.0.0/8"], outboundTag: "direct" },
          { type: "field", domain: ["geosite:cn","geosite:geolocation-cn"], outboundTag: "direct" },
          { type: "field", ip: ["geoip:cn"], outboundTag: "direct" },
          { type: "field", domain: ["domain:gemini.google.com","domain:generativelanguage.googleapis.com","domain:aistudio.google.com","domain:bard.google.com","domain:anthropic.com","domain:claude.ai","geosite:google","geosite:github","geosite:telegram","geosite:openai","geosite:geolocation-!cn"], outboundTag: "proxy" }
        ]
      }
    }' > /run/xray-config.json
  '';

  # ===== Free proxy fetcher: downloads clash configs from GitHub =====
  proxyFreeFetch = pkgs.writeShellScriptBin "proxy-free-fetch" ''
    set -euo pipefail
    MIHOMO_DIR="/etc/mihomo"
    CONFIG="$MIHOMO_DIR/config.yaml"
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT

    log() { echo "$(date '+%H:%M:%S') [free-fetch] $1"; }

    # GitHub free clash subscription sources (multiple for redundancy)
    URLS=(
      "https://raw.githubusercontent.com/peasoft/NoMoreWalls/master/list.yml"
      "https://raw.githubusercontent.com/ermaozi/get_subscribe/main/subscribe/clash.yml"
      "https://raw.githubusercontent.com/mfuu/v2ray/master/clash.yaml"
      "https://raw.githubusercontent.com/aiboboxx/clashfree/main/clash.yml"
    )

    # GitHub mirror prefixes for China access
    MIRRORS=(
      ""
      "https://ghfast.top/"
      "https://gh-proxy.com/"
      "https://mirror.ghproxy.com/"
    )

    download_success=false

    for url in "''${URLS[@]}"; do
      [ "$download_success" = "true" ] && break
      for mirror in "''${MIRRORS[@]}"; do
        target="''${mirror}''${url}"
        log "Trying: $target"
        # Try direct (no proxy)
        if ${pkgs.curl}/bin/curl -sL --noproxy '*' --max-time 30 \
          -H "User-Agent: clash-verge/v2.0" \
          "$target" -o "$TEMP_DIR/raw.yml" 2>/dev/null; then
          if [ -s "$TEMP_DIR/raw.yml" ] && grep -q "proxies:" "$TEMP_DIR/raw.yml" 2>/dev/null; then
            download_success=true
            log "OK (direct): $target"
            break
          fi
        fi
        # Try via current proxy
        if ${pkgs.curl}/bin/curl -sL -x http://0.0.0.0:7890 --max-time 20 \
          -H "User-Agent: clash-verge/v2.0" \
          "$target" -o "$TEMP_DIR/raw.yml" 2>/dev/null; then
          if [ -s "$TEMP_DIR/raw.yml" ] && grep -q "proxies:" "$TEMP_DIR/raw.yml" 2>/dev/null; then
            download_success=true
            log "OK (proxy): $target"
            break
          fi
        fi
      done
    done

    if [ "$download_success" != "true" ]; then
      log "ERROR: All download sources failed!"
      exit 1
    fi

    log "Downloaded config, processing..."

    # Fix config: set correct ports and settings
    ${pkgs.gnused}/bin/sed -i \
      -e 's/^mixed-port:.*/mixed-port: 7890/' \
      -e 's/^port:.*/mixed-port: 7890/' \
      -e 's/^socks-port:.*/socks-port: 7891/' \
      -e 's/^allow-lan:.*/allow-lan: true/' \
      -e 's/^external-controller:.*/external-controller: 127.0.0.1:9091/' \
      "$TEMP_DIR/raw.yml"

    # Ensure required fields exist
    grep -q "^mixed-port:" "$TEMP_DIR/raw.yml" || \
      ${pkgs.gnused}/bin/sed -i '1i mixed-port: 7890' "$TEMP_DIR/raw.yml"
    grep -q "^socks-port:" "$TEMP_DIR/raw.yml" || \
      ${pkgs.gnused}/bin/sed -i '/^mixed-port:/a socks-port: 7891' "$TEMP_DIR/raw.yml"
    grep -q "^allow-lan:" "$TEMP_DIR/raw.yml" || \
      ${pkgs.gnused}/bin/sed -i '/^mixed-port:/a allow-lan: true' "$TEMP_DIR/raw.yml"
    grep -q "^external-controller:" "$TEMP_DIR/raw.yml" || \
      ${pkgs.gnused}/bin/sed -i '/^mixed-port:/a external-controller: 127.0.0.1:9091' "$TEMP_DIR/raw.yml"

    # Download Country.mmdb if missing (needed for GEOIP rules)
    if [ ! -f "$MIHOMO_DIR/Country.mmdb" ]; then
      log "Downloading Country.mmdb..."
      for mirror in "''${MIRRORS[@]}"; do
        mmdb_url="''${mirror}https://github.com/Dreamacro/maxmind-geoip/releases/latest/download/Country.mmdb"
        if ${pkgs.curl}/bin/curl -sL --noproxy '*' --max-time 60 "$mmdb_url" \
          -o "$MIHOMO_DIR/Country.mmdb" 2>/dev/null; then
          if [ -s "$MIHOMO_DIR/Country.mmdb" ]; then
            log "Country.mmdb downloaded"
            break
          fi
        fi
      done
      # If MMDB still missing, strip GEOIP/GEOSITE rules to prevent crash
      if [ ! -f "$MIHOMO_DIR/Country.mmdb" ] || [ ! -s "$MIHOMO_DIR/Country.mmdb" ]; then
        log "MMDB download failed, stripping GEO rules..."
        ${pkgs.gnused}/bin/sed -i '/GEOIP/d; /GEOSITE/d' "$TEMP_DIR/raw.yml"
        rm -f "$MIHOMO_DIR/Country.mmdb"
      fi
    fi

    # Count proxies
    proxy_count=$(grep -c "^  - " "$TEMP_DIR/raw.yml" 2>/dev/null || echo "0")
    log "Config has approximately $proxy_count proxy entries"

    if [ "$proxy_count" -lt 1 ]; then
      log "ERROR: No proxies found in config"
      exit 1
    fi

    # Backup old config and install new one
    [ -f "$CONFIG" ] && cp "$CONFIG" "$CONFIG.bak" 2>/dev/null || true
    cp "$TEMP_DIR/raw.yml" "$CONFIG"
    chmod 644 "$CONFIG"
    log "Config installed: $CONFIG (~$proxy_count proxies)"
  '';

  # ===== Subscription downloader (manual use) =====
  proxySub = pkgs.writeShellScriptBin "proxy-sub" ''
    set -euo pipefail
    SUB_URL="''${1:-}"
    CONFIG="/etc/mihomo/config.yaml"
    if [ -z "$SUB_URL" ]; then
      echo "用法: sudo proxy-sub <订阅URL>"
      exit 1
    fi
    if echo "$SUB_URL" | grep -q '?'; then
      SUB_URL="$SUB_URL&flag=meta"
    else
      SUB_URL="$SUB_URL?flag=meta"
    fi
    echo "正在下载订阅配置..."
    ${pkgs.curl}/bin/curl -sL --noproxy '*' "$SUB_URL" -o "$CONFIG.tmp"
    if [ ! -s "$CONFIG.tmp" ]; then
      echo "下载失败：空文件"
      rm -f "$CONFIG.tmp"
      exit 1
    fi
    if ! grep -q "proxies:" "$CONFIG.tmp"; then
      echo "错误：下载的配置不包含 proxies 段"
      rm -f "$CONFIG.tmp"
      exit 1
    fi
    mv "$CONFIG.tmp" "$CONFIG"
    ${pkgs.gnused}/bin/sed -i 's/^allow-lan: false/allow-lan: true/' "$CONFIG"
    chmod 644 "$CONFIG"
    echo "配置已更新: $CONFIG"
    echo "重启 mihomo..."
    systemctl restart mihomo
    sleep 3
    if systemctl is-active --quiet mihomo; then
      echo "mihomo 运行中。测试代理..."
      if ${pkgs.curl}/bin/curl -o /dev/null -s -m 10 --proxy http://0.0.0.0:7890 https://www.google.com; then
        echo "代理正常工作！"
      else
        echo "警告：mihomo 已启动但无法连接 Google，请检查节点"
      fi
    else
      echo "错误：mihomo 启动失败，请检查: journalctl -u mihomo -e"
    fi
  '';

  # ===== 3-Tier Watchdog: auto-detect, auto-switch, self-heal =====
  proxyWatchdog = pkgs.writeShellScriptBin "proxy-watchdog" ''
    set -euo pipefail
    STATE_FILE="/run/proxy-watchdog-state"
    FAIL_COUNT_FILE="/run/proxy-watchdog-fails"

    log() { echo "$(date '+%H:%M:%S') [watchdog] $1"; }

    # DNS pre-check: ensure proxy domain resolves
    dns_precheck() {
      local proxy_domain
      proxy_domain=$(cat /run/xray-config.json 2>/dev/null | ${pkgs.jq}/bin/jq -r '.outbounds[0].settings.vnext[0].address' 2>/dev/null || echo "")
      if [ -z "$proxy_domain" ]; then return 0; fi

      # Test current DNS
      if ${pkgs.dnsutils}/bin/nslookup "$proxy_domain" >/dev/null 2>&1; then
        return 0
      fi

      log "DNS FAILED for $proxy_domain! Injecting fallback DNS..."
      cp /etc/resolv.conf /run/resolv.conf.bak 2>/dev/null || true
      {
        echo "nameserver 8.8.8.8"
        echo "nameserver 1.1.1.1"
        echo "nameserver 223.5.5.5"
        cat /etc/resolv.conf 2>/dev/null
      } > /run/resolv.conf.tmp
      cp /run/resolv.conf.tmp /etc/resolv.conf 2>/dev/null || true

      if ${pkgs.dnsutils}/bin/nslookup "$proxy_domain" >/dev/null 2>&1; then
        log "DNS recovered with fallback servers"
        return 0
      fi
      log "DNS still failing after fallback injection"
      return 1
    }

    notify_tier() {
      DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus" \
        ${pkgs.libnotify}/bin/notify-send -u critical "Proxy Watchdog" "$1" 2>/dev/null || true
    }

    test_proxy() {
      local code
      code=$(${pkgs.curl}/bin/curl -s --max-time 10 -x http://0.0.0.0:7890 \
        -o /dev/null -w "%{http_code}" https://www.gstatic.com/generate_204 2>/dev/null) || true
      [[ "$code" =~ ^(200|204|301|302)$ ]]
    }

    CURRENT=$(cat "$STATE_FILE" 2>/dev/null || echo "xray")
    FAILS=$(cat "$FAIL_COUNT_FILE" 2>/dev/null || echo "0")

    # ---- PROXY IS WORKING ----
    if test_proxy; then
      echo "0" > "$FAIL_COUNT_FILE"

      # If not on tier 1, periodically try to recover to xray
      if [ "$CURRENT" != "xray" ]; then
        LAST_CHANGE=$(stat -c %Y "$STATE_FILE" 2>/dev/null || echo 0)
        NOW=$(date +%s)
        ELAPSED=$((NOW - LAST_CHANGE))

        if [ "$ELAPSED" -gt 300 ]; then
          log "Proxy OK on $CURRENT, trying to recover to xray (tier 1)..."
          systemctl stop mihomo 2>/dev/null || true
          sleep 2
          systemctl start xray 2>/dev/null || true
          sleep 5
          if test_proxy; then
            echo "xray" > "$STATE_FILE"
            log "Recovered to xray (tier 1)!"
          else
            log "Xray recovery failed, back to $CURRENT"
            systemctl stop xray 2>/dev/null || true
            sleep 2
            systemctl start mihomo 2>/dev/null || true
            sleep 3
            touch "$STATE_FILE"
          fi
        fi
      fi
      exit 0
    fi

    # ---- PROXY IS DOWN ----
    FAILS=$((FAILS + 1))
    echo "$FAILS" > "$FAIL_COUNT_FILE"
    log "PROXY DOWN! Tier: $CURRENT, fails: $FAILS"

    # DNS pre-check before restart attempts
    dns_precheck || log "WARNING: DNS precheck failed, continuing anyway"

    # ---- TIER 2: Restart xray ----
    log "[Tier 2] Restarting xray..."
    systemctl stop mihomo 2>/dev/null || true
    sleep 1
    systemctl restart xray 2>/dev/null || true
    sleep 5
    if test_proxy; then
      echo "xray" > "$STATE_FILE"
      echo "0" > "$FAIL_COUNT_FILE"
      log "[Tier 2] Xray recovered!"
      notify_tier "Tier 2: Xray recovered"
      exit 0
    fi

    # ---- TIER 1: Switch to mihomo ----
    log "[Tier 1] Switching to mihomo..."
    systemctl stop xray 2>/dev/null || true
    sleep 1
    if [ -f /etc/mihomo/config.yaml ] && grep -q "proxies:" /etc/mihomo/config.yaml 2>/dev/null; then
      systemctl start mihomo 2>/dev/null || true
      sleep 5
      if test_proxy; then
        echo "mihomo" > "$STATE_FILE"
        echo "0" > "$FAIL_COUNT_FILE"
        log "[Tier 1] Mihomo working!"
        notify_tier "Tier 1: Switched to Mihomo"
        exit 0
      fi
      systemctl stop mihomo 2>/dev/null || true
    else
      log "[Tier 1] No valid mihomo config"
    fi

    # ---- TIER 3: Fetch fresh free proxies ----
    log "[Tier 3] Fetching fresh free proxies..."
    if proxy-free-fetch 2>/dev/null; then
      sleep 1
      systemctl start mihomo 2>/dev/null || true
      sleep 5
      if test_proxy; then
        echo "free" > "$STATE_FILE"
        echo "0" > "$FAIL_COUNT_FILE"
        log "[Tier 3] Fresh free proxies working!"
        notify_tier "Tier 3: Using fresh free proxies"
        exit 0
      fi
      systemctl stop mihomo 2>/dev/null || true
    else
      log "[Tier 3] Free proxy fetch failed"
    fi

    # ---- ALL FAILED: keep xray as last resort ----
    log "ALL TIERS FAILED! Starting xray (may recover later)"
    notify_tier "ALL TIERS FAILED! Proxy is down"
    systemctl start xray 2>/dev/null || true
    echo "xray" > "$STATE_FILE"

    if [ "$FAILS" -ge 10 ]; then
      log "10+ fails! Full reset on next cycle"
      echo "0" > "$FAIL_COUNT_FILE"
    fi
  '';

  # ===== Proxy status command =====
  proxyStatus = pkgs.writeShellScriptBin "proxy-status" ''
    echo "=== Proxy 3-Tier Status ==="
    CURRENT=$(cat /run/proxy-watchdog-state 2>/dev/null || echo "unknown")
    FAILS=$(cat /run/proxy-watchdog-fails 2>/dev/null || echo "0")
    echo "Active tier: $CURRENT"
    echo "Consecutive fails: $FAILS"
    echo ""
    echo "--- Xray (Tier 2) ---"
    systemctl is-active xray 2>/dev/null && echo "  Status: RUNNING" || echo "  Status: stopped"
    echo "--- Mihomo (Tier 1) ---"
    systemctl is-active mihomo 2>/dev/null && echo "  Status: RUNNING" || echo "  Status: stopped"
    echo "--- Watchdog ---"
    systemctl is-active proxy-watchdog.timer 2>/dev/null && echo "  Timer: ACTIVE" || echo "  Timer: inactive"
    echo "--- Free Refresh ---"
    systemctl is-active proxy-free-refresh.timer 2>/dev/null && echo "  Timer: ACTIVE" || echo "  Timer: inactive"
    echo ""
    echo "--- Connectivity ---"
    code=$(${pkgs.curl}/bin/curl -s --max-time 5 -x http://0.0.0.0:7890 \
      -o /dev/null -w "%{http_code}" https://www.gstatic.com/generate_204 2>/dev/null) || code="FAIL"
    echo "  HTTP test: $code"
    ip_info=$(${pkgs.curl}/bin/curl -s --max-time 5 -x http://0.0.0.0:7890 \
      https://ipinfo.io/json 2>/dev/null | head -c 200) || ip_info="unavailable"
    echo "  IP Info: $ip_info"
  '';

in
{
  # --- sops secrets for proxy ---
  sops.secrets = {
    vless-uuid = {};
    proxy-server-address = {};
    proxy-server-port = {};
    proxy-tls-serverName = {};
    proxy-ws-path = {};
    proxy-ws-host = {};
  };

  # DO NOT use services.mihomo — causes "Failed to set up credentials" bug
  # Everything is defined manually below for full control

  systemd.tmpfiles.rules = [
    "d /etc/mihomo 0755 root root - -"
  ];

  # 注：xray, mihomo 包已移至 modules/packages.nix，此处只安装本地脚本包
  environment.systemPackages = [
    proxySub
    proxyFreeFetch
    proxyWatchdog
    proxyStatus
  ];

  # ===== TIER 2: Xray VLESS (Backup — managed by watchdog, NOT auto-started) =====
  # 注意：故意不设 wantedBy，防止 nixos-rebuild switch 在 mihomo 运行时启动 xray
  # 触发 Conflicts 停掉当前代理（Claude 断线 bug）。watchdog 负责启停。
  systemd.services.xray = {
    description = "Xray VLESS Proxy (Tier 2 - Backup US)";
    after = [ "network-online.target" "sops-nix.service" ];
    wants = [ "network-online.target" "sops-nix.service" ];
    conflicts = [ "mihomo.service" ];
    restartIfChanged = false;  # prevent nixos-rebuild from killing proxy mid-session
    unitConfig = {
      StartLimitBurst = 3;
      StartLimitIntervalSec = 300;
    };
    serviceConfig = {
      ExecStartPre = "${xrayConfigGenerator}";
      ExecStart = "${pkgs.xray}/bin/xray run -c /run/xray-config.json";
      Restart = "on-failure";
      RestartSec = 10;
      LimitNOFILE = 65536;
    };
  };

  # ===== TIER 1: Mihomo (Primary — managed by watchdog) =====
  systemd.services.mihomo = {
    description = "Mihomo Proxy (Tier 1 - Primary)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    conflicts = [ "xray.service" ];
    restartIfChanged = false;  # prevent nixos-rebuild from killing proxy mid-session
    serviceConfig = {
      ExecStart = "${pkgs.mihomo}/bin/mihomo -d /etc/mihomo -f /etc/mihomo/config.yaml";
      Restart = "on-failure";
      RestartSec = 5;
      WorkingDirectory = "/etc/mihomo";
      LimitNOFILE = 65536;
    };
  };

  # ===== Watchdog: every 30s health check =====
  systemd.services.proxy-watchdog = {
    description = "Proxy 3-tier failover watchdog";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [
      pkgs.curl pkgs.coreutils pkgs.systemd pkgs.gnugrep pkgs.gnused
      pkgs.dnsutils pkgs.libnotify pkgs.jq
      proxyFreeFetch
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${proxyWatchdog}/bin/proxy-watchdog";
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  systemd.timers.proxy-watchdog = {
    description = "Proxy watchdog timer (every 30s)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "15s";
      OnUnitActiveSec = "15s";
      AccuracySec = "5s";
    };
  };

  # ===== Periodic free proxy refresh (every 6h) =====
  systemd.services.proxy-free-refresh = {
    description = "Refresh free proxy pool from GitHub";
    path = [ pkgs.curl pkgs.coreutils pkgs.gnugrep pkgs.gnused ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${proxyFreeFetch}/bin/proxy-free-fetch";
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  systemd.timers.proxy-free-refresh = {
    description = "Refresh free proxies every 6h";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "6h";
      AccuracySec = "5min";
    };
  };

  # 7890 仅本地使用，防火墙不对外暴露

  networking.proxy = {
    httpProxy = "http://127.0.0.1:7890";
    httpsProxy = "http://127.0.0.1:7890";
    noProxy = "127.0.0.0/8,192.168.0.0/16,10.0.0.0/8,100.100.100.100,localhost,*.local,*.ts.net,open.bigmodel.cn,11434,18789";
  };
}
