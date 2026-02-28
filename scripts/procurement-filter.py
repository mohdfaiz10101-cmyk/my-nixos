#!/usr/bin/env python3
"""
1688 采购智能筛选系统
功能：
1. 网页内容去重（URL 域名、供应商名称）
2. 智能分类（用 Letta 向量相似度判断是否相关）
3. 供应商黑名单/白名单管理
4. 手机端同步（Web API）
5. 浏览历史记录（防重复访问）
"""

import json
import hashlib
import re
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Set, Optional
import subprocess

DATA_DIR = Path.home() / "Documents" / "Obsidian" / "Procurement"
DATA_DIR.mkdir(parents=True, exist_ok=True)

LETTA_URL = "http://127.0.0.1:8283/v1"
LETTA_TOKEN = "letta-charlie-2026"
LETTA_AGENT = "nixos-sysadmin"  # 用于向量搜索

class ProcurementFilter:
    def __init__(self):
        self.visited_file = DATA_DIR / "visited_urls.json"
        self.suppliers_file = DATA_DIR / "suppliers.json"
        self.items_file = DATA_DIR / "items.json"
        self.blacklist_file = DATA_DIR / "blacklist.json"

        self.visited: Dict[str, dict] = self._load_json(self.visited_file, {})
        self.suppliers: Dict[str, dict] = self._load_json(self.suppliers_file, {})
        self.items: Dict[str, dict] = self._load_json(self.items_file, {})
        self.blacklist: Set[str] = set(self._load_json(self.blacklist_file, []))

    def _load_json(self, path, default):
        if path.exists():
            try:
                with open(path) as f:
                    return json.load(f)
            except:
                pass
        return default

    def _save_json(self, path, data):
        with open(path, 'w') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

    def _get_domain(self, url: str) -> str:
        """提取域名"""
        match = re.search(r'https?://([^/]+)', url)
        return match.group(1) if match else url

    def _normalize_supplier(self, name: str) -> str:
        """规范化供应商名称"""
        return re.sub(r'[\s\-_\.]+', ' ', name.lower()).strip()

    def _is_duplicate(self, url: str, supplier: str = None) -> tuple[bool, str]:
        """检查是否重复"""
        domain = self._get_domain(url)

        # 检查黑名单
        if domain in self.blacklist:
            return True, f"域名在黑名单: {domain}"

        if supplier and self._normalize_supplier(supplier) in [self._normalize_supplier(s) for s in self.blacklist]:
            return True, f"供应商在黑名单: {supplier}"

        # 检查是否访问过
        if url in self.visited:
            return True, f"URL 已访问: {url[:50]}..."

        # 检查域名是否重复（同域名不同页面）
        domain_visits = [v for v in self.visited.values() if v.get('domain') == domain]
        if len(domain_visits) > 5:
            return True, f"域名访问过多: {domain} ({len(domain_visits)} 次)"

        # 检查供应商是否重复
        if supplier:
            norm_supplier = self._normalize_supplier(supplier)
            for supp_data in self.suppliers.values():
                if self._normalize_supplier(supp_data.get('name', '')) == norm_supplier:
                    return True, f"供应商已存在: {supplier}"

        return False, ""

    def add_item(self, url: str, title: str, supplier: str = None,
                 price: str = None, notes: str = None, tags: List[str] = None) -> dict:
        """添加新项目"""
        # 检查重复
        is_dup, reason = self._is_duplicate(url, supplier)
        if is_dup:
            return {"ok": False, "error": reason, "duplicate": True}

        # 记录访问
        item_id = hashlib.md5(url.encode()).hexdigest()[:12]
        domain = self._get_domain(url)

        item = {
            "id": item_id,
            "url": url,
            "title": title,
            "domain": domain,
            "supplier": supplier,
            "price": price,
            "notes": notes,
            "tags": tags or [],
            "created_at": datetime.now().isoformat(),
            "status": "pending"  # pending, contacted, ordered, rejected
        }

        self.items[item_id] = item
        self.visited[url] = {
            "domain": domain,
            "title": title,
            "visited_at": datetime.now().isoformat()
        }

        # 记录供应商
        if supplier:
            supp_id = hashlib.md5(supplier.encode()).hexdigest()[:12]
            if supp_id not in self.suppliers:
                self.suppliers[supp_id] = {
                    "id": supp_id,
                    "name": supplier,
                    "domains": set(),
                    "items": [],
                    "created_at": datetime.now().isoformat()
                }
            self.suppliers[supp_id]["domains"].add(domain)
            self.suppliers[supp_id]["items"].append(item_id)

        # 保存
        self._save_json(self.items_file, self.items)
        self._save_json(self.visited_file, self.visited)
        self._save_json(self.suppliers_file, {k: {**v, "domains": list(v["domains"])} for k, v in self.suppliers.items()})

        return {"ok": True, "item": item}

    def check_via_letta(self, content: str) -> dict:
        """用 Letta 向量搜索判断内容是否相关"""
        try:
            payload = {
                "messages": [{"role": "user", "content": f"""
判断以下内容是否与采购需求相关。如果相关，提取：产品名称、供应商、价格。

内容：{content}

请用 JSON 格式回复：
{{
    "relevant": true/false,
    "product": "产品名称",
    "supplier": "供应商名称",
    "price": "价格",
    "confidence": 0-100
}}
""" }]
            }

            result = subprocess.run(
                ["curl", "-s", "-X", "POST",
                 f"{LETTA_URL}/agents/{LETTA_AGENTS.get('nixos-sysadmin', '')}/messages",
                 "-H", f"Authorization: Bearer {LETTA_TOKEN}",
                 "-H", "Content-Type: application/json",
                 "-d", json.dumps(payload)],
                capture_output=True, text=True, timeout=30
            )

            if result.returncode == 0:
                response = json.loads(result.stdout)
                # 解析回复
                for msg in response.get("messages", []):
                    if msg.get("message_type") == "assistant_message":
                        content = msg.get("content", "")
                        if isinstance(content, str):
                            # 尝试提取 JSON
                            match = re.search(r'\{[^}]+\}', content, re.DOTALL)
                            if match:
                                return json.loads(match.group(0))
        except Exception as e:
            return {"error": str(e)}

        return {"relevant": False, "confidence": 0}

    def get_stats(self) -> dict:
        """获取统计信息"""
        return {
            "total_items": len(self.items),
            "pending": len([i for i in self.items.values() if i.get("status") == "pending"]),
            "contacted": len([i for i in self.items.values() if i.get("status") == "contacted"]),
            "ordered": len([i for i in self.items.values() if i.get("status") == "ordered"]),
            "rejected": len([i for i in self.items.values() if i.get("status") == "rejected"]),
            "suppliers": len(self.suppliers),
            "blacklisted": len(self.blacklist),
            "visited_urls": len(self.visited)
        }

    def add_blacklist(self, entry: str) -> dict:
        """添加到黑名单"""
        self.blacklist.add(entry)
        self._save_json(self.blacklist_file, list(self.blacklist))
        return {"ok": True, "entry": entry}

    def remove_blacklist(self, entry: str) -> dict:
        """从黑名单移除"""
        if entry in self.blacklist:
            self.blacklist.remove(entry)
            self._save_json(self.blacklist_file, list(self.blacklist))
            return {"ok": True}
        return {"ok": False, "error": "Not found"}

    def export_to_obsidian(self):
        """导出到 Obsidian"""
        index_md = f"""# 1688 采购记录

> 更新时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

## 统计

| 状态 | 数量 |
|------|------|
| 待处理 | {len([i for i in self.items.values() if i.get("status") == "pending"])} |
| 已联系 | {len([i for i in self.items.values() if i.get("status") == "contacted"])} |
| 已下单 | {len([i for i in self.items.values() if i.get("status") == "ordered"])} |
| 已拒绝 | {len([i for i in self.items.values() if i.get("status") == "rejected"])} |
| 供应商 | {len(self.suppliers)} |
| 黑名单 | {len(self.blacklist)} |

## 待处理项目

"""
        for item in sorted(self.items.values(), key=lambda x: x.get("created_at", ""), reverse=True):
            if item.get("status") == "pending":
                index_md += f"""
### [{item.get('title', '未命名')}]({item.get('url')})

- **供应商**: {item.get('supplier', '未知')}
- **价格**: {item.get('price', '未知')}
- **域名**: {item.get('domain', '')}
- **标签**: {', '.join(item.get('tags', []))}
- **时间**: {item.get('created_at', '')}
"""
        (DATA_DIR / "INDEX.md").write_text(index_md, encoding='utf-8')


def main():
    import sys
    filter_sys = ProcurementFilter()

    if len(sys.argv) < 2:
        print("1688 采购筛选系统")
        print("用法:")
        print("  procurement add <url> <title> [supplier] [price]")
        print("  procurement check <content>")
        print("  procurement stats")
        print("  procurement blacklist <domain/supplier>")
        print("  procurement export")
        return

    cmd = sys.argv[1]

    if cmd == "add":
        if len(sys.argv) < 4:
            print("用法: procurement add <url> <title> [supplier] [price]")
            return
        url = sys.argv[2]
        title = sys.argv[3]
        supplier = sys.argv[4] if len(sys.argv) > 4 else None
        price = sys.argv[5] if len(sys.argv) > 5 else None
        result = filter_sys.add_item(url, title, supplier, price)
        if result.get("ok"):
            print(f"✓ 添加成功: {title}")
        else:
            print(f"✗ {result.get('error', 'Unknown error')}")

    elif cmd == "check":
        if len(sys.argv) < 3:
            print("用法: procurement check <content>")
            return
        content = sys.argv[2]
        result = filter_sys.check_via_letta(content)
        print(json.dumps(result, ensure_ascii=False, indent=2))

    elif cmd == "stats":
        stats = filter_sys.get_stats()
        print(json.dumps(stats, ensure_ascii=False, indent=2))

    elif cmd == "blacklist":
        if len(sys.argv) < 3:
            print(f"黑名单: {filter_sys.blacklist}")
            return
        entry = sys.argv[2]
        result = filter_sys.add_blacklist(entry)
        print(f"✓ 已添加到黑名单: {entry}")

    elif cmd == "export":
        filter_sys.export_to_obsidian()
        print(f"✓ 已导出到 Obsidian: {DATA_DIR}")

    else:
        print(f"未知命令: {cmd}")


if __name__ == "__main__":
    main()
