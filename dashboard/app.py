#!/usr/bin/env python3
"""NixOS System Dashboard — Charlie's Snowflake"""

import subprocess
import os
import json
import time
import threading
import requests as http_requests
from flask import Flask, render_template, jsonify, Response, request

app = Flask(__name__)

# --- Command Whitelist (security core) ---
COMMANDS = {
    "ns": {
        "cmd": "sudo nixos-rebuild build --flake /etc/nixos#charlie && sudo nixos-rebuild switch --flake /etc/nixos#charlie --install-bootloader",
        "label": "系統重構", "group": "system", "icon": "🔨", "danger": True, "long": True,
    },
    "nc": {
        "cmd": "sudo nix-collect-garbage -d",
        "label": "垃圾回收", "group": "system", "icon": "🧹", "danger": True, "long": True,
    },
    "nix-recover": {
        "cmd": "sudo /etc/nixos/scripts/recover-from-git.sh",
        "label": "遠端恢復", "group": "system", "icon": "🔄", "danger": True, "long": True,
    },
    "ai-up": {
        "cmd": (
            "cd /mnt/ai/ai-cluster/dify/docker && docker compose up -d && "
            "cd /mnt/ai/ai-cluster/n8n && docker compose -p n8n2 up -d && "
            "cd /mnt/ai/ai-cluster/chroma && docker compose -p chroma2 up -d && "
            "cd /mnt/ai/ai-cluster/autogen && docker compose -p autogen up -d && "
            "cd /mnt/ai/ai-cluster/litellm && docker compose -p litellm up -d && "
            "cd /mnt/ai/ai-cluster/letta && docker compose -p letta up -d && "
            "echo 'AI 集群全部啟動'"
        ),
        "label": "啟動 AI 集群", "group": "ai", "icon": "🚀", "danger": False, "long": True,
    },
    "ai-ps": {
        "cmd": "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'",
        "label": "容器狀態", "group": "ai", "icon": "📊", "danger": False, "long": False,
    },
    "ai-log": {
        "cmd": "journalctl -u ollama.service -u openclaw-gateway.service --no-pager -n 50",
        "label": "AI 日誌", "group": "ai", "icon": "📋", "danger": False, "long": False,
    },
    "distill": {
        "cmd": "cd /mnt/ai/ai-cluster/knowledge-distiller && docker compose -p distiller --profile run up --build -d",
        "label": "知識蒸餾", "group": "ai", "icon": "⚗️", "danger": False, "long": True,
    },
    "proxy-status": {
        "cmd": "systemctl status mihomo --no-pager",
        "label": "代理狀態", "group": "proxy", "icon": "🌐", "danger": False, "long": False,
    },
    "proxy-restart": {
        "cmd": "sudo systemctl restart mihomo",
        "label": "重啟代理", "group": "proxy", "icon": "🔁", "danger": False, "long": False,
    },
    "proxy-log": {
        "cmd": "journalctl -u mihomo --no-pager -n 50",
        "label": "代理日誌", "group": "proxy", "icon": "📋", "danger": False, "long": False,
    },
    "letta-sync": {
        "cmd": "/etc/nixos/scripts/letta-sync.sh",
        "label": "記憶同步", "group": "letta", "icon": "🧠", "danger": False, "long": False,
    },
    "nix-seed": {
        "cmd": "nix-shell -p python313Packages.requests --run 'python3 /mnt/ai/ai-cluster/letta/seed-knowledge.py'",
        "label": "知識注入", "group": "letta", "icon": "💉", "danger": False, "long": True,
    },
}

# Rate limiting
_last_run = {}
COOLDOWN_DANGER = 10
COOLDOWN_NORMAL = 2

LETTA_MEMORY_FILE = os.path.expanduser(
    "~/.claude/projects/-etc-nixos/memory/letta-memory.md"
)

LETTA_URL = "http://localhost:8283/v1"
LETTA_TOKEN = "letta-charlie-2026"
LETTA_AGENTS = {
    "nixos-sysadmin": "agent-f7473a7f-185f-4653-96ab-227299653b4a",
    "code-assistant": "agent-caad9ac5-2a89-4d69-ab74-08379cce48f2",
    "opus-analyst": "agent-f7b9eb97-bf04-4127-8389-dd2808e85c81",
}


def run_cmd(cmd, timeout=30):
    try:
        r = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=timeout
        )
        return r.stdout + r.stderr, r.returncode
    except subprocess.TimeoutExpired:
        return "Command timed out", 1
    except Exception as e:
        return str(e), 1


def stream_cmd(cmd):
    proc = subprocess.Popen(
        cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
    )
    for line in iter(proc.stdout.readline, ""):
        yield f"data: {json.dumps({'line': line.rstrip()})}\n\n"
    proc.wait()
    yield f"data: {json.dumps({'done': True, 'exit_code': proc.returncode})}\n\n"


@app.route("/")
def index():
    return render_template("index.html", commands=COMMANDS)


@app.route("/api/status")
def api_status():
    # Disk usage
    disk = {}
    for mount in ["/", "/boot", "/mnt/ai"]:
        out, _ = run_cmd(f"df -h {mount} 2>/dev/null | tail -1")
        parts = out.split()
        if len(parts) >= 5:
            pct = parts[4].rstrip("%")
            disk[mount] = {
                "total": parts[1], "used": parts[2],
                "avail": parts[3], "pct": int(pct) if pct.isdigit() else 0,
            }

    # Service status
    services = {}
    for svc in ["ollama", "mihomo", "docker", "openclaw-gateway"]:
        out, rc = run_cmd(f"systemctl is-active {svc} 2>/dev/null")
        services[svc] = out.strip() == "active"

    # Docker containers
    containers = []
    out, _ = run_cmd("docker ps --format '{{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null")
    for line in out.strip().split("\n"):
        parts = line.split("\t")
        if len(parts) >= 2:
            containers.append({
                "name": parts[0],
                "status": parts[1],
                "ports": parts[2] if len(parts) > 2 else "",
            })

    return jsonify({
        "disk": disk, "services": services, "containers": containers,
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
    })


@app.route("/api/letta-memory")
def api_letta_memory():
    try:
        with open(LETTA_MEMORY_FILE) as f:
            return jsonify({"content": f.read()})
    except FileNotFoundError:
        return jsonify({"content": "Letta 記憶文件不存在，請執行 letta-sync"})


@app.route("/api/run/<cmd_id>", methods=["POST"])
def api_run(cmd_id):
    if cmd_id not in COMMANDS:
        return jsonify({"ok": False, "error": "未知命令"}), 404

    cmd_info = COMMANDS[cmd_id]
    now = time.time()
    cooldown = COOLDOWN_DANGER if cmd_info["danger"] else COOLDOWN_NORMAL
    if cmd_id in _last_run and now - _last_run[cmd_id] < cooldown:
        return jsonify({"ok": False, "error": f"冷卻中，請等 {cooldown} 秒"}), 429

    _last_run[cmd_id] = now
    output, exit_code = run_cmd(cmd_info["cmd"], timeout=60)
    return jsonify({"ok": exit_code == 0, "output": output, "exit_code": exit_code})


@app.route("/api/stream/<cmd_id>")
def api_stream(cmd_id):
    if cmd_id not in COMMANDS:
        return jsonify({"ok": False, "error": "未知命令"}), 404

    cmd_info = COMMANDS[cmd_id]
    now = time.time()
    cooldown = COOLDOWN_DANGER if cmd_info["danger"] else COOLDOWN_NORMAL
    if cmd_id in _last_run and now - _last_run[cmd_id] < cooldown:
        def err():
            yield f"data: {json.dumps({'line': f'冷卻中，請等 {cooldown} 秒', 'done': True})}\n\n"
        return Response(err(), mimetype="text/event-stream")

    _last_run[cmd_id] = now
    return Response(
        stream_cmd(cmd_info["cmd"]),
        mimetype="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@app.route("/api/chat", methods=["POST"])
def api_chat():
    data = request.get_json()
    msg = data.get("message", "").strip()
    agent_name = data.get("agent", "nixos-sysadmin")
    if not msg:
        return jsonify({"ok": False, "error": "空消息"}), 400
    agent_id = LETTA_AGENTS.get(agent_name)
    if not agent_id:
        return jsonify({"ok": False, "error": "未知 agent"}), 404
    try:
        resp = http_requests.post(
            f"{LETTA_URL}/agents/{agent_id}/messages",
            headers={
                "Authorization": f"Bearer {LETTA_TOKEN}",
                "Content-Type": "application/json",
            },
            json={"messages": [{"role": "user", "content": msg}]},
            timeout=120,
        )
        if resp.status_code != 200:
            return jsonify({"ok": False, "error": f"Letta API {resp.status_code}"}), 502
        result = resp.json()
        reply = ""
        for m in result.get("messages", []):
            if m.get("message_type") == "assistant_message":
                content = m.get("content", "")
                if isinstance(content, list):
                    for c in content:
                        if isinstance(c, dict) and c.get("type") == "text":
                            reply += c["text"]
                elif isinstance(content, str):
                    reply += content
        return jsonify({"ok": True, "reply": reply or "(無回應)"})
    except http_requests.Timeout:
        return jsonify({"ok": False, "error": "Letta 回應超時"}), 504
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=9099, debug=False)
