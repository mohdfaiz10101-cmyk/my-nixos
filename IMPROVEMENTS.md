# 系统改进追踪 (System Improvements Tracker)

> **创建时间**: 2026-03-22
> **目的**: 记录所有系统错误、改进建议和简化方案

---

## 🔴 当前紧急问题 (Current Critical Issues)

### 1. Docker 代理配置错误
- **问题**: configuration.nix:107-108 中 Docker daemon 代理端口 7890 ✅ 已与 xray 统一（2026-03-23 确认正确）
- **影响**: LiteLLM 等容器无法访问外部网络（GitHub API 等）
- **修复方案**:
  ```nix
  # configuration.nix
  proxies = {
    http-proxy = "http://127.0.0.1:7891";   # 7890 → 7891
    https-proxy = "http://127.0.0.1:7891";  # 7890 → 7891
    no-proxy = "127.0.0.0/8,192.168.0.0/16,localhost,4000,11434,18789";
  };
  ```
- **优先级**: 🔴 高 - 影响所有 Docker 服务外网访问

### 2. fcitx5 中文输入未完全配置
- **问题**: systemd user service 无法启动（D-Bus 连接错误）
- **当前状态**: 使用 autostart .desktop 文件，但每次登录后需手动检查
- **改进方案**: 使用 GNOME session startup script 替代 systemd user service
- **优先级**: 🟡 中 - 不影响使用但需手动检查

### 3. Claude Code 多端点选择复杂度高
- **问题**: claude-interactive.sh 需要每次选择端点（官方/LiteLLM/第三方）
- **用户反馈**: kitty 中出现 403 错误（因选择了异常的 LiteLLM）
- **简化方案**:
  - 默认使用官方 Claude（最稳定）
  - LiteLLM 仅在需要时手动指定
  - 移除第三方端点依赖
- **优先级**: 🟡 中 - 影响用户体验

---

## ✅ 已解决问题 (Resolved Issues)

### 2026-03-22
1. ✅ **xray 连接警告洪水** - 通过 `loglevel="none"` + `StandardOutput/Error="null"` 完全静默
2. ✅ **Claude 凭证未同步** - 创建 claude-sync.sh 自动同步 root → charlie
3. ✅ **缺少权限框架** - 创建 PERMISSION-RULES.md 避免重复询问

---

## 📋 系统简化建议 (Simplification Proposals)

### 1. 代理架构简化
**当前**: xray (vless+ws+tls) 在 7891 端口
**问题**:
- configuration.nix 中 Docker 代理配置错误
- 多处配置不一致（mihomo 残留）
**建议**:
- 统一所有代理配置为 127.0.0.1:7890（已完成）
- mihomo 已作为 Tier 2 备份重新启用（2026-03-23）
- 在 CONTEXT.md 中明确标注代理架构

### 2. Claude Code 端点管理
**当前**: 三个端点（官方/LiteLLM/第三方），交互式选择
**问题**:
- LiteLLM 配置复杂且容易出错
- 第三方端点环境变量未设置
- 用户每次都要选择，增加认知负担
**建议**:
- 默认官方端点（无需环境变量）
- LiteLLM 作为可选 fallback，使用别名 `q-lite`
- 移除第三方端点或在文档中标注为"未配置"

### 3. 输入法管理
**当前**: fcitx5 通过 autostart .desktop + shell script 启动
**问题**:
- 启动时序不稳定（sleep 2 hardcode）
- 环境变量重复配置（systemd/shell/desktop）
**建议**:
- 使用 NixOS i18n.inputMethod 内置机制
- 移除手动 shell script
- 统一环境变量配置位置

### 4. 日志管理
**当前**: 各服务日志分散，部分服务产生大量无用日志
**改进**:
- ✅ xray 已静默
- 🟡 LiteLLM GitHub API 警告（待修复代理后观察）
- 📝 建议：所有服务统一日志级别配置

---

## 🔧 待实施改进 (Pending Improvements)

### 高优先级
- [ ] 修复 Docker daemon 代理端口（7890 → 7891）
- [ ] 测试 LiteLLM 修复后是否正常工作
- [ ] 简化 Claude Code 端点选择逻辑

### 中优先级
- [ ] fcitx5 改用 GNOME session startup
- [ ] 创建系统盘自动扩容脚本（boot 后执行）
- [ ] mihomo 已重新启用为 3-Tier 代理备份（不再需要清理）

### 低优先级
- [ ] 优化 freeze-detector.sh 性能
- [ ] 添加更多自动化测试脚本

---

## 📝 设计原则 (Design Principles)

1. **简单优于复杂** - 能用一个工具解决的不用两个
2. **稳定优于功能** - 优先保证核心功能稳定运行
3. **自动优于手动** - 减少需要用户干预的操作
4. **明确优于隐式** - 配置清晰可读，避免魔法数字
5. **记录优于记忆** - 所有变更记录在 CLAUDE.md 和本文件

---

## 🗺️ 长期规划 (Long-term Roadmap)

### Phase 1: 稳定基础 (Current)
- 修复所有已知 bug
- 简化核心配置

### Phase 2: 自动化增强
- 系统盘自动扩容
- 更智能的服务健康检查
- 自动化备份验证

### Phase 3: 体验优化
- 统一的命令行界面
- 更好的错误提示
- 智能故障恢复

---

**最后更新**: 2026-03-22 18:30
**维护者**: charlie
**AI 助手**: Claude Code (Sonnet 4.5)

## [2026-03-27] AI Agent 記憶系統升級
**問題**: 換 API 賬號後 AI 行為完全改變，記憶丟失
**根本原因**: LLM context window 是臨時的，換賬號 = 新會話 = 丟失所有 context
**解決方案**: 
- SessionStart Hook 強制加載記憶（~/.claude/hooks/session-init.sh）
- 5層防護：Hook + Letta + ChromaDB + 自動備份 + 文件系統
- 每小時自動備份到 /mnt/pool/backups/memory/
**狀態**: ✅ 已完成並測試
**參考**: 
- https://www.linkedin.com/posts/jianfeng-xu-6b36172b_why-your-ai-agent-keeps-losing-its-memory-activity-7434174917727940608-qPDy
- https://plurality.network/blogs/universal-ai-context-to-switch-ai-tools/

## [2026-04-07] Hub 新增 3D 架構流動圖可視化
**問題**: 缺乏系統架構整體視圖，30+ 服務/節點關係難以直觀理解
**解決方案**: 
- 開發 3D 星球架構流動圖（Canvas 渲染引擎）
- 350+ 恆星背景 + 5 片星雲 + 16 個特化 3D 行星節點
- 9 個預設場景展示數據流轉（Claude Code 請求/Aider 重構/AGI 循環等）
- 集成到 Hub 導航（:9800/arch）
**狀態**: ✅ 已完成並上線
**技術細節**:
- 純 HTML + Canvas API，零依賴
- 星球系統：徑向漸變 + 高光反射 + 軌道環 + 卫星系統
- 粒子流動：貝塞爾曲線 + 拖尾動畫 + 節點辉光
- 交互：點擊節點/場景按鈕/鍵盤 1-9/空格自動播放
**文件**: ~/hub/static/arch.html (1500 行)
**配置變更**: nav-config.json + Caddyfile + hub-api.py
