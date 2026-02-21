
## 4. 自動化工作流 (2026-02-21 新增)
- **git up**: 一鍵完成「Add + Commit + Push」流程。
- **安全性校驗**: 透過 git.nix 內置的 core.excludesfile 選項，確保 up 指令永遠不會將敏感文件 (user-secrets.nix) 推送到雲端。

## 5. 當前系統狀態 (2026-02-21)
- **Ollama**: 已成功編譯並啟動 (ollama-cuda)，支持 GPU 加速。
- **存儲**: 4T 數據硬碟已自動掛載於 /mnt/data。
- **待辦**: OpenClaw 因 GitHub API 限制暫時註解，待 Rate Limit 恢復後取消 modules/ai.nix 中的註解並修復 Hash。
