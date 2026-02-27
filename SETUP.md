# NixOS 配置多人协作指南

## 快速开始（朋友使用）

### 1. 克隆仓库
```bash
git clone https://github.com/mohdfaiz10101-cmyk/my-nixos.git
cd my-nixos
```

### 2. 生成你的硬件配置
```bash
# 生成当前机器的硬件配置
sudo nixos-generate-config --show-hardware-config > hardware-configuration.nix
```

### 3. 配置代理（如果需要）
```bash
# 创建你自己的代理订阅配置
sudo mkdir -p /etc/mihomo
sudo proxy-sub <你的订阅链接>
```

### 4. 构建系统
```bash
# 先 build 测试，不直接 switch
sudo nixos-rebuild build --flake .#charlie

# 确认无误后再 switch
sudo nixos-rebuild switch --flake .#charlie --install-bootloader
```

## 敏感文件说明

以下文件已被 `.gitignore` 排除，不会同步到仓库：

- `hardware-configuration.nix` — 硬件配置（每台机器不同）
- `.envrc*` — 环境变量（含 API token）
- `claude-*.js`, `claude_*.py` — 测试脚本（含 API key）
- `secrets/` — 密钥目录
- `.git-credentials` — Git 凭证

## 协作流程

### 提交更改
```bash
# 查看改动
git status

# 添加配置文件（不会包含敏感文件）
git add configuration.nix modules/*.nix flake.nix

# 提交
git commit -m "描述你的改动"

# 推送（需要你自己的 GitHub 账号和 PAT）
git push
```

### 拉取更新
```bash
# 拉取最新配置
git pull

# 重新构建
sudo nixos-rebuild switch --flake .#charlie --install-bootloader
```

## 注意事项

1. **硬件配置独立**：每台机器的 `hardware-configuration.nix` 不同，不要提交到 Git
2. **代理配置独立**：每个人的代理订阅不同，使用自己的订阅链接
3. **API 密钥独立**：如果需要使用 AI 服务，创建自己的 `.envrc` 文件
4. **测试后提交**：修改配置后先 `build` 测试，确认无误再 `switch`

## 常用命令

```bash
# 系统重构（安全模式：先 build 再 switch）
ns

# 垃圾回收
nc

# 查看系统状态
systemctl status

# 查看日志
journalctl -xe

# 代理管理
proxy-status
proxy-restart
proxy-ui

# AI 服务管理
ai-up
ai-ps
```

## 获取帮助

- 查看系统文档：`/etc/nixos/CLAUDE.md`
- 查看架构说明：`/etc/nixos/CONTEXT.md`
- Dashboard 控制台：http://127.0.0.1:9099（需要先启动服务）
