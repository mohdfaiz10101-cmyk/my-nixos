# 🛠️ 系統同步與故障恢復邏輯 (Gen 1.1)

---

## 🛡️ Docker 大型映像檔處理
- **異常中斷處理**：若遇到 unexpected EOF，先執行 sudo docker image prune -f，確認空間 > 20GB 再重試。
- **穩定源偏好**：優先使用 quay.io。

---

## ⚙️ 權限與自動化閉環
- **Sudo 慣性**：/etc/nixos/ 下所有操作強制附加 sudo。
- **Git-Action 守則**：補丁存入 updates/ 後 Commit 即觸發雲端合併；隨後本地執行 sudo git pull 清空目錄。

---

## 🖌️ 視覺散熱校準
- **Zsh 貼上保護**：多行指令強制封裝在 EOF 區塊中，避免 # 註解導致解析錯誤。
