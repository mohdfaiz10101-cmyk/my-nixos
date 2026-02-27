require('dotenv').config();
const Anthropic = require('@anthropic-ai/sdk');

// 初始化客户端（复用你的 Token/Base URL）
const anthropic = new Anthropic({
  apiKey: process.env.ANTHROPIC_AUTH_TOKEN,
  baseURL: process.env.ANTHROPIC_BASE_URL,
});

// 测试所有可能的模型别名（服务商自定义的极简标识）
const MODEL_ALIASES = [
  "claude",          // 极简别名（最可能）
  "opus",            // 仅模型类型
  "claude-opus",     // 组合别名
  "claude-3",        // 仅大版本
  "claude-3.5",      // 3.5 简写
  "claude-2",        // 标准 2 代
  "claude-2.1",      // 2.1 代
  "claude-3-opus",   // 标准 3 opus
  "claude-3-5-opus", // 标准 3.5 opus
  "default"          // 服务商默认别名
];

// 批量测试所有别名
async function testAllModels() {
  console.log(`🔍 测试服务商 ${process.env.ANTHROPIC_BASE_URL} 的所有模型别名...\n`);
  
  for (const model of MODEL_ALIASES) {
    try {
      const response = await anthropic.messages.create({
        model: model,
        max_tokens: 100,
        messages: [{ role: "user", content: "ping" }], // 极简请求，减少负载
        timeout: 10000 // 超时时间
      });
      console.log(`✅ 模型 ${model}：调用成功！响应：${response.content[0].text.slice(0, 20)}...`);
      process.exit(0); // 找到可用模型，直接退出
    } catch (e) {
      // 只打印核心错误，不刷屏
      console.log(`❌ 模型 ${model}：${e.message.split('{')[0].trim()}（错误码：${e.statusCode}）`);
    }
  }

  console.log(`\n❌ 所有别名测试失败！确认：`);
  console.log(`1. 服务商 ${process.env.ANTHROPIC_BASE_URL} 是否支持 Anthropic 新版 API（/v1/messages）？`);
  console.log(`2. Token ${process.env.ANTHROPIC_AUTH_TOKEN.slice(0, 10)}... 是否在服务商侧已授权？`);
}

testAllModels();
