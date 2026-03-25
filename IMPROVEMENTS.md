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
