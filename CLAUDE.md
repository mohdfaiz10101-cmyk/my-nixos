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
- 遠端恢復：`nix-recover`（Git pull 最新配置 → build → switch，自動處理代理）
- 緊急回滾：
  ```bash
  # 方法 1：GRUB 選 Gen 64 開機，然後拉遠端配置重建
  nix-recover

  # 方法 2：手動切回 Gen 64
  sudo nix-env --profile /nix/var/nix/profiles/system --switch-generation 64
  sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch
  ```

## 配置結構
- `configuration.nix`：主配置（引導、桌面、網路、用戶、套件）
- `hardware-configuration.nix`：硬體偵測（UUID、kernel modules）
- `modules/proxy.nix`：代理方案（mihomo HTTP/SOCKS5 代理，無 TUN）
- `modules/ai.nix`：AI 相關服務（Ollama、OpenClaw、Letta）
- `modules/storage.nix`：儲存掛載
- `modules/productivity.nix`：生產力工具

## 代理架構（2026-02-27 更新）
- mihomo：系統級代理，開機自啟，port 7890，手動代理模式（無 TUN）
- allow-lan: true（Docker 容器需要通過代理訪問外部 API）
- 防火牆已開放 7890（Docker 網段訪問用）
- proxy-sub 腳本自動注入 `allow-lan: true`（訂閱配置預設 false）
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
- **自動模式優先**：所有操作自動確認，不需要每次詢問
- 改動合理時自動 git commit，不需要每次確認
- 保持 CLAUDE.md 和 CONTEXT.md 同步更新，記錄每次操作結果
- CONTEXT.md 是跨 AI 共享的上下文檔案（Gemini、Claude 等共用）
- 錯誤與踩坑也要記錄到 CLAUDE.md，避免跨 session 重複犯錯

## cc-switch 配置（2026-02-28）
- cc-switch 數據庫：`~/.cc-switch/cc-switch.db`
- JetBrains 插件（Claude Code GUI by codemossai）從此數據庫讀取 provider 配置
- 導入腳本：`/tmp/import-cc-switch.py`（從 `~/.claude/settings.json` 導入）
- Provider ID：`b6b4d75b-5f43-45ac-8b3f-a6c872a6aa52`
- 數據庫 schema：providers 表包含 id, app_type, name, settings_config, is_current 等欄位
- 插件讀取邏輯：`~/.local/share/JetBrains/IntelliJIdea2025.3/idea-claude-code-gui/ai-bridge/read-cc-switch-db.js`

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
- 新增 nix-recover 遠端恢復腳本（Git pull → build → switch，自動偵測代理）
- nixos-rebuild switch 成功，直連 + 代理均正常

## AI 服務架構（2026-02-27 更新）
- Ollama：本地推理後端，CUDA 加速，port 11434，數據存放 `/mnt/ai/ollama`
- OLLAMA_KEEP_ALIVE=30m（冷啟動要 50 秒，30 秒太短會頻繁卸載）
- 已安裝模型：qwen3:8b、deepseek-r1:14b
- OpenClaw：API 閘道器，port 18789，預設模型 qwen3:8b
- Gemini API key 存放於 `/etc/nixos/secrets/letta.env`（已 gitignore）
- Gemini 免費額度已用完（2026-02-27），需要升級付費方案或等待重置
- secrets 目錄不進 git

## AI 自動化集群（2026-02-27 部署）
- 所有服務容器化，compose 文件位於 `/mnt/ai/ai-cluster/`
- Dify：多模態 AI 入口，port 3000，初始密碼 `charlie2026`
  - compose: `/mnt/ai/ai-cluster/dify/docker/docker-compose.yaml`
  - 數據: `/mnt/ai/ai-cluster/dify/docker/volumes/`
  - 含 PostgreSQL + Redis + Weaviate + Sandbox + Plugin Daemon
- n8n：自動化工作流引擎，port 5678
  - compose: `/mnt/ai/ai-cluster/n8n/docker-compose.yml`（project: n8n2）
  - 數據: `/mnt/ai/n8n-data/`
- Chroma：向量知識庫，port 8000
  - compose: `/mnt/ai/ai-cluster/chroma/docker-compose.yml`（project: chroma2）
  - 數據: `/mnt/ai/chroma-data/`
- AutoGen Studio：核心調度大腦，port 8080，自建鏡像（autogenstudio 0.4.2）
  - compose: `/mnt/ai/ai-cluster/autogen/docker-compose.yml`（project: autogen）
  - 數據: `/mnt/ai/autogen-data/`
  - 支援 Ollama (host.docker.internal:11434) + Claude + Gemini API
- LiteLLM：智能路由代理，port 4000，master_key: `sk-litellm-charlie-2026`
  - compose: `/mnt/ai/ai-cluster/litellm/docker-compose.yml`（project: litellm）
  - 路由配置: `/mnt/ai/ai-cluster/litellm/config.yaml`
  - 容器已配置 HTTP_PROXY/HTTPS_PROXY 指向 host.docker.internal:7890
  - auto 路由 = Gemini Flash（需代理出網，免費額度已用完待重置）
  - 直選模型：local/qwen3-8b, local/deepseek-r1-14b, cloud/claude-opus, cloud/gemini-flash, cloud/gemini-pro
  - Fallback 鏈：qwen3 → deepseek → gemini-flash；claude → gemini-pro
  - 踩坑：LiteLLM routing_strategy 不尊重 priority（usage-based-routing-v2 和 simple-shuffle 都不行）
- 知識洗鍊引擎：`/mnt/ai/ai-cluster/knowledge-distiller/`
  - 輸入: `/mnt/ai/conversations/`（放入 Gemini/Claude JSON 導出）
  - 運行: `cd /mnt/ai/ai-cluster/knowledge-distiller && docker compose -p distiller --profile run up`
  - 用 DeepSeek-R1 遞歸總結 → Chroma 覆蓋寫入

## IDE 整合（2026-02-27 更新）
- JetBrains Continue 插件：AI 編碼助手
  - 配置: `~/.continue/config.yaml`（新版 schema v1，需要 name/version/schema 欄位）
  - config.json 已棄用，新版用 config.yaml
  - Chat 模型：Qwen3 8B + DeepSeek R1（直連 Ollama）、Claude Opus（走 LiteLLM）
  - Tab 補全：Qwen3 8B（直連 Ollama）
  - 踩坑：qwen3/deepseek-r1 的 thinking mode 導致 content 為空
    - Ollama OpenAI 兼容端點不支持 `think: false`
    - LiteLLM 的 `merge_reasoning_content_in_choices` 在 streaming 模式下無效
    - Continue 的 `requestOptions.extraBodyProperties` 無法正確傳遞 `think: false`
    - 解法：Continue 用原生 Ollama provider 直連（繞過 LiteLLM）
  - LiteLLM 保留給 Claude Opus 等需要路由/代理的雲端模型

## 存儲架構（2026-02-26 更新）
- 系統盤 `/`：nvme0n1p9，89GB ext4（保持 <70% 使用率）
- sda4 `/mnt/data`：932GB NTFS（UUID: C672D33272D32649）
- `/mnt/ai`：100GB ext4 loopback 映像（位於 /mnt/data/ai-data.img）
  - Docker data-root：`/mnt/ai/docker`
  - Ollama 模型：`/mnt/ai/ollama`
  - Letta 數據：`/mnt/ai/letta`
- EFI `/boot`：252MB（configurationLimit=3 防溢出）

### 2026-02-27 Session 5
- 修復 Docker containerd snapshot 嚴重損坏（上次拉鏡像中斷導致）
- 完全重置 Docker data-root，清理 18 個幽靈容器
- 部署 AI 自動化集群：Dify (port 3000) + n8n (port 5678) + Chroma (port 8000)
- 所有服務數據落盤 /mnt/ai，系統盤 64%，/mnt/ai 31%

### 2026-02-27 Session 6
- 踩坑：Continue 插件只寫了 config.yaml，但 JetBrains 版 (v1.0.60) 需要 config.json 才能識別
- 補寫 `~/.continue/config.json`，插件恢復正常
- 新增用戶偏好：錯誤與踩坑必須記錄到 CLAUDE.md，防止重複

### 2026-02-27 Session 7 — Continue 插件 + LiteLLM 全鏈路調試
- Continue config.yaml 升級到 schema v1（需要 name/version/schema 頂層欄位，models 用 name 不用 title）
- 診斷 Continue "Generating..." 卡住問題，根因鏈：
  1. qwen3/deepseek-r1 thinking mode 導致 streaming 回應只有 `reasoning_content`，`content` 為空
  2. LiteLLM `usage-based-routing-v2` 和 `simple-shuffle` 都不尊重 model_info.priority
  3. Gemini Flash 從 LiteLLM 容器出網超時（mihomo 只聽 127.0.0.1，Docker 容器訪問不到）
  4. 開放 mihomo allow-lan + 防火牆 7890 後，Gemini 免費額度已用完（429）
- 修復措施：
  - Ollama KEEP_ALIVE 從 30s → 30m（減少冷啟動）
  - mihomo allow-lan: true + 防火牆開 7890（Docker 容器代理出網）
  - proxy-sub 腳本自動注入 allow-lan: true
  - LiteLLM 容器加 HTTP_PROXY/HTTPS_PROXY 環境變數
  - LiteLLM config 加 `drop_params: true` + `merge_reasoning_content_in_choices: true`
  - Continue 改用原生 Ollama provider 直連（繞過 LiteLLM thinking mode 問題）
  - LiteLLM 保留給 Claude Opus 等雲端模型
- nixos-rebuild switch 成功（OLLAMA_KEEP_ALIVE + 防火牆 7890）
- 待驗證：Continue Ollama provider 是否正確處理 thinking mode

## 省Token優化方案（2026-02-28）
- **Prompt Caching**：已啟用 `promptCaching` 和 `cacheSystemPrompt`
- **智譜 GLM**：已配置 GLM-4.7、GLM-4.5-air、GLM-4.5-x
  - API Key: `sk-3knUH8p2ErRr7j6Lgg7soCmsUTolna0eSb2Qq2qGwVDmL2pq`
  - 優勢：128K 上下文自動緩存，系統 Prompt 100% 命中
  - 成本：比 Claude 便宜 90%
- **Redis 緩存**：LiteLLM 已啟用 Redis 緩存（port 6380）
  - 緩存命中率：通過 Dashboard `/api/token-stats` 查看
- **預估節省**：50-90% token消耗

## Obsidian 記憶管理（2026-02-28）
- **Letta → Obsidian 同步**：`letta-obsidian` 腳本
  - 導出 core memory + archival memory
  - YAML frontmatter（agent、timestamp、tags）
  - 同步日誌記錄
- **記憶碎片管理系統**：`memory-manage` 腳本
  - 從 Claude history + Letta 收集碎片
  - 自動打標籤（規則引擎，不耗 token）
  - 重要性評分（0-10）
  - 30 天未訪問自動歸檔
  - 按標籤導出到 Obsidian
- **Obsidian Vault**：`~/Documents/Obsidian/`
  - `Letta-Memory/` - Letta 記憶（按 agent 分類）
  - `Memory-Fragments/` - 記憶碎片（按標籤分類）
  - `INDEX.md` - 索引文件
- **zsh 後台同步**：每次開終端自動觸發

## 輸入法配置（2026-02-28）
- fcitx5 每窗口記憶狀態
- 環境變量：`GTK_IM_MODULE`、`QT_IM_MODULE`、`XMODIFIERS`
- 默認簡體中文，代碼框保持英文

## Letta 記憶整合（2026-02-27 Session 8）
- 修復 archival memory seeding：embedding 從 letta-free（404）改為 Ollama nomic-embed-text
  - 關鍵：`embedding_endpoint_type` 必須用 `openai`，endpoint 帶 `/v1` 後綴
  - 三個 agent 各插入 31 條知識（CLAUDE.md + CONTEXT.md）
- 新增 `letta-sync.py`：從 Letta API 導出 core memory + archival memory 到 Claude Code 記憶目錄
  - 輸出：`~/.claude/projects/-etc-nixos/memory/letta-memory.md`
- 新增 `letta-sync.sh`：wrapper 腳本，帶 1 小時 cooldown 防重複
- zsh interactiveShellInit 後台自動同步（每次開終端觸發，不阻塞）
- 新增 alias：`letta-sync`（手動觸發同步）
- 踩坑：Letta `ollama` endpoint type 用原生 API，不走 OpenAI 兼容端點，導致 404
  - 解法：用 `openai` type + `http://host.docker.internal:11434/v1`

## NixOS Dashboard（2026-02-27 Session 9）
- 新增統一 Web 控制台：http://127.0.0.1:9099
- 功能：
  - 快捷操作按鈕（系統/AI/代理/Letta 四類命令）
  - 系統狀態監控（磁盤、服務、容器）
  - Letta 對話面板（三個 agent 切換）
  - 命令輸出終端（SSE 流式輸出）
  - 服務鏈接（Dify/n8n/Chroma/LiteLLM/Letta/mihomo）
  - 設為 Recovery 按鈕（釘死當前 generation 為 GC root）
- 技術棧：
  - 後端：Flask + Python 3.13（pythonEnv with packages）
  - 前端：Vanilla JS + Catppuccin Mocha 暗色主題
  - 部署：systemd service (nixos-dashboard.service)
  - 安全：命令白名單 + localhost only + rate limiting
- 文件結構：
  - `/etc/nixos/dashboard/app.py` — Flask 後端
  - `/etc/nixos/dashboard/templates/index.html` — 單頁前端
  - `/etc/nixos/scripts/dashboard.sh` — nix-shell wrapper
- 部署記錄：
  - Generation 102 (2026-02-27 18:09:59)
  - 踩坑：systemd 環境缺 NIX_PATH，改用 pythonEnv.withPackages 解決
  - 服務狀態：active (running)，綁定 127.0.0.1:9099
- Dify OpenAPI 插件配置：Bearer Token 填 `letta-charlie-2026`
  - `modules/ai.nix` — systemd service 配置
- 新增 alias：`dashboard`（打開瀏覽器）
- 防火牆開放 9099 端口
  - 服務鏈接快捷入口
- 技術棧：Flask + vanilla HTML/CSS/JS，Catppuccin Mocha 暗色主題
- 部署：systemd service（nixos-dashboard.service），nix-shell wrapper
- 新增 alias：`dashboard`（打開瀏覽器）
- 文件：
  - `/etc/nixos/dashboard/app.py`：Flask 後端，命令白名單 + 狀態 API + chat API
  - `/etc/nixos/dashboard/templates/index.html`：單頁面前端
  - `/etc/nixos/scripts/dashboard.sh`：nix-shell wrapper
- Dify OpenAPI 插件配置：Bearer Token 填 `letta-charlie-2026`

## NixOS Dashboard（2026-02-27 Session 9）
- 新增統一 Web 控制台：http://127.0.0.1:9099
- 功能：
  - 快捷操作按鈕（系統/AI/代理/Letta 四類命令）
  - 系統狀態監控（磁盤、服務、容器）
  - Letta 對話面板（三個 agent 切換，直接在 Web 聊天）
  - 命令輸出終端（SSE 流式輸出）
  - 知識蒸餾流程說明（Gemini 清洗工作流程文檔）
- 技術棧：
  - 後端：Flask + Python 3.13（nix-shell wrapper）
  - 前端：單頁 HTML + Vanilla JS（Catppuccin Mocha 暗色主題）
  - 部署：systemd 服務 `nixos-dashboard.service`
  - 安全：命令白名單（不接受任何用戶輸入），危險操作需確認
- 文件結構：
  - `/etc/nixos/dashboard/app.py` - Flask 後端
  - `/etc/nixos/dashboard/templates/index.html` - 前端
  - `/etc/nixos/scripts/dashboard.sh` - nix-shell wrapper
  - `configuration.nix` - systemd 服務定義 + `dashboard` alias
- 使用：
  - 啟動：`sudo systemctl start nixos-dashboard`（或 `ns` 後自動啟動）
  - 訪問：`dashboard` alias 或直接打開 http://127.0.0.1:9099
  - 停止：`sudo systemctl stop nixos-dashboard`
- Dify OpenAPI 整合：
  - 新增 `/mnt/ai/ai-cluster/letta/openapi-dify.yaml` - Letta API spec for Dify
  - 6 個端點：listAgents, sendMessage, getCoreMemory, updateCoreMemory, getArchivalMemory, searchArchivalMemory
  - 認證：Bearer Token `letta-charlie-2026`
  - Base URL：`http://host.docker.internal:8283/v1`
- 知識蒸餾工作流程（2026-02-27 更新）：
  - 準備：導出 Gemini/Claude 對話 JSON → 放入 `/mnt/ai/conversations/`
  - 執行：點擊「知識蒸餾」按鈕，DeepSeek-R1 遞歸總結
  - 完成：知識寫入 Chroma（覆蓋模式），Letta agents 可檢索
  - 注意：蒸餾會覆蓋 Chroma 現有數據，執行前需備份
