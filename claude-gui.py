import tkinter as tk
from tkinter import scrolledtext
import requests
import os

# 调用 Claude API
def call_claude():
    prompt = input_text.get("1.0", tk.END).strip() or "hello，请输出一句话测试"
    try:
        response = requests.post(
            "https://hone.vvvv.ee/v1/chat/completions",
            json={
                "model": "claude-opus-4-6",
                "messages": [{"role": "user", "content": prompt}],
                "max_tokens": 200
            },
            headers={
                "Authorization": f"Bearer {os.getenv('ANTHROPIC_AUTH_TOKEN')}",
                "Content-Type": "application/json"
            },
            timeout=10
        )
        result = response.json()["choices"][0]["message"]["content"]
        output_text.delete("1.0", tk.END)
        output_text.insert(tk.END, result)
    except Exception as e:
        output_text.delete("1.0", tk.END)
        output_text.insert(tk.END, f"❌ 错误：{str(e)}")

# 创建 GUI 窗口
root = tk.Tk()
root.title("Claude 一键调用")
root.geometry("600x400")

# 输入框
tk.Label(root, text="提问内容：").pack(pady=5)
input_text = scrolledtext.ScrolledText(root, height=8)
input_text.pack(padx=10, fill=tk.BOTH)
input_text.insert(tk.END, "hello，请输出一句话测试")

# 调用按钮
tk.Button(root, text="调用 Claude", command=call_claude, bg="#4CAF50", fg="white").pack(pady=5)

# 输出框
tk.Label(root, text="响应结果：").pack(pady=5)
output_text = scrolledtext.ScrolledText(root, height=8)
output_text.pack(padx=10, fill=tk.BOTH)

# 运行窗口
root.mainloop()
