# NixOS 系統維護手冊 — Charlie's Snowflake
# 完整系統上下文見 CONTEXT.md（跨 AI 共用）

## 架構概覽
- Flake 架構，入口 `flake.nix`，輸出端點 `charlie`
- UEFI + GRUB 引導，EFI 掛載於 `/boot`（252MB，與 Windows 11 共用）
- 桌面：GNOME + GDM，GPU：NVIDIA RTX 3060 Ti（閉源驅動）
- 雙系統：NixOS + Windows 11（同一 NVMe）
- 無 WiFi 硬體（桌機 Intel H510），僅 USB 有線網路

## 關鍵分區 UUID
- 根分區 `/`：`b7615046-fc37-443c-a249-4caca7ed6edd`（ext4，nvme0n1p9）
- EFI `/boot`：`FA67-631E`（vfat，nvme0n1p2）

## 已知問題與修復歷史
### 2026-02 GRUB 黑屏事件
- 症狀：預設 Generation 開機黑屏，掉進 `grub>` 命令行
- 根因：EFI 分區 252MB 爆滿（95%），GRUB 寫入不完整
- 修復：LiveCD 進入 → 手動選 Gen 64 → 重寫 GRUB
- 防護措施已部署：
  1. `configurationLimit = 3`：限制 GRUB 保留 Generation 數量
  2. `ns` alias 改為先 build 再 switch：防止壞配置直接切換
  3. Gen 64 釘死為 GC root：`/nix/var/nix/gcroots/pinned-stable-gen64`

## 安全操作規範
- 重構指令：`ns`（先 build 驗證，成功才 switch + --install-bootloader）
- 清理指令：`nc`（nix-collect-garbage -d，不會刪除被釘住的 Generation）
- 緊急回滾：
  ```bash
  sudo nix-env --profile /nix/var/nix/profiles/system --switch-generation 64
  sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch
  ```

## 配置結構
- `configuration.nix`：主配置（引導、桌面、網路、用戶、套件）
- `hardware-configuration.nix`：硬體偵測（UUID、kernel modules）
- `modules/proxy.nix`：代理方案（mihomo HTTP/SOCKS5 代理，無 TUN）
- `modules/ai.nix`：AI 相關服務（Ollama、OpenClaw）
- `modules/storage.nix`：儲存掛載
- `modules/productivity.nix`：生產力工具

## 代理架構（2026-02-26 更新）
- mihomo：系統級代理，開機自啟，port 7890，手動代理模式（無 TUN）
- metacubexd：Web UI 面板，http://127.0.0.1:9090/ui（節點切換用）
- networking.proxy：系統環境變數，git/curl 等自動走代理
- 訂閱更新：`sudo proxy-sub <URL>`（自動追加 &flag=meta）
- 訂閱格式：需 `&flag=meta` 參數取得 mihomo YAML 格式
- 已移除：clash-verge-rev（與 mihomo TUN 衝突，且無獨立訂閱）
- 已移除：TUN 模式（避免劫持全部流量導致斷網）
- Firefox 需手動設定代理 127.0.0.1:7890 或用 FoxyProxy 擴展

## specialisation
- `F3 - Recovery Stable Mode`：開機選單救援選項，強制啟用 NetworkManager + allowUnfree

## 用戶偏好
- 改動合理時自動 git commit，不需要每次確認
- 保持 CLAUDE.md 和 CONTEXT.md 同步更新，記錄每次操作結果
- CONTEXT.md 是跨 AI 共享的上下文檔案（Gemini、Claude 等共用）

## 操作日誌
### 2026-02-25 Session 1
- 診斷 GRUB 黑屏根因：EFI 分區 95% 滿
- UUID 驗證通過（根分區 + EFI 均一致）
- 部署防護：configurationLimit=3、安全 ns alias、Gen 64 GC root
- 新增 F3 Recovery Stable Mode specialisation
- 加回 direnv 支援（.envrc 含 Anthropic API 配置）
- .envrc 從 git 移除（含 API key，已加入 .gitignore）
- npm install 報錯：VSCode 內部 xterm 插件嘗試寫入 /nix/store（唯讀），非配置問題
- 待執行：安全修復流程（釘 Gen64 → 清理 → build → switch --install-bootloader）

### 2026-02-26 Session 2
- 診斷 WiFi：桌機無 WiFi 硬體（Intel H510），僅 USB 有線網路
- 選定代理方案：mihomo + clash-verge-rev（取代 flclash/dae）
- 建立 modules/proxy.nix：services.mihomo + programs.clash-verge + networking.proxy
- 清理 configuration.nix：移除壞掉的 clashTUI 服務、手動 dae 服務、flclash/dae/clash-meta 套件
- 下載訂閱配置（liangxin.xyz，&flag=meta 取得 mihomo YAML 格式）
- 訂閱含節點：香港、新加坡、日本、美國、韓國、台灣（vless + hysteria2）

### 2026-02-26 Session 3
- 修復代理衝突：mihomo TUN + clash-verge-rev 雙引擎互搶流量導致全系統斷網
- 移除 clash-verge-rev（無獨立訂閱，與 mihomo 衝突）
- 關閉 TUN 模式：改為手動代理（port 7890），不再劫持全部流量
- 從 mihomo 訂閱配置中移除已注入的 TUN 段
- chown /etc/nixos 給 charlie 用戶（JetBrains 可直接編輯，不需 root）
- nixos-rebuild switch 成功，直連 + 代理均正常
