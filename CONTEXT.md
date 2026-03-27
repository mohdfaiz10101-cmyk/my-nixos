# NixOS 系統上下文 — Charlie's Snowflake
# 此檔案供所有 AI 助手共用（Claude、Gemini 等），請勿刪除
# 最後更新：2026-03-27


## AI 記憶系統架構 (2026-03-27 新增)
**5層防護系統** - 解決換賬號後記憶丟失問題：
1. SessionStart Hook（~/.claude/hooks/session-init.sh）- 強制加載記憶
2. Letta 長期記憶（localhost:8283）- 4 Agents + 7層防護
3. ChromaDB 向量庫（localhost:8000）- 備用（實際用 Ollama 嵌入）
4. 自動備份（/mnt/pool/backups/memory/）- 每小時備份，保留7天
5. 文件系統冗余（memory/ + Obsidian + CONTEXT.md）
## 系統架構
- OS: NixOS (Flake 架構)，入口 `flake.nix`，輸出端點 `charlie`
- 引導: UEFI + GRUB，EFI 掛載 `/boot`（252MB，與 Windows 11 共用同一 NVMe）
- 桌面: KDE Plasma 6 + SDDM（主力），GNOME + GDM（備用）
- GPU: NVIDIA RTX 3060 Ti（GA104，閉源驅動，CUDA 加速）
- CPU: Intel（啟用 KVM 虛擬化）
- 網路: NetworkManager + xray 代理 127.0.0.1:7890（HTTP）+ 7891（SOCKS5）
- 輸入法: Fcitx5 + Rime + Chinese Addons (Qt6) + Wayland Frontend
- 終端: Kitty

## 分區佈局
| 分區 | UUID | 類型 | 掛載點 | 備註 |
|------|------|------|--------|------|
| nvme0n1p9 | 2d8662db-7f69-49a6-b396-ef96dc3e0b23 | ext4 | / | 根分區 89G（重裝後新 UUID）|
| nvme0n1p2 | FA67-631E | vfat | /boot | EFI 252MB（共用） |
| sdb1 | B2BCF4DBBCF49B55 | ntfs | /mnt/storage_1.8t | 外接 2T 硬碟 |
| (sda4等) | DE22F5F022F5CD91 | ntfs | /mnt/data | 4T 資料碟 |
| sda1-4 | 各自 UUID | ntfs | 未掛載 | 拷貝碟 1/2/3 |

## 配置檔案結構與職責
```
/etc/nixos/
├── flake.nix                # Flake 入口，定義 inputs (nixpkgs-unstable + openclaw)
├── configuration.nix        # 主配置（下面詳述）
├── hardware-configuration.nix  # 硬體偵測（UUID、kernel modules），自動生成勿手改
├── .envrc                   # direnv 環境變數（Anthropic API key + base URL，不進 git）
├── .gitignore               # 排除 .envrc、.idea、.claude、secrets、hardware-config
│
├── modules/
│   ├── ai.nix               # AI 服務棧（見下方 AI 架構）
│   ├── storage.nix          # 4T 資料碟掛載 (DE22... → /mnt/data, ntfs3, nofail)
│   ├── productivity.nix     # uTools 容錯安裝（hasAttr 檢查，fallback 到 appimage-run）
│   ├── community.nix        # [舊] Flatpak + input-remapper + 1.8T 掛載 + OpenClaw oneshot
│   ├── essentials.nix       # [舊] 同 community 的早期版本
│   └── git.nix              # [舊] Git 全域配置（alias: st/ad/up/last, safe directory）
│
├── user/
│   └── charlie.nix          # [舊] 用戶定義 + zsh alias (up/down/ns/nc/nu) + tmux + fcitx5
│
├── packages.nix             # [舊] 獨立套件清單（chrome, scrcpy, flclash 等）
├── proxy.nix                # [舊] 代理看門狗（Mihomo ↔ dae 自動切換）
├── scripts.nix              # [舊] scrcpy 三機位佈局 + nx-apply 一鍵同步
│
├── essence/
│   ├── 00_base.md           # Charlie 核心交互協議（模式路由、視覺規範、部署協議）
│   └── updates/             # 增量補丁目錄（手機端新增 → GitHub Action 合併）
│
├── logic.md                 # AI 工作站部署邏輯存檔
├── CLAUDE.md                # Claude Code 專用上下文
└── CONTEXT.md               # 本檔案（跨 AI 共用）
```

**注意**：標記 `[舊]` 的檔案是重構前的遺留模組。目前 `configuration.nix` 的 imports 引用：
- `hardware-configuration.nix`、`modules/storage.nix`、`modules/ai.nix`、`modules/proxy.nix`
- `modules/essentials.nix`、`modules/git.nix`、`modules/community.nix`、`modules/productivity.nix`
- `scripts.nix`
其餘舊模組（`packages.nix`、`proxy.nix`根目錄版、`user/charlie.nix`）的功能已整合進主配置或不再使用。

## configuration.nix 構建邏輯
1. **硬體與驅動**：allowUnfree + enableAllFirmware + Intel/AMD microcode + NVIDIA 閉源驅動
2. **引導加固**：GRUB + efiInstallAsRemovable（萬用路徑）+ configurationLimit=3 + Windows 11 chainloader
3. **F3 救援模式**：specialisation 強制啟用 NetworkManager + allowUnfree
4. **虛擬化**：Docker（含代理設定）+ libvirtd + virt-manager
5. **用戶環境**：charlie 用戶 + zsh（安全 ns/nc alias）+ direnv
6. **開發工具**：firefox, git, vscode, idea, docker-compose, tmux, nodejs_22, ntfs3g, direnv
7. **輸入法**：fcitx5 + rime + chinese-addons (Qt6)

## AI 服務架構 (modules/ai.nix)
- **Ollama**：CUDA 加速推理後端，監聽 0.0.0.0:11434
- **OpenClaw Gateway**：數據門戶，Port 18789，對接本地 Ollama
  - 預設模型：qwen2.5-coder:7b
  - 配置透過 Nix Store 不可變 JSON 注入
  - systemd 服務：root 運行，always restart
- **防火牆**：開放 11434 + 18789

## 安全機制與操作規範
### GRUB 防護（2026-02 黑屏事件後部署）
- `configurationLimit = 3`：限制 GRUB Generation 數量，防 EFI 爆滿
- `ns` alias：先 `nixos-rebuild build` 驗證 → 成功才 `switch --install-bootloader`
- Gen 64 釘死為 GC root：`/nix/var/nix/gcroots/pinned-stable-gen64`
- F3 Recovery Stable Mode：specialisation 救援開機選項

### 緊急回滾
```bash
sudo nix-env --profile /nix/var/nix/profiles/system --switch-generation 64
sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch
```

### 磁碟保護
- 所有外接碟掛載加 `nofail`，防止開機卡死
- 1.8T 硬碟鎖定 UUID B2BCF4DBBCF49B55

### 包管理安全
- 包定義使用 `builtins.hasAttr` 容錯檢查（見 productivity.nix）
- `/nix/store` 唯讀，不能在裡面跑 `npm install`

## 代理與網路（2026-03-22 更新）
- **xray**：系統級代理，vless+ws+tls，開機自啟
  - HTTP 代理：port 7890
  - SOCKS5 代理：port 7891
  - 出口節點：美國（cfyes.lxy1015.top → lx-us1.lxy1015.top）
  - 配置以 `builtins.toJSON` 內聯於 `modules/proxy.nix`（純 Nix，不依賴外部文件）
- networking.proxy 系統環境變數（git/curl 自動走代理）
- GNOME 系統代理：manual 模式指向 127.0.0.1:7890
- Firefox：已配 user.js 使用 HTTP 代理
- **已移除**：clash-verge-rev、TUN 模式、dae
- **2026-03-23 更新**：mihomo 和 proxy-watchdog 已重新启用为 3-Tier Failover 备份方案

## Essence 同步協議
- `up` alias：git pull → commit → push → rclone sync 到 Google Drive
- `down` alias：git pull → 重建 updates/ 目錄
- GitHub Action：updates/ 補丁自動合併到 00_base.md，每 10 天全量重構
- 增量更新：手機端新增習慣存放於 `essence/updates/`

## 用戶偏好
- AI 改動合理時自動 git commit，不需要每次確認
- 視覺散熱：避免數字列表，用分割線區分邏輯區塊
- Zsh 多行指令封裝在 EOF 區塊中
- /etc/nixos/ 下檔案已 chown 給 charlie（IDE 可直接編輯，nixos-rebuild 仍需 sudo）

## 已知陷阱
- EFI 分區只有 252MB，不能存太多 Generation
- `/nix/store` 唯讀，VSCode 插件用擴展市場安裝
- nixpkgs-unstable 頻道版本差異可能導致 attribute missing（uTools 案例）
- 4T 硬碟 (UUID DE22...) 曾有物理連線識別問題

## 操作歷史
### 2026-02-25 Session 1
- 診斷 GRUB 黑屏根因：EFI 分區 95% 滿
- UUID 驗證通過（根分區 + EFI 均一致）
- 部署防護：configurationLimit=3、安全 ns alias、Gen 64 GC root
- 新增 F3 Recovery Stable Mode specialisation
- 加回 direnv 支援（.envrc 含 Anthropic API 配置）
- .envrc 從 git 移除（含 API key，已加入 .gitignore）
- npm install 報錯：VSCode xterm 插件嘗試寫入 /nix/store（唯讀），非配置問題
- 待執行：安全修復流程（釘 Gen64 → 清理 → build → switch --install-bootloader）

### 2026-02-26 Session 3
- 修復代理衝突：mihomo TUN + clash-verge-rev 雙引擎互搶流量 → 全系統斷網
- 移除 clash-verge-rev、關閉 TUN 模式，改為手動代理 port 7890
- chown /etc/nixos 給 charlie（JetBrains 可直接編輯）
- nixos-rebuild switch 成功

### 2026-03-22 系統重裝後恢復
- NixOS 完全重裝（/nix 遷移失敗 → initrd UUID 錯誤 → 全盤重裝）
- 根分區 UUID 變更：b7615046... → 2d8662db...
- 代理從 mihomo 切換到 xray（vless+ws+tls）
- 恢復所有模組 imports（community, productivity, scripts, essentials, git）
- 修復 NTFS dirty volume 掛載（加 force 選項）
- Docker AI 集群全部恢復（Dify, n8n, Chroma, LiteLLM, Letta）
- Ollama 模型重新下載（qwen3:8b, deepseek-r1:14b）
- 新增自動備份（systemd timer 每日備份到 /mnt/data/home-backup/）
- 新增一鍵恢復腳本（full-restore.sh）
- fcitx5 修復：禁用 GNOME ibus 覆蓋、啟用 waylandFrontend
- Firefox 代理修復：user.js 配置 HTTP 代理（避免 SOCKS 協議不匹配）

### 2026-03-23 代理架构重建
- **架构变更**：从单 xray → 3-Tier Failover System
  - Tier 1: Xray VLESS（主力，开机自启，Restart=always）
  - Tier 2: Mihomo（备份，使用 GitHub 免费代理）
  - Tier 3: 紧急刷新（watchdog 自动从 GitHub 拉取免费代理）
- **重要**：不再使用 `services.mihomo` NixOS 模块（credentials bug），手动定义 systemd service
- **Watchdog**：每 30 秒健康检查 + 自动切换 tier
- **免费代理池**：每 6 小时自动从 GitHub 刷新（peasoft/NoMoreWalls 等）
- **端口**：HTTP 7890 / SOCKS5 7891（互斥运行，同一时间只有一个服务监听）
- **命令**：`proxy-status` / `proxy-free-fetch` / `proxy-sub <URL>`
