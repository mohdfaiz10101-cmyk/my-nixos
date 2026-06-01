# StepClaw × OpenAgents × OpenClaw × OpenCode × Hermes 五层架构
## NixOS 配置方案（纯 Linux，无 Win/Mac）

> 更新日期：2026-05-14
> 环境：NixOS Flake 架构，本地 IP 内网 192.168.2.x，公网 IP 通过 FRP 暴露

---

## 一、架构总览

```
【StepClaw 云端】──ws──→【OpenAgents Network 8700】──→【OpenClaw Gateway 18789】──→【OpenCode 8-Agent】
   (阶跃 AI App)          (统一编排层)                    (桌面控制+消息接入)          (编码引擎)
        ↑                       ↑                              ↑
  飞书/钉钉/Telegram      统一事件总线                    coding-agent 桥接
  任务入口 + 7×24          agent 协作                     OpenClaw → OpenCode
  轻量任务直接执行        跨网络联邦                    Hermes 记忆注入 context

                    【Hermes Agent】
                    (自学习记忆层, 独立进程)
                    · Skill 自生成 + FTS5 全文检索 + Honcho 用户建模
                    · 跨会话持久记忆（OpenCode/OpenClaw 缺失的第四步）
                    · 与 Letta 互补：Letta=事实存储，Hermes=过程性知识

【LiteLLM 网关】←──所有层共享──模型路由代理（localhost:4000）
```

---

## 二、各层状态确认（NixOS）

### 2.1 OpenAgents Network（统一编排层）

```bash
# 版本
openagents --version

# daemon 状态
systemctl --user status openagents
# → Active: active (running)

# Workspace Web UI
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8700
# → 200

# network.yaml
cat ~/.openagents/network.yaml
```

**当前值**：
| 配置项 | 值 |
|--------|-----|
| version | `v0.9.3.post19` |
| port | `8700`（HTTP，gRPC 已禁用） |
| mode | `centralized` |
| agents | `openclaw / stepclaw / opencode / hermes` |
| status | `running`（systemd user, `openagents.service`） |

### 2.2 Hermes Agent（自学习记忆层）

```bash
# 版本
hermes --version

# 配置
cat ~/.hermes/config.yaml

# 记忆数据库
ls -la ~/.hermes/memory/
```

**当前值**：
| 配置项 | 值 |
|--------|-----|
| model | `litellm/step-3.5-flash-2603` |
| provider | `litellm`（→ StepFun via localhost:4000） |
| fallbacks | `glm-5.1 → deepseek-v4-pro` |
| memory | `~/.hermes/memory/`（SQLite FTS5） |
| skills | `~/.hermes/skills/`（自生成） |
| curator | 每小时整理记忆 |
| MCP servers | filesystem / letta / liteLLM |

### 2.3 OpenClaw Gateway

```bash
systemctl --user status openclaw-gateway
cat ~/.openclaw/openclaw.json | python3 -c "
import sys, json
c = json.load(sys.stdin)
gw = c['gateway']
print(f'mode: {gw[\"mode\"]}')
print(f'port: {gw.get(\"port\", \"default 18789\")}')
print(f'auth: {gw[\"auth\"][\"mode\"]}')
"
journalctl --user -u openclaw-gateway --no-pager -n 5
```

**当前值**：
| 配置项 | 值 |
|--------|-----|
| mode | `local` |
| port | `18789` |
| bind | `127.0.0.1` |
| auth.mode | `token` |
| auth.token | `0e9ec3e2359ff9c986062728f00d5caae783e03628584ca8` |
| model | `litellm/step-3.5-flash-2603` |

### 2.4 FRP 映射

```bash
journalctl --user -u frpc --no-pager -n 20 | grep proxy
```

**当前值**：
| 代理名 | 本地 | 远程 | 用途 |
|--------|------|------|------|
| nixos-ssh | 127.0.0.1:22 | **2223** | SSH 远程登录 |
| nixos-tty | 127.0.0.1:7699 | **17699** | Web TTY 终端 |
| nixos-mosh-{1,2,3} | 127.0.0.1:60000-60002 | **60000-60002** | Mosh 低延迟终端 |
| nixos-opencode-web | 127.0.0.1:8080 | **19890** | OpenCode Web 终端 |
| nixos-hub-api | 127.0.0.1:9800 | **19891** | Hub API |
| nixos-letta-mcp | 127.0.0.1:8284 | **19892** | Letta MCP |
| **nixos-openclaw-gw** | **127.0.0.1:18789** | **19893** | **OpenClaw Gateway（StepClaw 云端连接）** |
| nixos-opencode-sisy | 127.0.0.1:8090 | **18090** | OpenCode Sisy 永久公网 |

> OpenAgents Network（8700）**不需要** FRP 代理——纯本地编排层，外部访问通过 OpenClaw Gateway 间接路由。

### 2.5 OpenCode CLI

```bash
which opencode        # ~/.npm-global/bin/opencode
opencode --version    # 1.14.50
```

### 2.6 LiteLLM 代理

```bash
curl -s -H "Authorization: Bearer sk-litellm-charlie-2026" \
  http://localhost:4000/v1/models | python3 -c "import json,sys; print(len(json.load(sys.stdin)['data']), 'models')"
```

**当前值**：
| 配置项 | 值 |
|--------|-----|
| url | `http://localhost:4000` |
| models | `28` 可用（step-3.5-flash-2603 / step-3.5-flash / glm-5.1 / glm-5-turbo / deepseek-v4-pro / deepseek-v4-flash） |
| status | `running`（Docker: `litellm-litellm` + `litellm-redis`） |

---

## 三、StepClaw 云端配置（你在阶跃 AI App 上操作）

> ⚠️ **重要**：你只有 NixOS Linux，没有 Win/Mac。配置在 **阶跃 AI App**（手机 App）或 **阶跃 AI 网页版**完成。

### 3.1 手机 App 配置路径

1. 打开「阶跃 AI」App → 左上角 **StepClaw** 入口
2. 进入 **设置** / **连接配置**
3. 找到 **本地 Gateway 配置** / **远程 OpenClaw** / **自定义实例**
4. 填写：

| 配置项 | 值 |
|--------|-----|
| Gateway 模式 | `Remote` / `自定义远程网关` |
| WebSocket URL | `ws://100.91.93.99:19893` |
| Token | `0e9ec3e2359ff9c986062728f00d5caae783e03628584ca8` |
| 模型 | `Step 3.5 Flash`（云端默认） |

> ⚠️ 手机 App 界面可能没有"远程 Gateway"入口。如果 App 只支持本地桌面部署，那么：
>
> **替代方案 A**：用 **阶跃 AI 网页版**（https://stepclaw.org 或 https://platform.stepfun.com）配置 StepClaw 云端
>
> **替代方案 B**：在 NixOS 上用浏览器操作阶跃 AI Web 控制台完成配置

### 3.2 公网 IP 确认

当前 FRP 服务端：`192.168.123.209:7000`（NixOS 局域网 IP）

**公网访问地址**（Tailscale + FRP）：
- **WebSocket**: `ws://100.91.93.99:19893`（OpenClaw Gateway）
- **OpenCode Web**: `http://100.91.93.99:19890`
- **Hub API**: `http://100.91.93.99:19891`
- **Letta MCP**: `http://100.91.93.99:19892`

> ⚠️ 以上地址通过 Tailscale 网络可达。如果 StepClaw 云端不在 Tailscale 网络内，需配置 FRP 公网映射。

### 3.3 WebSocket URL 格式

```
ws://100.91.93.99:19893
```

已配置完成，可直接使用。

### 3.4 五层路由说明

StepClaw 云端 → OpenAgents Network（本地 8700）→ OpenClaw Gateway（本地 18789 → 公网 19893）→ OpenCode 8-Agent

- **轻量任务**（<100行代码、摘要、翻译）：StepClaw 云端直接执行，不经本地
- **编码/架构/NixOS 任务**：StepClaw → OpenAgents → OpenClaw → OpenCode coding-agent
- **本地控制/消息/自动化**：StepClaw → OpenAgents → OpenClaw 直接执行
- **记忆层**：Hermes（独立进程）通过 OpenAgents 总线注入 context

---

## 四、OpenClaw 本地配置（已完成 ✅）

### 4.1 已配置项

| 配置项 | 值 | 状态 |
|--------|-----|------|
| `gateway.mode` | `local` | ✅ |
| `gateway.auth.mode` | `token` | ✅ |
| `gateway.auth.token` | `0e9ec3e2...` | ✅ |
| `agents.defaults.model` | `litellm/step-3.5-flash-2603` | ✅ |
| `agents.defaults.model.fallbacks` | `[glm-5.1, deepseek-v4-pro]` | ✅ |
| `agents.defaults.agentRuntime.id` | `auto`（支持 OpenCode backend） | ✅ |
| `agents.list[0].id` | `main`（OpenClaw 桌面控制） | ✅ |
| `skills.entries.coding-agent.enabled` | `true` | ✅ |

### 4.2 coding-agent 路由逻辑

OpenClaw main agent 的 system prompt override：

```
编码任务识别 → 使用 coding-agent skill → 调用 OpenCode CLI
本地控制/消息/自动化 → OpenClaw 自己执行
```

### 4.3 OpenCode 8-Agent 精简

| Agent | Mode | Model | 角色 |
|-------|------|-------|------|
| sisyphus | primary | step-3.5-flash | 主指挥官 |
| plan | primary | step-3.5-flash | 规划器 |
| arch | primary | step-3.5-flash-2603 | 架构师 |
| chat | primary | step-3.5-flash | 对话模式 |
| marketing-coordinator | primary | step-3.5-flash | 营销负责人 |
| build | subagent | step-3.5-flash | 代码构建器 |
| explore | subagent | step-3.5-flash | 代码搜索员 |
| refactor | subagent | step-3.5-flash | 重构器 |

已删除：`ops-dispatcher` → 合并入 `sisyphus`
已删除：`tech-architect` → 合并入 `arch`
已删除：`tech-researcher` → 合并入 `explore`
已删除：`marketing-auditor` → 合并入 `marketing-coordinator`

---

## 五、任务路由总表

| 入口 | 任务类型 | 执行位置 | 路径 |
|------|---------|---------|------|
| 阶跃 AI App / 飞书 / 钉钉 | 轻量编码（<100行） | **StepClaw 云端** | 云端 StepFun 直接执行 |
| 阶跃 AI App / 飞书 / 钉钉 | 复杂编码 / 架构 / NixOS | OpenAgents → OpenClaw → OpenCode | 云端 → OpenAgents 8700 → OpenClaw GW → OpenCode |
| 阶跃 AI App / 飞书 / 钉钉 | 本地文件 / 桌面控制 | OpenAgents → OpenClaw | 云端 → OpenAgents 8700 → OpenClaw GW → 直接执行 |
| 阶跃 AI App / 飞书 / 钉钉 | 信息检索 / 摘要 / 定时 | **StepClaw 云端** | 云端 StepFun 直接执行 |
| OpenCode CLI | 任何编码任务 | OpenCode 本地 | **直接执行，不经 OpenAgents/OpenClaw** |
| OpenClaw Gateway Web | 本地控制 / coding-agent | OpenClaw / OpenCode | 直接执行 |
| Hermes | 记忆检索 / Skill 生成 | Hermes 独立进程 | 通过 OpenAgents 总线注入 context |

---

## 六、FRP 端口汇总

| 远程端口 | 本地 | 用途 |
|---------|------|------|
| 19890 | OpenCode Web | OpenCode Web 终端 |
| 19891 | localhost:9800 | Hub API |
| 19892 | localhost:8284 | Letta MCP |
| **19893** | **127.0.0.1:18789** | **OpenClaw Gateway（StepClaw 云端连接）** |

---

## 七、NixOS 服务状态检查

```bash
# OpenAgents Network（统一编排层）
systemctl --user status openagents
ss -tlnp | grep 8700          # → LISTEN 0.0.0.0:8700
curl -s http://127.0.0.1:8700 # → Web UI HTML

# Hermes Agent（自学习记忆层）
systemctl --user status hermes-agent

# OpenClaw Gateway
systemctl --user status openclaw-gateway
ss -tlnp | grep 18789

# FRP Client
systemctl --user status frpc
journalctl --user -u frpc --no-pager -n 10 | grep proxy

# LiteLLM
docker ps | grep litellm
curl -s -H "Authorization: Bearer sk-litellm-charlie-2026" http://localhost:4000/v1/models

# OpenCode
opencode --version
```

### 当前五层状态速查

| 层级 | 服务 | 端口 | 状态 |
|------|------|------|------|
| StepClaw 云端 | 阶跃 AI App | — | ⏳ 待用户配置 WebSocket |
| OpenAgents | `openagents.service` | 8700 | ✅ running |
| Hermes | `hermes-agent.service` | — | ✅ running |
| OpenClaw GW | `openclaw-gateway.service` | 18789 | ✅ running |
| OpenCode | CLI | — | ✅ v1.14.50 |
| FRP | `frpc.service` | 9 个代理 | ✅ 全部在线 |
| LiteLLM | Docker | 4000 | ✅ 28 模型 |

---

## 八、故障排查

### StepClaw 云端连不上本地 OpenClaw

```bash
# 1. 确认 FRP 代理在线
journalctl --user -u frpc --no-pager -n 20 | grep openclaw

# 2. 确认 OpenClaw Gateway 在线
systemctl --user status openclaw-gateway
ss -tlnp | grep 18789

# 3. 本地测试 WebSocket
curl -H "Authorization: Bearer 0e9ec3e2359ff9c986062728f00d5caae783e03628584ca8" \
  http://127.0.0.1:18789/health 2>/dev/null

# 4. 从公网测试（换你的 IP）
curl -H "Authorization: Bearer 0e9ec3e2359ff9c986062728f00d5caae783e03628584ca8" \
  http://<公网IP>:19893/health
```

### OpenClaw → OpenCode 编码任务失败

```bash
# 确认 opencode 在 PATH 里
which opencode
opencode --version

# 手动测试
cd /tmp && opencode --model step-3.5-flash -p "echo hello"

# 检查 coding-agent skill
openclaw skills list | grep coding-agent
```

### OpenClaw Gateway 启动失败

```bash
# 检查端口占用
ss -tlnp | grep 18789

# 强制重启
systemctl --user restart openclaw-gateway

# 查看错误日志
journalctl --user -u openclaw-gateway --no-pager -n 30
```

### OpenAgents Network 启动失败

```bash
# 检查端口占用
ss -tlnp | grep 8700

# 检查 venv 依赖
/mnt/ai/oa-venv/bin/python3 -c "import pydantic; import requests; print('OK')"

# 强制重启
systemctl --user restart openagents

# 查看错误日志
journalctl --user -u openagents --no-pager -n 30
tail -20 /home/charlie/.openagents/openagents.log
```

> **常见问题**：NixOS venv 隔离导致 `pydantic`/`requests` 等包找不到
> → 修复：`pip install --target /mnt/ai/oa-venv/lib/python3.13/site-packages <package>`
> **gRPC 依赖 libstdc++.so.6**：已禁用 gRPC transport，仅保留 HTTP 8700

### Hermes Agent 启动失败

```bash
# 检查进程
ps aux | grep hermes | grep -v grep

# 检查配置
cat ~/.hermes/config.yaml

# 强制重启
systemctl --user restart hermes-agent

# 查看日志
journalctl --user -u hermes-agent --no-pager -n 30
```

### 全链路连通性测试

```bash
# 1. Hermes → OpenAgents
curl -s http://127.0.0.1:8700/mcp  # → 200（MCP tools 列表）

# 2. OpenAgents → OpenClaw
curl -H "Authorization: Bearer 0e9ec3e2359ff9c986062728f00d5caae783e03628584ca8" \
  http://127.0.0.1:18789/health  # → 200

# 3. OpenClaw → OpenCode
which opencode && opencode --version  # → 1.14.50

# 4. LiteLLM 模型路由
curl -s -H "Authorization: Bearer sk-litellm-charlie-2026" \
  http://localhost:4000/v1/models | python3 -c "import json,sys; print(len(json.load(sys.stdin)['data']), 'models')"
```
