import os
import anthropic

# 适配代理（必须保留，访问第三方地址需要）
os.environ["HTTP_PROXY"] = "http://127.0.0.1:7890"
os.environ["HTTPS_PROXY"] = "http://127.0.0.1:7890"

# 初始化客户端（加载你的 Token 和第三方地址）
client = anthropic.Anthropic(
    api_key=os.environ.get("ANTHROPIC_AUTH_TOKEN"),
    base_url=os.environ.get("ANTHROPIC_BASE_URL")
)

# 🔥 核心修改：只测试第三方支持的 Claude 2 模型 🔥
SUPPORTED_MODELS = ["claude-2", "claude-2.1"]

def call_claude():
    print(f"🔹 当前使用【临时】Claude 环境（第三方：hone.vvvv.ee）")
    print(f"🔍 测试支持的模型：{SUPPORTED_MODELS}")
    print(f"🌐 代理配置：{os.environ.get('HTTP_PROXY', '未配置')}")
    
    # 检查核心配置
    if not os.environ.get("ANTHROPIC_AUTH_TOKEN"):
        print("\n❌ 错误：未找到 ANTHROPIC_AUTH_TOKEN（检查 .envrc）")
        return False
    if not os.environ.get("ANTHROPIC_BASE_URL"):
        print("\n❌ 错误：未找到 ANTHROPIC_BASE_URL（检查 .envrc）")
        return False
    
    for model in SUPPORTED_MODELS:
        try:
            response = client.messages.create(
                model=model,
                max_tokens=500,
                temperature=0.7,
                messages=[{"role": "user", "content": "你好，请确认你是 Claude 2 模型，并简单介绍自己"}]
            )
            print(f"\n✅ 模型 {model} 调用成功！")
            print(f"📝 回复：{response.content[0].text}")
            return True
        except anthropic.APIError as e:
            error_info = e.response.json() if (hasattr(e, 'response') and hasattr(e.response, 'json')) else {}
            error_msg = error_info.get('error', {}).get('message', str(e))
            print(f"\n❌ 模型 {model} 失败：{error_msg}")
        except anthropic.APIConnectionError:
            print(f"\n❌ 模型 {model} 连接失败：代理 127.0.0.1:7890 不通，请启动 mihomo")
        except Exception as e:
            print(f"\n❌ 模型 {model} 错误：{str(e)}")

    print("\n❌ 所有模型调用失败！请按以下顺序排查：")
    print("1. 启动 mihomo 代理：sudo mihomo -d /etc/mihomo &")
    print("2. 验证代理：curl --proxy http://127.0.0.1:7890 https://hone.vvvv.ee")
    print("3. 确认 Token/Base URL 正确（.envrc 中已配置）")
    return False

if __name__ == "__main__":
    call_claude()
