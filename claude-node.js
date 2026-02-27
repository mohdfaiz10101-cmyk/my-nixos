// 加载环境变量（和你之前的 .envrc 兼容）
require('dotenv').config();
const Anthropic = require('@anthropic-ai/sdk');

// 初始化客户端（复用你的 Token/Base URL）
const anthropic = new Anthropic({
  apiKey: process.env.ANTHROPIC_AUTH_TOKEN,
  baseURL: process.env.ANTHROPIC_BASE_URL,
});

// 调用 Claude（用兼容的模型名）
async function callClaude() {
  try {
    const response = await anthropic.messages.create({
      model: "claude-2", // 第三方支持的模型
      max_tokens: 500,
      messages: [{ role: "user", content: "你好，确认你是 Claude 并简单介绍" }],
    });
    console.log("✅ 调用成功：", response.content[0].text);
  } catch (e) {
    console.log("❌ 错误：", e.message);
  }
}

callClaude();
