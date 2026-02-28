# NixOS 配置多人协作指南

## 快速开始（朋友使用）

### 方式一：电脑（已有 NixOS）

#### 1. 克隆仓库
```bash
git clone https://github.com/mohdfaiz10101-cmyk/my-nixos.git
cd my-nixos

# 查看所有分支
git branch -a
# main     — 稳定版（不经常更新）
# personal — 最新版（日常使用）

# 切换到最新版
git checkout personal
```

#### 2. 配置你的机器
```bash
# 生成硬件配置（每台机器不同）
sudo nixos-generate-config --show-hardware-config > hardware-configuration.nix

# 创建你的密码和代理配置
cp user-secrets.nix.example user-secrets.nix

# 生成密码哈希
nix-shell -p mkpasswd --run 'mkpasswd -m sha-512 你的密码'
# 把输出的哈希值填入 user-secrets.nix 的 password 字段

# 编辑 user-secrets.nix
nano user-secrets.nix
```

#### 3. 配置代理（如果在中国大陆）
```bash
sudo mkdir -p /etc/mihomo
sudo proxy-sub <你的订阅链接>
```

#### 4. 构建系统
```bash
# 先 build 测试
sudo nixos-rebuild build --flake .#charlie

# 确认无误后 switch
sudo nixos-rebuild switch --flake .#charlie --install-bootloader
```

### 方式二：Windows 虚拟机安装 NixOS

#### 1. 下载 NixOS ISO
- 官网：https://nixos.org/download
- 选择 GNOME 图形安装器（推荐）

#### 2. 创建虚拟机
- **VirtualBox**：新建 → Linux → Other Linux (64-bit)
  - 内存：8GB+、磁盘：80GB+、CPU：4核+
  - 设置 → 系统 → 启用 EFI
  - 设置 → 显示 → 显存 128MB
- **Hyper-V**：新建 → 第 2 代 → 安全启动关闭

#### 3. 安装 NixOS
- 用 ISO 启动 → 图形安装器一路 Next
- 安装完成后重启，移除 ISO

#### 4. 拉取配置
```bash
# 安装 git
nix-shell -p git

# 克隆配置
cd /etc/nixos
sudo rm -f configuration.nix  # 移除默认配置
sudo git clone https://github.com/mohdfaiz10101-cmyk/my-nixos.git .
sudo git checkout personal
sudo chown -R $(whoami):users /etc/nixos

# 保留你自己的硬件配置（已经在 .gitignore 中）
# hardware-configuration.nix 会保留安装器生成的版本

# 配置密码和代理
cp user-secrets.nix.example user-secrets.nix
nix-shell -p mkpasswd --run 'mkpasswd -m sha-512 你的密码'
nano user-secrets.nix  # 填入密码哈希

# 构建
sudo nixos-rebuild switch --flake .#charlie --install-bootloader
```

### 方式三：手机查看配置

#### GitHub 官方 App（推荐）
1. 手机安装 **GitHub** App（App Store / Google Play）
2. 登录 GitHub 账号
3. 搜索 `mohdfaiz10101-cmyk/my-nixos`
4. 可浏览所有文件、切换 main/personal 分支

#### 浏览器直接访问
- https://github.com/mohdfaiz10101-cmyk/my-nixos
- 切换分支下拉框选 `personal` 看最新版

#### Android 终端（Termux）
```bash
# 安装 Termux（从 F-Droid 下载，不要用 Play Store 版本）
pkg install git
git clone https://github.com/mohdfaiz10101-cmyk/my-nixos.git
cd my-nixos && git checkout personal
cat configuration.nix   # 查看配置
git pull                 # 拉取最新
```

#### iOS 终端（iSH）
```bash
apk add git
git clone https://github.com/mohdfaiz10101-cmyk/my-nixos.git
```

## 分支说明

| 分支 | 用途 | 更新频率 |
|------|------|----------|
| `main` | 稳定版 | 偶尔 |
| `personal` | 最新版（日常使用） | 每天 |

## 敏感文件说明

以下文件已被 `.gitignore` 排除，**不会**同步到仓库：

| 文件 | 内容 | 你需要做什么 |
|------|------|-------------|
| `hardware-configuration.nix` | 硬件配置 | 安装时自动生成 |
| `user-secrets.nix` | 密码 + 代理 URL | 从 `.example` 复制并填写 |
| `secrets/` | API 密钥 | 按需创建 |
| `.envrc` | 环境变量 | 按需创建 |

## 常用命令

```bash
ns              # 系统重构（安全模式：先 build 再 switch）
nc              # 垃圾回收
ai-up           # 启动 AI 集群
ai-ps           # 容器状态
proxy-status    # 代理状态
proxy-ui        # 代理节点切换 UI
dashboard       # 打开 Dashboard 控制面板
```

## 获取帮助

- 系统文档：`/etc/nixos/CLAUDE.md`
- 架构说明：`/etc/nixos/CONTEXT.md`
- Dashboard：http://127.0.0.1:9099
