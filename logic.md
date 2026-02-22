# NixOS AI 工作站部署邏輯存檔 (2026-02-22)

## 1. 核心組件狀態
- **Ollama-CUDA**: 監聽 `11434`，已確認 GPU 加速就緒。
- **OpenClaw Gateway**: 監聽 `18789`，提供 AI 網關與 UI 控制面板。
- **存儲**: 4T 硬碟掛載於 `/mnt/data`。

## 2. OpenClaw 關鍵修正邏輯
- **指令修正**: `openclaw` 為多功能 CLI，必須顯式呼叫 `gateway --port 18789` 子指令。
- **衝突解決**: 透過 `lib.mkForce` 強行覆蓋 `systemd` 模組內建的預設參數（如 `RestartSec`）。
- **權限與路徑**: 
    - 注入 `HOME = /var/lib/openclaw` 解決 Node.js 運行時的配置寫入需求。
    - 使用 `ExecStartPre` 自動生成 `openclaw.json` 以繞過互動式設定。
- **性能優化**: 設置 `TimeoutStartSec = 300`，確保 1.4GB 級別的引擎加載不會觸發系統超時殺進程。

## 3. Excel 不規則表格解析邏輯
- **問題**: 合併單元格（Merged Cells）在讀取時會導致數據斷裂（除首格位外均為 NaN）。
- **解決方案**: 
    1. 使用 `openpyxl` 掃描 `ws.merged_cells.ranges`。
    2. 建立坐標矩陣，將合併區域的首格值「廣播」到整個區域。
    3. 轉換為 Markdown 表格，確保 Ollama 提取時的上下文連續性。

## 4. 運作流程
1. 修改 `/etc/nixos/modules/ai.nix`。
2. 執行 `sudo -E nixos-rebuild switch --flake .#charlie --option sandbox false`。
3. 執行 `sudo git up` 同步邏輯至雲端。
