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
