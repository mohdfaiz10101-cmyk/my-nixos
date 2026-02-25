require('dotenv').config();
const axios = require('axios');
const https = require('https');

// New API 平台的核心配置（vvvv.ee 专用）
const API_KEY = process.env.ANTHROPIC_AUTH_TOKEN;
const BASE_URL = `${process.env.ANTHROPIC_BASE_URL}/v1/chat/completions`;
const MODEL = "claude-3-opus";

// 修复 TLS 代理配置（解决握手断开问题）
const httpsAgent = new https.Agent({
  rejectUnauthorized: false, // 兼容部分代理的证书
  secureProtocol: 'TLSv1_3_method', // 强制 TLS 1.3
  ALPNProtocols: ['h2', 'http/1.1'], // 匹配 vvvv.ee 的 ALPN
  keepAlive: true,
  keepAliveMsecs: 30000
});

// 用 OpenAI 格式调用 Claude（适配 New API 网关）
async function callClaudeViaNewAPI() {
  console.log(`🔍 适配 vvvv.ee New API 平台调用 Claude...`);
  console.log(`🔑 Token：${API_KEY.slice(0, 10)}...`);
  console.log(`🌐 地址：${BASE_URL}`);

  try {
    const response = await axios.post(
      BASE_URL,
      {
        model: MODEL,
        messages: [{ role: "user", content: "你好，请确认你是 Claude 3 Opus 模型" }],
        max_tokens: 500,
        temperature: 0.7
      },
      {
        headers: {
          "Authorization": `Bearer ${API_KEY}`,
          "Content-Type": "application/json",
          "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"
        },
        // 修复代理配置：使用 httpsAgent + 明确代理协议
        proxy: {
          protocol: 'http:', // 代理是 HTTP 协议，不是 HTTPS
          host: "127.0.0.1",
          port: 7890
        },
        httpsAgent: httpsAgent,
        timeout: 60000 // 延长超时时间
      }
    );

    console.log(`\n✅ 调用成功！`);
    console.log(`📝 Claude 回复：${response.data.choices[0].message.content}`);
  } catch (error) {
    console.log(`\n❌ 调用失败：`);
    if (error.response) {
      console.log(`状态码：${error.response.status}`);
      console.log(`错误信息：${JSON.stringify(error.response.data)}`);
    } else if (error.request) {
      console.log(`请求已发送但无响应：${error.message}`);
    } else {
      console.log(`请求构建错误：${error.message}`);
    }
  }
}

callClaudeViaNewAPI();
