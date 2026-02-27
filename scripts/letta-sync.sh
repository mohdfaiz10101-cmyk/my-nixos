#!/usr/bin/env bash
# Sync Letta agent memories to Claude Code memory directory.
# Runs at most once per hour (uses timestamp file to debounce).
# Called by Claude Code hook on UserPromptSubmit.

LOCK_FILE="/tmp/letta-sync-last"
COOLDOWN=3600  # 1 hour

# Check cooldown
if [ -f "$LOCK_FILE" ]; then
    last=$(cat "$LOCK_FILE" 2>/dev/null || echo 0)
    now=$(date +%s)
    elapsed=$((now - last))
    if [ "$elapsed" -lt "$COOLDOWN" ]; then
        exit 0
    fi
fi

# Check if Letta is reachable (fast fail)
if ! curl -s -o /dev/null -w '' --connect-timeout 2 http://localhost:8283/v1/agents/ -H "Authorization: Bearer letta-charlie-2026" 2>/dev/null; then
    exit 0
fi

# Run sync with nix-shell for requests dependency
nix-shell -p python313Packages.requests --run "python3 /mnt/ai/ai-cluster/letta/letta-sync.py" 2>/dev/null

# Update timestamp
date +%s > "$LOCK_FILE"
