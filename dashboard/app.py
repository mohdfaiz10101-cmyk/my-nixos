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
    "memory-sync": {
        "cmd": "/etc/nixos/scripts/memory-sync.sh",
        "label": "全量記憶同步", "group": "letta", "icon": "🔄", "danger": False, "long": True,
    },
    "nix-seed": {
        "cmd": "nix-shell -p python313Packages.requests --run 'python3 /mnt/ai/ai-cluster/letta/seed-knowledge.py'",
        "label": "知識注入", "group": "letta", "icon": "💉", "danger": False, "long": True,
    },
    "pin-recovery": {
        "cmd": "current_gen=$(sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | grep current | awk '{print $1}') && sudo ln -sf /nix/var/nix/profiles/system-${current_gen}-link /nix/var/nix/gcroots/pinned-recovery-$(date +%Y%m%d-%H%M%S) && echo \"已釘死 Generation ${current_gen} 為 Recovery 版本\"",
        "label": "設為 Recovery", "group": "system", "icon": "📌", "danger": False, "long": False,
    },
    "1688-install-userscript": {
        "cmd": "cat /mnt/ai/ai-cluster/1688-system/userscript/1688-assistant.user.js",
        "label": "安裝油猴腳本", "group": "1688", "icon": "📜", "danger": False, "long": False,
    },
    "1688-sync-telegram": {
        "cmd": "curl -s -x http://127.0.0.1:7890 'https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage' -d 'chat_id=${TELEGRAM_CHAT_ID}' -d 'text=🔄 1688 系統同步測試' -d 'parse_mode=HTML' 2>/dev/null && echo '✅ Telegram 推送成功'",
        "label": "同步到 Telegram", "group": "1688", "icon": "📱", "danger": False, "long": False,
    },
    "letta-obsidian": {
        "cmd": "python3 /etc/nixos/scripts/letta-obsidian-sync.py 2>&1 || /mnt/ai/ai-cluster/1688-system/letta-obsidian-simple.sh 2>&1",
        "label": "Letta→Obsidian", "group": "letta", "icon": "📓", "danger": False, "long": False,
    },
    "memory-manage": {
        "cmd": "python3 /etc/nixos/scripts/memory-fragment-manager.py 2>&1",
        "label": "記憶碎片管理", "group": "letta", "icon": "🧩", "danger": False, "long": False,
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


@app.route("/api/token-stats")
def api_token_stats():
    """获取 Token 使用统计与省 Token 优化状态"""
    stats = {
        "redis": {"hits": 0, "misses": 0, "hit_rate": 0},
        "letta": {"agents": 0, "total_memories": 0},
        "obsidian": {"letta_files": 0, "fragment_files": 0, "total_fragments": 0},
        "models": {"local": ["qwen3:8b", "deepseek-r1:14b"], "cloud": ["glm-4.7", "gemini-flash", "claude-opus"]},
    }

    # Redis 缓存统计
    try:
        out, _ = run_cmd("docker exec litellm-redis redis-cli -a litellm-redis-2026 INFO stats 2>/dev/null")
        for line in out.split("\n"):
            if "keyspace_hits" in line:
                stats["redis"]["hits"] = int(line.split(":")[1].strip())
            elif "keyspace_misses" in line:
                stats["redis"]["misses"] = int(line.split(":")[1].strip())

        hits = stats["redis"]["hits"]
        misses = stats["redis"]["misses"]
        total = hits + misses
        stats["redis"]["hit_rate"] = round(hits / total * 100, 2) if total > 0 else 0
    except:
        pass

    # Letta 记忆统计
    try:
        resp = http_requests.get(f"{LETTA_URL}/agents",
                               headers={"Authorization": f"Bearer {LETTA_TOKEN}"}, timeout=2)
        if resp.status_code == 200:
            agents = resp.json().get("agents", [])
            stats["letta"]["agents"] = len(agents)
            for agent in agents:
                resp = http_requests.get(f"{LETTA_URL}/agents/{agent['id']}/archival",
                                       headers={"Authorization": f"Bearer {LETTA_TOKEN}"}, timeout=2)
                if resp.status_code == 200:
                    stats["letta"]["total_memories"] += len(resp.json().get("memories", []))
    except:
        pass

    # Obsidian 文件统计
    try:
        from pathlib import Path
        letta_path = Path.home() / "Documents" / "Obsidian" / "Letta-Memory"
        frag_path = Path.home() / "Documents" / "Obsidian" / "Memory-Fragments"
        stats["obsidian"]["letta_files"] = len(list(letta_path.glob("*.md"))) if letta_path.exists() else 0
        if frag_path.exists():
            md_files = list(frag_path.glob("*.md"))
            stats["obsidian"]["fragment_files"] = len(md_files)
            # 统计碎片数量
            for f in md_files:
                if f.name != "INDEX.md":
                    content = f.read_text()
                    stats["obsidian"]["total_fragments"] += content.count("## [")
    except:
        pass

    return jsonify(stats)


@app.route("/api/obsidian-stats")
def api_obsidian_stats():
    """获取 Obsidian 记忆碎片详细统计"""
    from pathlib import Path
    result = {"categories": [], "total_fragments": 0}
    try:
        frag_path = Path.home() / "Documents" / "Obsidian" / "Memory-Fragments"
        index_file = frag_path / "INDEX.md"
        if index_file.exists():
            content = index_file.read_text()
            # 解析统计信息
            import re
            match = re.search(r'\*\*(\d+)\*\*.*?碎片.*?\*\*(\d+)\*\*.*?标签', content)
            if match:
                result["total_fragments"] = int(match.group(1))
                total_tags = int(match.group(2))
            # 解析分类
            for line in content.split("\n"):
                if "- [[" in line:
                    match = re.search(r'\[\[([^\]]+)\)\]\s*\((\d+)\s*个\)', line)
                    if match:
                        result["categories"].append({"name": match.group(1), "count": int(match.group(2))})
    except:
        pass
    return jsonify(result)


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


@app.route("/api/userscript")
def api_userscript():
    """提供油猴脚本下载"""
    script_path = "/mnt/ai/ai-cluster/1688-system/userscript/1688-assistant.user.js"
    try:
        with open(script_path) as f:
            content = f.read()
        return Response(
            content,
            mimetype="application/javascript",
            headers={
                "Content-Disposition": "inline; filename=1688-assistant.user.js",
                "Content-Type": "application/javascript; charset=utf-8",
            },
        )
    except FileNotFoundError:
        return jsonify({"error": "脚本文件不存在"}), 404


@app.route("/procurement")
def procurement_page():
    return render_template("procurement.html")


@app.route("/api/procurement/stats")
def api_procurement_stats():
    """获取采购统计"""
    import sys
    sys.path.insert(0, "/etc/nixos/scripts")
    try:
        from procurement_filter import ProcurementFilter
        filter_sys = ProcurementFilter()
        return jsonify(filter_sys.get_stats())
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/procurement/items")
def api_procurement_items():
    """获取采购项目列表"""
    import sys
    sys.path.insert(0, "/etc/nixos/scripts")
    try:
        from procurement_filter import ProcurementFilter
        filter_sys = ProcurementFilter()
        status = request.args.get("status", "pending")
        items = filter_sys.items
        if status != "all":
            items = {k: v for k, v in items.items() if v.get("status") == status}
        return jsonify({"items": items, "suppliers": filter_sys.suppliers, "blacklist": list(filter_sys.blacklist)})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/procurement/add", methods=["POST"])
def api_procurement_add():
    """添加采购项目"""
    import sys
    sys.path.insert(0, "/etc/nixos/scripts")
    try:
        from procurement_filter import ProcurementFilter
        filter_sys = ProcurementFilter()
        data = request.get_json()
        result = filter_sys.add_item(
            url=data.get("url", ""),
            title=data.get("title", ""),
            supplier=data.get("supplier"),
            price=data.get("price"),
            tags=data.get("tags", []),
            notes=data.get("notes")
        )
        return jsonify(result)
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@app.route("/api/procurement/status", methods=["POST"])
def api_procurement_status():
    """更新项目状态"""
    import sys
    sys.path.insert(0, "/etc/nixos/scripts")
    try:
        from procurement_filter import ProcurementFilter
        filter_sys = ProcurementFilter()
        data = request.get_json()
        item_id = data.get("id")
        new_status = data.get("status")
        if item_id in filter_sys.items:
            filter_sys.items[item_id]["status"] = new_status
            filter_sys._save_json(filter_sys.items_file, filter_sys.items)
            return jsonify({"ok": True})
        return jsonify({"ok": False, "error": "Item not found"}), 404
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@app.route("/api/procurement/blacklist", methods=["POST"])
def api_procurement_blacklist():
    """添加黑名单"""
    import sys
    sys.path.insert(0, "/etc/nixos/scripts")
    try:
        from procurement_filter import ProcurementFilter
        filter_sys = ProcurementFilter()
        data = request.get_json()
        result = filter_sys.add_blacklist(data.get("entry", ""))
        return jsonify(result)
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@app.route("/api/procurement/export", methods=["POST"])
def api_procurement_export():
    """导出到 Obsidian"""
    import sys
    sys.path.insert(0, "/etc/nixos/scripts")
    try:
        from procurement_filter import ProcurementFilter
        filter_sys = ProcurementFilter()
        filter_sys.export_to_obsidian()
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=9099, debug=False)
