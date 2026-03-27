# NixOS AI 工作站部署邏輯存檔 (2026-02-22)

## 🏗️ 基礎設施
- **Ollama-CUDA**: 本地大腦 (Port 11434)。
- **OpenClaw Gateway**: 數據門戶 (Port 18789)，已解決啟動超時與權限衝突。
- **Unstructured API**: 表格視覺還原引擎 (Port 8000)，容器化運行。

## 📊 數據處理邏輯 (Unstructured + Ollama)
- **步驟**: Unstructured 將 Excel 視覺解析為 JSON/HTML -> 座標廣播還原合併儲存格 -> 餵給 Ollama 提取。
- **優勢**: 針對不規則、多合併單元格的合同，準確率提升 80% 以上。

## ☁️ 同步狀態
- 已設置 `sudo git up` 別名，確保所有邏輯變更即時備份。

## 💾 磁碟空間評估 (2026-02-22)
- **磁碟狀態**: `/` 分區 (nvme0n1p9) 總量 89G，初始可用 25G。
- **評估**: Unstructured 鏡像約 9-12G，剩餘空間足以支撐部署。
- **監控指令**: `watch -n 1 df -h /` 用於追蹤下載期間的磁碟消耗。

## 📝 系統狀態與生產力配置 (2026-02-22 - 階段二)

### 🤖 AI 服務狀態 (OpenClaw)
- **進度**: Gateway 已成功啟動並在背景運行 (PID: 61293)。
- **邏輯**: 透過 `productivity.nix` 中的 `oneshot` 補丁強制對接本地 Ollama (11434)。
- **驗證**: `systemctl status openclaw-gateway` 回傳 active。

### 🛠️ 生產力工具 (uTools)
- **調整**: 由於 `nixpkgs` 頻道版本差異導致 `attribute missing`，已切換至 **AppImage 方案**。
- **路徑**: 下載至 `~/Apps/uTools.AppImage`，使用 `appimage-run` 啟動。
- **衝突處理**: 需手動停用 Plasma 6 KRunner 的 Alt+Space。

### 🎨 VS Code 視覺分段系統
- **外觀注入**: 已注入 `settings.json` (行高 28, Sticky Scroll, 彩色括號)。
- **模板注入**: 已注入 `nix.json` Snippets，支援 `ok` (成功塊) 與 `err` (錯誤塊) 快速分段。
- **錯誤監控**: 安裝 `Error Lens` 實現行內報錯噴火效果。

### 🗄️ 存儲與數據
- **現狀**: `/mnt/contract_data` (sdb4) 已掛載。
- **遺留**: 4T 硬碟 (UUID DE22...) 仍未識別，暫列為物理連線檢查項。

## 🧠 記憶系統架構 (2026-03-27 新增)
- **5層防護系統**: 解決 AI Agent 換賬號後記憶丟失問題
  1. **SessionStart Hook** - 每次會話開始強制加載記憶（~/.claude/hooks/session-init.sh）
  2. **Letta 長期記憶** - 4 個 Agents + 7 層健康防護（每5分鐘檢查）
  3. **ChromaDB 向量庫** - 雖運行但 Letta 實際使用 Ollama nomic-embed-text
  4. **自動備份系統** - 每小時備份到 /mnt/pool/backups/memory/（保留7天）
  5. **文件系統冗余** - memory/ + Obsidian + CONTEXT.md 三重存儲
- **根本原因**: LLM context window 是臨時的，換 API 賬號 = 新會話 = 丟失所有 context
- **解決方案**: 多層冗余存儲 + 強制初始化協議
