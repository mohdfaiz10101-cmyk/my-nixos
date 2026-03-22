#!/usr/bin/env bash
# Auto-backup Floorp bookmarks to /etc/nixos/backups/ for git tracking
# Copies the latest bookmark backup (jsonlz4) and also exports readable JSON via sqlite
set -euo pipefail

BACKUP_DIR="/etc/nixos/backups"
mkdir -p "$BACKUP_DIR"

# Find all Floorp profiles (root + charlie)
for base in /root/.floorp /home/charlie/.floorp; do
  [ -d "$base" ] || continue
  for profile in "$base"/*.default*; do
    [ -d "$profile" ] || continue
    user=$(basename "$(dirname "$(dirname "$profile")")")

    # Method 1: Copy latest jsonlz4 bookmark backup
    bk_dir="$profile/bookmarkbackups"
    if [ -d "$bk_dir" ]; then
      latest=$(ls -t "$bk_dir"/bookmarks-*.jsonlz4 2>/dev/null | head -1)
      if [ -n "$latest" ]; then
        cp "$latest" "$BACKUP_DIR/floorp-bookmarks-${user}-latest.jsonlz4"
      fi
    fi

    # Method 2: Export bookmarks from places.sqlite as readable JSON
    # Copy to temp to avoid locking issues with running browser
    places="$profile/places.sqlite"
    if [ -f "$places" ]; then
      tmp_db=$(mktemp /tmp/places-XXXXXX.sqlite)
      cp "$places" "$tmp_db"
      cp "${places}-wal" "${tmp_db}-wal" 2>/dev/null || true
      SQLITE3=$(command -v sqlite3 || find /nix/store -maxdepth 2 -name sqlite3 -type f 2>/dev/null | head -1)
      $SQLITE3 "$tmp_db" "
        SELECT json_group_array(json_object(
          'title', b.title,
          'url', p.url,
          'added', datetime(b.dateAdded/1000000, 'unixepoch'),
          'folder', (SELECT title FROM moz_bookmarks WHERE id = b.parent)
        ))
        FROM moz_bookmarks b
        JOIN moz_places p ON b.fk = p.id
        WHERE b.type = 1 AND p.url NOT LIKE 'place:%'
        ORDER BY b.dateAdded DESC;
      " 2>/dev/null > "$BACKUP_DIR/floorp-bookmarks-${user}.json" || true
      rm -f "$tmp_db"
    fi
  done
done

echo "[$(date '+%Y-%m-%d %H:%M')] Floorp bookmarks backed up to $BACKUP_DIR"
