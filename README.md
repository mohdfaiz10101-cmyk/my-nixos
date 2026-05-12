# ai-config-sync

OpenCode × StepClaw 云端-本地配置同步仓库

## 目录结构

```
openclaw-config/
├── agents/           # OpenCode Agent 定义（21 个 agent）
├── openclaw.json     # OpenCode 主配置（已脱敏，密钥需本地单独配置）

memory-export/        # 记忆导出（定时更新，由本地 cron 写入）
├── lessons-learned.md
├── MEMORY.md
└── op-tasks-archive/

op-tasks-sync/        # 任务同步
├── pending.md        # 待处理任务（StepClaw 可认领）
└── completed.md      # 已完成归档
```

## 同步规则

| 方向 | 触发 | 工具 |
|------|------|------|
| 本地 → GitHub | op-tasks.md 变更 / config 变更 | `ai-config-sync-push.sh` |
| GitHub → 本地 | Webhook / 定时 15min | `ai-config-sync-pull.service` |
| StepClaw → GitHub | StepClaw 云端修改 | StepClaw 直接 push |

## FRP 公网通道（2026-05-12 部署）

| 本地端口 | 公网端口 | 服务 | StepClaw 访问地址 |
|---------|---------|------|------------------|
| 8080 | 19890 | OpenCode Web | `ws://100.91.93.99:19890` |
| 9800 | 19891 | Hub API | `http://100.91.93.99:19891` |
| 8283 | 19892 | Letta | `http://100.91.93.99:19892` |

## 安全

- 此仓库为 **Private**，仅本地机器和 StepClaw 有权限
- openclaw.json 已脱敏，真实密钥通过本地 `~/.config/opencode/opencode.json` 管理
- FRP 通道有 token 认证（`frp-token-charlie-2026`）
