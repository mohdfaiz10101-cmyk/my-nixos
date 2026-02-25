# NixOS 系統上下文 — Charlie's Snowflake
# 此檔案供所有 AI 助手共用（Claude、Gemini 等），請勿刪除

## 系統架構
- OS: NixOS (Flake 架構)，Flake 入口 `flake.nix`，輸出端點 `charlie`
- 引導: UEFI + GRUB，EFI 掛載 `/boot`（252MB，與 Windows 11 共用同一 NVMe）
- 桌面: GNOME + GDM
- GPU: NVIDIA RTX 3060 Ti（閉源驅動，GA104）
- CPU: Intel（啟用 KVM）
- 網路: NetworkManager + 代理 127.0.0.1:7890

## 分區佈局
| 分區 | UUID | 類型 | 掛載點 |
|------|------|------|--------|
| nvme0n1p9 | b7615046-fc37-443c-a249-4caca7ed6edd | ext4 | / |
| nvme0n1p2 | FA67-631E | vfat | /boot |
| sda1-4 | (見 lsblk) | ntfs | 資料碟 |
| sdb1 | (見 lsblk) | ntfs | 外接硬碟 2T |

## 配置檔案結構
```
/etc/nixos/
├── flake.nix              # Flake 入口
├── configuration.nix      # 主配置（引導、桌面、網路、用戶、套件）
├── hardware-configuration.nix  # 硬體偵測（UUID、kernel modules）
├── .envrc                 # direnv 環境變數（API keys，不進 git）
├── modules/
│   ├── ai.nix             # Ollama + OpenClaw 閘道器
│   ├── storage.nix        # 儲存掛載
│   └── productivity.nix   # 生產力工具
└── user/
    └── charlie.nix        # 用戶級配置
```

## 關鍵設計決策
1. **EFI 防爆滿**: `configurationLimit = 3`，GRUB 最多保留 3 個 Generation
2. **安全重構流程**: `ns` alias = 先 `build` 驗證 → 成功才 `switch --install-bootloader`
3. **Gen 64 釘死**: GC root 在 `/nix/var/nix/gcroots/pinned-stable-gen64`，永不被清理
4. **F3 救援模式**: specialisation "F3 - Recovery Stable Mode"，強制啟用 NetworkManager + allowUnfree
5. **efiInstallAsRemovable**: 寫入 `/EFI/BOOT/BOOTX64.EFI`，防華碩 BIOS 重置後認不到碟

## 常用指令
| 指令 | 用途 |
|------|------|
| `ns` | 安全重構（build → switch + install-bootloader） |
| `nc` | 清理舊 Generation（pinned 的不會被刪） |
| `ai-log` | 查看 Ollama + OpenClaw 日誌 |

## 緊急回滾
```bash
sudo nix-env --profile /nix/var/nix/profiles/system --switch-generation 64
sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch
```

## 已知陷阱
- `/nix/store` 是唯讀的，不能在裡面跑 `npm install`
- EFI 分區只有 252MB，不能存太多 Generation
- VSCode 插件安裝用擴展市場（Ctrl+Shift+X），不要用 npm

## 操作歷史
### 2026-02-25
- GRUB 黑屏修復：根因是 EFI 分區 95% 滿，GRUB 寫入不完整
- 部署 configurationLimit + 安全 alias + Gen 64 GC root + F3 救援模式
- 加回 direnv 支援
- 待執行：安全修復流程（釘 Gen64 → 清理 → build → switch）
