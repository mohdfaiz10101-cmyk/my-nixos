# Claude Code 權限與操作規範

## 核心原則
- **先問後做**：所有可能影響系統穩定性的操作，必須先獲得用戶明確許可
- **記錄所有變更**：每次操作完成後，必須記錄到 Obsidian 筆記
- **永不修改 UUID**：系統分區 UUID 是生命線，任何情況下都不能改動

---

## 需要明確許可的操作類別

### 1. 系統級操作（必須問）
- `nixos-rebuild switch`：應用配置變更並重啟服務
- `nixos-rebuild boot`：變更下次開機的系統配置
- `nix-collect-garbage`：清理舊 Generation
- `reboot` / `shutdown`：重啟或關機
- 修改 `hardware-configuration.nix`：硬件配置文件
- 修改 GRUB 引導配置（`boot.loader.*`）
- 修改分區掛載（`fileSystems.*`）
- 修改用戶密碼或權限

### 2. 破壞性操作（必須問）
- `docker system prune`：刪除未使用的 Docker 資源
- `git reset --hard`：丟棄本地修改
- `git push --force`：強制推送覆蓋遠端
- `rm -rf`：遞歸刪除目錄
- 刪除任何服務的數據目錄（如 `/mnt/ai/ollama`）
- 停用正在運行的關鍵服務（xray, ollama, docker）

### 3. 網路與代理操作（必須問）
- 修改 `modules/proxy.nix`：代理配置
- 修改 `networking.proxy`：系統代理環境變數
- 修改防火牆規則（`networking.firewall.*`）
- 停用或重啟 xray / mihomo 服務

### 4. Git 操作（根據情況）
- **不需問**：`git add`, `git commit`, `git pull`（日常操作）
- **必須問**：`git push`（推送到 GitHub）
- **必須問**：`git reset`, `git rebase`, `git cherry-pick`（歷史修改）
- **必須問**：修改 `.gitignore`（可能意外曝光敏感文件）

---

## 可以自動執行的操作

### 1. 只讀操作（完全允許）
- `Read`：讀取任何文件
- `Grep`, `Glob`：搜索文件
- `git status`, `git diff`, `git log`：查看 Git 狀態
- `docker ps`, `systemctl status`：查看服務狀態
- `df`, `du`, `ls`：查看磁盤和文件
- `curl`, `ping`：測試網路連接

### 2. 配置文件編輯（允許，但需記錄）
- 編輯 `.nix` 配置文件（除了 `hardware-configuration.nix`）
- 編輯 `.md` 文檔
- 編輯 `.sh` 腳本
- 編輯 `.yaml`, `.json` 配置

### 3. 輕量級操作（允許）
- 創建 `/tmp/` 下的臨時文件
- 創建用戶目錄下的文件（`/home/charlie/`）
- `git add`, `git commit`（本地操作）
- 啟動 Docker 容器（`docker compose up -d`）
- 重啟單個 Docker 容器（`docker restart`）

---

## 特殊規則

### UUID 不可變原則
以下 UUID **永遠不能修改**：
- 根分區 `/`：`2d8662db-7f69-49a6-b396-ef96dc3e0b23`（nvme0n1p9）
- EFI `/boot`：`FA67-631E`（nvme0n1p2）
- 數據盤 `/mnt/data`：`C672D33272D32649`（sda4）
- 1.8T 硬碟 `/mnt/storage_1.8t`：`B2BCF4DBBCF49B55`（sdb1）

如果用戶要求修改 UUID 或者你發現 UUID 不匹配，**必須拒絕並解釋風險**。

### 代理不可斷原則
- 代理（xray）是系統的生命線，不能隨意停用
- 修改代理配置前，必須先測試新配置可用性
- 如果修改導致代理失敗，必須立即回滾

### 自動記錄原則
每完成一次操作後，必須：
1. 更新 `CLAUDE.md` 操作日誌（簡要記錄）
2. 寫入 Obsidian 筆記（詳細記錄，見下方格式）
3. 如果修改了配置，運行 `git commit`

---

## Obsidian 筆記格式規範

### 位置
`~/Documents/Obsidian/System-Maintenance/`

### 文件命名
`YYYY-MM-DD-操作摘要.md`

### 筆記模板
```markdown
---
date: YYYY-MM-DD
tags: [NixOS, 配置, 修復, Docker, AI, 代理]
status: completed
---

# YYYY-MM-DD - 操作摘要

## 背景
用戶要求：<用戶的原始請求>

## 問題診斷
- 問題現象：
- 根本原因：
- 相關文件：

## 解決方案
### 步驟
1. 第一步操作
2. 第二步操作
3. 驗證結果

### 修改的文件
- `/etc/nixos/configuration.nix` - 添加 tmux 配置
- `/etc/nixos/modules/proxy.nix` - 修復連接警告

### 執行的命令
```bash
sudo nixos-rebuild switch --flake /etc/nixos#charlie
docker compose -p autogen up -d
```

## 結果
- ✅ AutoGen 容器啟動成功
- ✅ tmux 配置生效
- ⚠️ xray 連接警告仍存在（待修復）

## 遺留問題
- [ ] 修復 xray "connection ends" 警告
- [ ] 添加 GitHub SSH key

## 相關鏈接
- [[CLAUDE.md]]
- [[CONTEXT.md]]
- [[2026-03-14-系統重裝事件]]
```

---

## 操作流程範例

### 範例 1：用戶要求 "重建系統"
```
Claude: 我將執行 nixos-rebuild switch，這會應用配置變更並重啟服務。
        已修改的文件：
        - /etc/nixos/configuration.nix (添加 tmux)
        - /etc/nixos/CONTEXT.md (更新日期)

        是否繼續？[y/n]
```

### 範例 2：用戶要求 "修改代理"
```
Claude: 修改代理配置是高風險操作，可能導致系統斷網。
        我將：
        1. 備份當前配置
        2. 測試新配置的連通性
        3. 如果測試通過，才應用變更

        是否繼續？[y/n]
```

### 範例 3：用戶要求 "推送 Git"
```
Claude: 我將推送以下提交到 GitHub：
        - 8359d96 feat: switch proxy from mihomo to xray
        - 9032f6e add missing modules

        SSH key 已配置，是否繼續？[y/n]
```

---

## 緊急情況例外

以下情況可以**不詢問**直接執行：
1. **系統已經損壞**（如代理失效、服務崩潰）且修復不會造成更大損失
2. **用戶明確說明 "不要詢問"** 或 "自動執行"
3. **回滾操作**（如 `git reset` 回到上一個提交，`systemctl restart` 重啟失敗的服務）

---

## 總結檢查清單

每次操作前問自己：
- [ ] 這個操作會修改系統配置嗎？→ **問**
- [ ] 這個操作會刪除數據嗎？→ **問**
- [ ] 這個操作會影響代理或網路嗎？→ **問**
- [ ] 這個操作會推送到遠端嗎？→ **問**
- [ ] 這個操作會修改 UUID 嗎？→ **拒絕**
- [ ] 這個操作只是讀取信息嗎？→ **直接執行**
- [ ] 這個操作可以輕易撤銷嗎？→ **直接執行**

每次操作後檢查：
- [ ] 操作成功了嗎？
- [ ] 有沒有寫入 Obsidian 筆記？
- [ ] 有沒有更新 CLAUDE.md？
- [ ] 有沒有 git commit？
