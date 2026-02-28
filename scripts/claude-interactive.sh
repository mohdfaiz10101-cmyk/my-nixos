#!/usr/bin/env bash
# Claude Code CLI 交互式端点选择器

# 如果有参数且第一个参数不是 chat/code 等子命令，直接传递给 claude
if [[ $# -gt 0 && ! "$1" =~ ^(chat|code|prompt|config|auth)$ ]]; then
    exec claude "$@"
fi

echo "🤖 选择 Claude 连接方式："
echo "1) 官方订阅（直连 Anthropic，最稳定）"
echo "2) LiteLLM 路由（本地模型 + 智能 fallback）"
echo "3) 第三方端点（hone.vvvv.ee）"
echo ""
read -p "请选择 [1-3，默认 2]: " choice

case "${choice:-2}" in
    1)
        echo "✅ 使用官方订阅"
        exec claude "$@"
        ;;
    2)
        echo "✅ 使用 LiteLLM 路由"
        export ANTHROPIC_BASE_URL="http://127.0.0.1:4000"
        export ANTHROPIC_API_KEY="sk-litellm-charlie-2026"
        exec claude "$@"
        ;;
    3)
        echo "✅ 使用第三方端点"
        export ANTHROPIC_BASE_URL="$ANTHROPIC_THIRD_PARTY_URL"
        export ANTHROPIC_API_KEY="$ANTHROPIC_THIRD_PARTY_TOKEN"
        exec claude "$@"
        ;;
    *)
        echo "❌ 无效选择，使用 LiteLLM 路由"
        export ANTHROPIC_BASE_URL="http://127.0.0.1:4000"
        export ANTHROPIC_API_KEY="sk-litellm-charlie-2026"
        exec claude "$@"
        ;;
esac
