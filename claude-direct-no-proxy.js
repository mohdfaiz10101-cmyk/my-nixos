require('dotenv').config();
const axios = require('axios');

// 直接访问国内中转地址，无代理
async function runClaude() {
  try {
    console.log("🔄 直接访问国内中转接口（无代理）...");
    const response = await axios.post(
      'https://hone.vvvv.ee/v1/chat/completions',
      {
        model: "claude-opus-4-6",
        messages: [{ role: "user", content: "hello，请输出一句话测试" }],
        max_tokens: 100
      },
      {
        headers: {
          'Authorization': `Bearer ${process.env.ANTHROPIC_AUTH_TOKEN}`,
          'Content-Type': 'application/json'
        },
        timeout: 10000
      }
    );
    console.log("✅ Claude 响应成功：");
    console.log(response.data.choices[0].message.content);
  } catch (error) {
    console.log("❌ 错误状态码：", error.response?.status || "无");
    console.log("❌ 错误信息：", error.response?.data || error.message);
  }
}

runClaude();
