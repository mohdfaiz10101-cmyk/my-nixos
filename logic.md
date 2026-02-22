# NixOS AI 工作站部署邏輯存檔 (2026-02-22)

## 🛠️ OpenClaw Gateway 啟動邏輯
- **子指令修正**: 必須使用 `gateway --port 18789`，單獨執行 `openclaw` 只會顯示 Help。
- **強行覆蓋 (mkForce)**: 針對模組內建的 `RestartSec` 與路徑定義，必須用 `lib.mkForce` 平定優先級衝突。
- **環境補丁**: 注入 `HOME = /var/lib/openclaw`，解決 Node.js 執行時找不到家目錄導致的 Crash Loop。
- **自動化初始化**: 透過 `ExecStartPre` 產生 `openclaw.json` 並帶上 `--allow-unconfigured` 參數，實現無人值守啟動。

## 🧠 Ollama-CUDA 加速邏輯
- **進度接關**: 即使重構多次，Nix Store 仍保留了 77% 的編譯進度，最終成功啟用 GPU 加速。
- **端口**: 穩定運行於 `11434`。

## 📊 Excel 視覺還原邏輯
- **合併儲存格處理**: 針對不規則表格，採用「座標廣播」算法。
- **流程**: `openpyxl` 掃描區域 -> 取得左上角首值 -> 填充至整個矩陣範圍 -> 輸出 Markdown。
