#!/usr/bin/env bash
# Unified health aggregator with de-duplication and cooldown.
set -u

STATE_DIR="/var/lib/health-aggregator"
REPORT_FILE="$STATE_DIR/latest-report.txt"
LAST_HASH_FILE="$STATE_DIR/last-hash"
LAST_NOTIFY_FILE="$STATE_DIR/last-notify-ts"
DAILY_STAMP_FILE="$STATE_DIR/last-daily"
COOLDOWN_SEC="${HEALTH_AGGREGATOR_COOLDOWN_SEC:-1800}"
HOST_NAME="$(cat /etc/hostname 2>/dev/null || echo nixos)"

mkdir -p "$STATE_DIR" 2>/dev/null || true

now_ts() { date +%s; }
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

read_secret() {
  local env_name="$1"
  local file="$2"
  local value="${!env_name:-}"
  if [ -z "$value" ] && [ -r "$file" ]; then
    value="$(tr -d '\r\n' < "$file" 2>/dev/null || true)"
  fi
  printf '%s' "$value"
}

http_ok() {
  timeout 6 curl -fsS --connect-timeout 2 --max-time 5 "$1" >/dev/null 2>&1
}

tcp_ok() {
  timeout 3 bash -c "</dev/tcp/127.0.0.1/$1" >/dev/null 2>&1
}

docker_running() {
  docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null | grep -qx true
}

append_status() {
  local level="$1"
  local item="$2"
  local detail="$3"
  printf '%s\t%s\t%s\n' "$level" "$item" "$detail" >> "$REPORT_FILE.tmp"
}

send_telegram() {
  local text="$1"
  local token chat_id
  token="$(read_secret TELEGRAM_BOT_TOKEN /home/charlie/.config/telegram-bot-token)"
  chat_id="$(read_secret TELEGRAM_CHAT_ID /home/charlie/.config/telegram-chat-id)"
  [ -n "$token" ] || token="$(read_secret TG_BOT_TOKEN /home/charlie/.config/telegram-bot-token)"
  [ -n "$chat_id" ] || chat_id="$(read_secret TG_CHAT_ID /home/charlie/.config/telegram-chat-id)"
  [ -n "$token" ] && [ -n "$chat_id" ] || return 0
  curl -fsS --connect-timeout 5 --max-time 10 \
    "https://api.telegram.org/bot${token}/sendMessage" \
    -d "chat_id=${chat_id}" \
    --data-urlencode "text=${text}" >/dev/null 2>&1 || true
}

daily_maintenance() {
  local today backup_dir backup_file
  today="$(date '+%Y-%m-%d')"
  [ "$(cat "$DAILY_STAMP_FILE" 2>/dev/null || true)" = "$today" ] && return 0
  backup_dir="/mnt/data/nixos-backups"
  backup_file="$backup_dir/nixos-config-${today}.tar.gz"
  mkdir -p "$backup_dir" 2>/dev/null || true
  if [ ! -f "$backup_file" ]; then
    tar czf "$backup_file" --exclude=node_modules --exclude=result --exclude=.git \
      -C /etc nixos 2>/dev/null || true
  fi
  find "$backup_dir" -name "nixos-config-*.tar.gz" -mtime +3 -delete 2>/dev/null || true
  date '+%Y-%m-%d' > "$DAILY_STAMP_FILE" 2>/dev/null || true
}

main() {
  : > "$REPORT_FILE.tmp"

  root_usage="$(df / --output=pcent 2>/dev/null | tail -1 | tr -d ' %' || echo 0)"
  ai_usage="$(df /mnt/ai --output=pcent 2>/dev/null | tail -1 | tr -d ' %' || echo 0)"
  [ "${root_usage:-0}" -lt 85 ] && append_status OK disk-root "/ ${root_usage}%" || append_status WARN disk-root "/ ${root_usage}%"
  [ "${ai_usage:-0}" -lt 90 ] && append_status OK disk-ai "/mnt/ai ${ai_usage}%" || append_status WARN disk-ai "/mnt/ai ${ai_usage}%"

  failed_system="$(systemctl --failed --no-legend 2>/dev/null | wc -l | tr -d ' ')"
  failed_user="$(runuser -u charlie -- systemctl --user --failed --no-legend 2>/dev/null | wc -l | tr -d ' ')"
  [ "${failed_system:-0}" -eq 0 ] && append_status OK systemd-system "failed=0" || append_status WARN systemd-system "failed=${failed_system}"
  [ "${failed_user:-0}" -eq 0 ] && append_status OK systemd-user "failed=0" || append_status WARN systemd-user "failed=${failed_user}"

  http_ok http://127.0.0.1:8283/ && append_status OK letta "http 8283" || append_status WARN letta "http 8283 unavailable"
  http_ok http://127.0.0.1:4000/health/readiness && append_status OK litellm "readiness 4000" || append_status WARN litellm "readiness 4000 unavailable"
  tcp_ok 9900 && append_status OK agi-gateway "tcp 9900" || append_status WARN agi-gateway "tcp 9900 unavailable"
  tcp_ok 7890 && append_status OK mihomo "tcp 7890" || append_status WARN mihomo "tcp 7890 unavailable"

  for c in letta letta-db letta-chromadb litellm-litellm litellm-redis; do
    docker_running "$c" && append_status OK "docker-$c" "running" || append_status WARN "docker-$c" "not running"
  done

  daily_maintenance

  sort "$REPORT_FILE.tmp" > "$REPORT_FILE"
  rm -f "$REPORT_FILE.tmp"

  warn_count="$(awk '$1 != "OK" { n++ } END { print n + 0 }' "$REPORT_FILE")"
  report_hash="$(sha256sum "$REPORT_FILE" | awk '{print $1}')"
  last_hash="$(cat "$LAST_HASH_FILE" 2>/dev/null || true)"
  last_notify="$(cat "$LAST_NOTIFY_FILE" 2>/dev/null || echo 0)"
  now="$(now_ts)"

  log "health aggregation finished: warnings=${warn_count}, hash=${report_hash}"
  cat "$REPORT_FILE"

  if [ "$warn_count" -gt 0 ]; then
    if [ "$report_hash" != "$last_hash" ] || [ $((now - last_notify)) -ge "$COOLDOWN_SEC" ]; then
      summary="$(awk '$1 != "OK" { print "- " $2 ": " $3 }' "$REPORT_FILE" | head -12)"
      send_telegram "${HOST_NAME} health degraded (${warn_count})
${summary}
report: ${REPORT_FILE}"
      printf '%s' "$now" > "$LAST_NOTIFY_FILE" 2>/dev/null || true
    fi
  fi

  printf '%s' "$report_hash" > "$LAST_HASH_FILE" 2>/dev/null || true
  exit 0
}

main "$@"
