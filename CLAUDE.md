# NixOS 系統維護手冊 — Charlie's Snowflake

## 架構概覽
- Flake 架構，入口 `flake.nix`，輸出端點 `charlie`
- UEFI + GRUB 引導，EFI 掛載於 `/boot`（252MB，與 Windows 11 共用）
- 桌面：GNOME + GDM，GPU：NVIDIA RTX 3060 Ti（閉源驅動）
- 雙系統：NixOS + Windows 11（同一 NVMe）

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
- `modules/ai.nix`：AI 相關服務（Ollama、OpenClaw）
- `modules/storage.nix`：儲存掛載
- `modules/productivity.nix`：生產力工具
- `user/charlie.nix`：用戶級配置

## specialisation
- `F3 - Recovery Stable Mode`：開機選單救援選項，強制啟用 NetworkManager + allowUnfree
