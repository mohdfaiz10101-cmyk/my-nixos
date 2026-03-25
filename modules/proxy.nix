# modules/proxy.nix — 3-Tier Proxy Failover System
# ┌─────────────────────────────────────────────────────────────┐
# │ Tier 1: Xray VLESS (Primary, auto-start, user's US server) │
# │ Tier 2: Mihomo (Backup, free proxies from GitHub)          │
# │ Tier 3: Emergency fresh free proxy fetch + reconfigure     │
# │ Watchdog: every 30s, auto-detect failure, switch, self-heal│
# └─────────────────────────────────────────────────────────────┘
# Port 7890 (HTTP) / 7891 (SOCKS5) — only one service runs at a time
# Web UI: http://127.0.0.1:9090/ui (when mihomo is active)
{ config, pkgs, lib, ... }:
let
  # ===== TIER 1: Xray VLESS Config (User's own US server) =====
  xrayConfig = pkgs.writeText "xray-config.json" (builtins.toJSON {
    log = {
      loglevel = "warning";
      access = "none";
    };
    inbounds = [
      {
        tag = "http-in";
        port = 7890;
        protocol = "http";
        listen = "127.0.0.1";
      }
      {
        tag = "socks-in";
        port = 7891;
        protocol = "socks";
        listen = "127.0.0.1";
        settings.udp = true;
      }
    ];
    outbounds = [
      {
        tag = "proxy";
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
      }
      {
        tag = "direct";
        protocol = "freedom";
        settings = {};
      }
      {
        tag = "block";
        protocol = "blackhole";
        settings = {};
      }
    ];
    routing = {
      domainStrategy = "IPIfNonMatch";
      rules = [
        { type = "field"; domain = ["geosite:category-ads-all"]; outboundTag = "block"; }
        { type = "field"; ip = ["geoip:private" "127.0.0.0/8" "192.168.0.0/16" "10.0.0.0/8"]; outboundTag = "direct"; }
        { type = "field"; domain = ["geosite:cn" "geosite:geolocation-cn"]; outboundTag = "direct"; }
        { type = "field"; ip = ["geoip:cn"]; outboundTag = "direct"; }
        { type = "field"; domain = ["geosite:google" "geosite:github" "geosite:telegram" "geosite:openai" "geosite:geolocation-!cn"]; outboundTag = "proxy"; }
      ];
    };
  });

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
        if ${pkgs.curl}/bin/curl -sL -x http://127.0.0.1:7890 --max-time 20 \
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
      -e 's/^external-controller:.*/external-controller: 127.0.0.1:9090/' \
      "$TEMP_DIR/raw.yml"

    # Ensure required fields exist
    grep -q "^mixed-port:" "$TEMP_DIR/raw.yml" || \
      ${pkgs.gnused}/bin/sed -i '1i mixed-port: 7890' "$TEMP_DIR/raw.yml"
    grep -q "^socks-port:" "$TEMP_DIR/raw.yml" || \
      ${pkgs.gnused}/bin/sed -i '/^mixed-port:/a socks-port: 7891' "$TEMP_DIR/raw.yml"
    grep -q "^allow-lan:" "$TEMP_DIR/raw.yml" || \
      ${pkgs.gnused}/bin/sed -i '/^mixed-port:/a allow-lan: true' "$TEMP_DIR/raw.yml"
    grep -q "^external-controller:" "$TEMP_DIR/raw.yml" || \
      ${pkgs.gnused}/bin/sed -i '/^mixed-port:/a external-controller: 127.0.0.1:9090' "$TEMP_DIR/raw.yml"

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
      if ${pkgs.curl}/bin/curl -o /dev/null -s -m 10 --proxy http://127.0.0.1:7890 https://www.google.com; then
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

    test_proxy() {
      local code
      code=$(${pkgs.curl}/bin/curl -s --max-time 10 -x http://127.0.0.1:7890 \
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

    # ---- TIER 1: Restart xray ----
    log "[Tier 1] Restarting xray..."
    systemctl stop mihomo 2>/dev/null || true
    sleep 1
    systemctl restart xray 2>/dev/null || true
    sleep 5
    if test_proxy; then
      echo "xray" > "$STATE_FILE"
      echo "0" > "$FAIL_COUNT_FILE"
      log "[Tier 1] Xray recovered!"
      exit 0
    fi

    # ---- TIER 2: Switch to mihomo ----
    log "[Tier 2] Switching to mihomo..."
    systemctl stop xray 2>/dev/null || true
    sleep 1
    if [ -f /etc/mihomo/config.yaml ] && grep -q "proxies:" /etc/mihomo/config.yaml 2>/dev/null; then
      systemctl start mihomo 2>/dev/null || true
      sleep 5
      if test_proxy; then
        echo "mihomo" > "$STATE_FILE"
        echo "0" > "$FAIL_COUNT_FILE"
        log "[Tier 2] Mihomo working!"
        exit 0
      fi
      systemctl stop mihomo 2>/dev/null || true
    else
      log "[Tier 2] No valid mihomo config"
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
        exit 0
      fi
      systemctl stop mihomo 2>/dev/null || true
    else
      log "[Tier 3] Free proxy fetch failed"
    fi

    # ---- ALL FAILED: keep xray as last resort ----
    log "ALL TIERS FAILED! Starting xray (may recover later)"
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
    echo "--- Xray (Tier 1) ---"
    systemctl is-active xray 2>/dev/null && echo "  Status: RUNNING" || echo "  Status: stopped"
    echo "--- Mihomo (Tier 2) ---"
    systemctl is-active mihomo 2>/dev/null && echo "  Status: RUNNING" || echo "  Status: stopped"
    echo "--- Watchdog ---"
    systemctl is-active proxy-watchdog.timer 2>/dev/null && echo "  Timer: ACTIVE" || echo "  Timer: inactive"
    echo "--- Free Refresh ---"
    systemctl is-active proxy-free-refresh.timer 2>/dev/null && echo "  Timer: ACTIVE" || echo "  Timer: inactive"
    echo ""
    echo "--- Connectivity ---"
    code=$(${pkgs.curl}/bin/curl -s --max-time 5 -x http://127.0.0.1:7890 \
      -o /dev/null -w "%{http_code}" https://www.gstatic.com/generate_204 2>/dev/null) || code="FAIL"
    echo "  HTTP test: $code"
    ip_info=$(${pkgs.curl}/bin/curl -s --max-time 5 -x http://127.0.0.1:7890 \
      https://ipinfo.io/json 2>/dev/null | head -c 200) || ip_info="unavailable"
    echo "  IP Info: $ip_info"
  '';

in
{
  # DO NOT use services.mihomo — causes "Failed to set up credentials" bug
  # Everything is defined manually below for full control

  systemd.tmpfiles.rules = [
    "d /etc/mihomo 0755 root root - -"
  ];

  environment.systemPackages = [
    proxySub
    proxyFreeFetch
    proxyWatchdog
    proxyStatus
    pkgs.xray
    pkgs.mihomo
  ];

  # ===== TIER 1: Xray VLESS (Primary — AUTO-START on boot) =====
  systemd.services.xray = {
    description = "Xray VLESS Proxy (Tier 1 - Primary US)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    conflicts = [ "mihomo.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.xray}/bin/xray run -c ${xrayConfig}";
      Restart = "always";
      RestartSec = 3;
      StartLimitBurst = 50;
      StartLimitIntervalSec = 300;
      LimitNOFILE = 65536;
    };
  };

  # ===== TIER 2: Mihomo (Backup — managed by watchdog) =====
  systemd.services.mihomo = {
    description = "Mihomo Proxy (Tier 2 - Backup)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    conflicts = [ "xray.service" ];
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
      OnBootSec = "30s";
      OnUnitActiveSec = "30s";
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

  networking.firewall.allowedTCPPorts = [ 7890 ];

  networking.proxy = {
    httpProxy = "http://127.0.0.1:7890";
    httpsProxy = "http://127.0.0.1:7890";
    noProxy = "127.0.0.0/8,192.168.0.0/16,10.0.0.0/8,localhost,*.local,11434,18789";
  };
}
