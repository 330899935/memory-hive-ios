#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
hive-import — 蜂巢投喂格式转换器（引流小工具 · 独立可跑 · 零依赖）

把一个文件夹里的 Markdown / 纯文本 / JSON 笔记，转成蜂巢 `/api/ingest`
能直接接收的标准 JSON，并可选地直接投喂到你的蜂巢。

安全设计（本工具的红线）：
  - 不硬编码任何蜂巢地址、任何钥匙；
  - 钥匙只由你通过 --key 或环境变量 HIVE_MASTER_KEY 传入，本工具原样透传，绝不落盘；
  - 本工具只做「格式转换 + HTTP 转发」，不读写蜂巢的仓库/索引/鉴权任何内部实现。

用法：
  python3 hive-import.py convert <输入文件或目录> -o 输出.json
  python3 hive-import.py send 输出.json --url http://127.0.0.1:8768 --key 你的钥匙
  python3 hive-import.py convert <输入> --dry-run   # 只打印，不写文件
"""

import argparse
import json
import os
import sys
import urllib.request
import urllib.error

QUALITY_MIN_TITLE = 5
QUALITY_MIN_CONTENT = 20


# ─────────────────────────── 转换 ───────────────────────────

def _title_from_filename(path: str) -> str:
    return os.path.splitext(os.path.basename(path))[0].strip()


def _md_to_entry(text: str, path: str) -> dict:
    """Markdown：第一个 # 标题当 title，其余当 content。"""
    lines = text.splitlines()
    title = _title_from_filename(path)
    body_lines = []
    title_picked = False
    for ln in lines:
        s = ln.strip()
        if not title_picked and s.startswith("#"):
            t = s.lstrip("#").strip()
            if t:
                title = t
                title_picked = True
            continue
        body_lines.append(ln)
    content = "\n".join(body_lines).strip()
    if not content:
        content = text.strip()
    return {"title": title, "content": content, "type": "markdown"}


def _txt_to_entry(text: str, path: str) -> dict:
    """纯文本：第一行当 title，其余当 content。"""
    lines = [l for l in text.splitlines() if l.strip()]
    if not lines:
        return {"title": _title_from_filename(path), "content": "", "type": "text"}
    title = lines[0].strip()
    content = "\n".join(lines[1:]).strip()
    return {"title": title, "content": content, "type": "text"}


def _load_json(path: str) -> list:
    with open(path, encoding="utf-8") as f:
        obj = json.load(f)
    if isinstance(obj, dict):
        obj = [obj]
    if not isinstance(obj, list):
        raise ValueError(f"JSON 顶层必须是对象或数组：{path}")
    out = []
    for it in obj:
        if not isinstance(it, dict):
            continue
        title = it.get("title") or it.get("name") or it.get("summary") or ""
        content = it.get("content") or it.get("text") or it.get("body") or ""
        if title or content:
            out.append({"title": str(title), "content": str(content),
                        "type": str(it.get("type", "text"))})
    return out


def convert_path(path: str) -> list:
    """把文件或目录转成条目列表。"""
    entries = []
    files = []
    if os.path.isdir(path):
        for root, _dirs, names in os.walk(path):
            for n in names:
                ext = os.path.splitext(n)[1].lower()
                if ext in (".md", ".markdown", ".txt", ".json"):
                    files.append(os.path.join(root, n))
    else:
        files = [path]

    for fp in files:
        try:
            ext = os.path.splitext(fp)[1].lower()
            with open(fp, encoding="utf-8") as f:
                text = f.read()
            if ext in (".md", ".markdown"):
                entries.append(_md_to_entry(text, fp))
            elif ext == ".txt":
                entries.append(_txt_to_entry(text, fp))
            elif ext == ".json":
                entries.extend(_load_json(fp))
        except Exception as e:  # noqa: BLE001
            print(f"⚠ 跳过 {fp}：{e}", file=sys.stderr)
    return entries


def to_ingest(entries, source="import", tags=None) -> list:
    """把条目组装成蜂巢 /api/ingest 的 body 数组（不含钥匙，钥匙在发送时注入）。"""
    out = []
    for i, e in enumerate(entries):
        title = str(e.get("title", "")).strip()
        content = str(e.get("content", "")).strip()
        if not title:
            print(f"⚠ 第 {i + 1} 条无标题，已跳过", file=sys.stderr)
            continue
        if len(title) > 500:
            print(f"⚠ 第 {i + 1} 条标题超 500 字，已截断", file=sys.stderr)
            title = title[:500]
        if len(title) < QUALITY_MIN_TITLE or len(content) < QUALITY_MIN_CONTENT:
            print(f"⚠ 第 {i + 1} 条（标题 {len(title)} 字 / 正文 {len(content)} 字）可能被蜂巢质量门槛拒收"
                  f"（门槛：标题≥{QUALITY_MIN_TITLE} 字且正文≥{QUALITY_MIN_CONTENT} 字）", file=sys.stderr)
        out.append({
            "title": title,
            "content": content,
            "type": e.get("type", "text"),
            "source": source,
            "tags": tags or ["待确认"],
        })
    return out


# ─────────────────────────── 发送 ───────────────────────────

def send_entries(entries, base_url, master_key, dry_run=False):
    """逐条 POST 到 {base_url}/api/ingest。钥匙由调用方传入，本函数不落盘。"""
    url = base_url.rstrip("/") + "/api/ingest"
    ok, fail = 0, 0
    for i, body in enumerate(entries):
        payload = dict(body)
        payload["master_key"] = master_key
        if dry_run:
            print(f"[dry-run] 第 {i + 1} 条 → {url}  title={body['title'][:30]!r}")
            continue
        req = urllib.request.Request(
            url, data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"}, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                r = json.loads(resp.read().decode("utf-8"))
                st = r.get("status", "?")
                print(f"第 {i + 1} 条 → {st}  {body['title'][:30]!r}")
                ok += 1
        except urllib.error.HTTPError as e:
            print(f"第 {i + 1} 条 → HTTP {e.code}  {body['title'][:30]!r}", file=sys.stderr)
            fail += 1
        except Exception as e:  # noqa: BLE001
            print(f"第 {i + 1} 条 → 发送失败：{e}", file=sys.stderr)
            fail += 1
    return ok, fail


# ─────────────────────────── 入口 ───────────────────────────

def main():
    ap = argparse.ArgumentParser(description="蜂巢投喂格式转换器")
    sub = ap.add_subparsers(dest="cmd", required=True)

    c = sub.add_parser("convert", help="转换文件/目录为蜂巢 ingest JSON")
    c.add_argument("input", help="输入文件或目录")
    c.add_argument("-o", "--out", help="输出 JSON 文件路径")
    c.add_argument("--source", default="import", help="source 字段（默认 import）")
    c.add_argument("--tags", help="tags，逗号分隔")
    c.add_argument("--dry-run", action="store_true", help="只打印不写文件")

    s = sub.add_parser("send", help="把 convert 产出的 JSON 投喂到蜂巢")
    s.add_argument("json_file", help="convert 产出的 JSON 文件")
    s.add_argument("--url", default=os.environ.get("HIVE_URL", "http://127.0.0.1:8768"))
    s.add_argument("--key", default=os.environ.get("HIVE_MASTER_KEY", ""))
    s.add_argument("--dry-run", action="store_true", help="只打印不真发")

    args = ap.parse_args()

    if args.cmd == "convert":
        entries = convert_path(args.input)
        tags = [t.strip() for t in (args.tags or "").split(",") if t.strip()] or None
        ingest = to_ingest(entries, source=args.source, tags=tags)
        if args.dry_run:
            print(json.dumps(ingest, ensure_ascii=False, indent=2))
            return
        out_path = args.out or "hive_import.json"
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(ingest, f, ensure_ascii=False, indent=2)
        print(f"✅ 转换 {len(ingest)} 条 → {out_path}")
        return

    if args.cmd == "send":
        with open(args.json_file, encoding="utf-8") as f:
            entries = json.load(f)
        if not isinstance(entries, list):
            print("JSON 顶层必须是数组", file=sys.stderr)
            sys.exit(1)
        if not args.key:
            print("缺少钥匙：用 --key 传，或设环境变量 HIVE_MASTER_KEY", file=sys.stderr)
            sys.exit(1)
        ok, fail = send_entries(entries, args.url, args.key, dry_run=args.dry_run)
        print(f"\n完成：成功 {ok} / 失败 {fail}")
        sys.exit(1 if fail else 0)


if __name__ == "__main__":
    main()
