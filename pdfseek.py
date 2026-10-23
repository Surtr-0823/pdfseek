#!/usr/bin/env python3
"""pdfseek — 在 PDF 中搜索文字，输出文件名和页码（跨平台版）。

用法:
    pip install pypdf
    python3 pdfseek.py "に欠かせない" [PDF 文件或文件夹...]

默认忽略短语内部的换行/空格，因此被 PDF 排版拆行的短语也能命中。
"""

import argparse
import os
import re
import sys
import unicodedata

try:
    from pypdf import PdfReader
except ImportError:  # pragma: no cover
    sys.exit("pdfseek: 需要 pypdf，请先运行: pip install pypdf")

TOOL_NAME = "pdfseek"
TOOL_VERSION = "1.0.0"
USE_COLOR = sys.stdout.isatty()


def paint(text: str, code: str) -> str:
    return f"\x1b[{code}m{text}\x1b[0m" if USE_COLOR else text


def natural_key(path: str):
    """让 2.pdf 排在 10.pdf 前面。"""
    return [int(part) if part.isdigit() else part.lower()
            for part in re.split(r"(\d+)", path)]


def collect_pdfs(paths):
    found = []
    for path in paths:
        if os.path.isdir(path):
            for root, dirs, files in os.walk(path):
                dirs.sort(key=natural_key)
                for name in files:
                    if name.lower().endswith(".pdf"):
                        found.append(os.path.join(root, name))
        elif os.path.isfile(path):
            found.append(path)
        else:
            print(f"{TOOL_NAME}: 找不到路径: {path}", file=sys.stderr)

    seen = set()
    unique = []
    for path in found:
        key = os.path.realpath(path)
        if key not in seen:
            seen.add(key)
            unique.append(path)
    return sorted(unique, key=natural_key)


def display_path(path):
    try:
        rel = os.path.relpath(path)
    except ValueError:
        return path
    return path if rel.startswith("..") else rel


def build_pattern(needle, exact):
    escaped = [re.escape(ch) for ch in needle]
    return "".join(escaped) if exact else r"\s*".join(escaped)


def context_text(text, start, end, context):
    lo = max(0, start - context)
    hi = min(len(text), end + context)
    return re.sub(r"\s+", " ", text[lo:hi]).strip()


def parse_args(argv):
    parser = argparse.ArgumentParser(
        prog=TOOL_NAME,
        description="在 PDF 中搜索文字，输出文件名和页码。"
                    "默认忽略短语内部的换行/空格，适合搜索日文短语。",
        add_help=False,
    )
    parser.add_argument("needle", nargs="?", help="要搜索的文字")
    parser.add_argument("paths", nargs="*", help="PDF 文件或文件夹（默认当前目录）")
    parser.add_argument("-C", "--context", type=int, default=60,
                        help="匹配前后各显示 N 个字符（默认 60）")
    parser.add_argument("-l", "--files-only", action="store_true",
                        help="只列出命中的文件和命中次数")
    parser.add_argument("-p", "--pages-only", action="store_true",
                        help="只列出命中的页码")
    parser.add_argument("-m", "--max-per-page", type=int, default=5,
                        help="每页最多显示 N 条匹配（默认 5，0 表示全部）")
    parser.add_argument("-i", "--ignore-case", action="store_true",
                        help="不区分拉丁字母大小写")
    parser.add_argument("-W", "--whole", action="store_true",
                        help="精确匹配，不忽略短语内部的空白/换行")
    parser.add_argument("-h", "--help", action="help",
                        help="显示帮助并退出")
    parser.add_argument("-v", "--version", action="version",
                        version=f"{TOOL_NAME} {TOOL_VERSION}",
                        help="显示版本并退出")

    args = parser.parse_args(argv)
    if not args.needle:
        parser.print_help()
        sys.exit(2)
    if not args.paths:
        args.paths = ["."]
    if args.context < 0 or args.max_per_page < 0:
        parser.error("N 必须是非负整数")
    return args


def main(argv=None):
    args = parse_args(argv)
    pdfs = collect_pdfs(args.paths)
    if not pdfs:
        print(f"{TOOL_NAME}: 没有找到 PDF 文件", file=sys.stderr)
        return 2

    flags = re.IGNORECASE if args.ignore_case else 0
    # NFKC 归一化：有些 PDF 把汉字提取成康熙部首（如「欠」→「⽋」），
    # 归一化后两者才能匹配上
    needle = unicodedata.normalize("NFKC", args.needle)
    try:
        pattern = re.compile(build_pattern(needle, args.whole), flags)
    except re.error as exc:
        print(f"{TOOL_NAME}: 无法构造搜索模式: {exc}", file=sys.stderr)
        return 2

    total_hits = 0
    files_with_hits = 0
    searched_files = 0
    had_error = False

    for pdf_path in pdfs:
        shown_path = display_path(pdf_path)
        try:
            reader = PdfReader(pdf_path)
            if reader.is_encrypted:
                try:
                    reader.decrypt("")
                except Exception:
                    pass
        except Exception:
            print(f"{TOOL_NAME}: 无法打开 {shown_path}（可能不是 PDF 或文件损坏）",
                  file=sys.stderr)
            had_error = True
            continue

        searched_files += 1
        file_hits = 0
        pages_with_hits = []
        text_pages = 0

        for page_index, page in enumerate(reader.pages, start=1):
            try:
                text = page.extract_text() or ""
            except Exception:
                text = ""
            if not text.strip():
                continue
            text_pages += 1

            search_text = unicodedata.normalize("NFKC", text)
            matches = list(pattern.finditer(search_text))
            if not matches:
                continue

            file_hits += len(matches)
            pages_with_hits.append(page_index)

            if args.files_only or args.pages_only:
                continue

            limit = args.max_per_page
            for match in matches[:limit] if limit > 0 else matches:
                ctx = context_text(search_text, match.start(), match.end(), args.context)
                print(f"{paint(shown_path, '36')}:{paint(str(page_index), '32')}: {ctx}")
            if limit > 0 and len(matches) > limit:
                rest = len(matches) - limit
                print(f"{paint(shown_path, '36')}:{paint(str(page_index), '32')}: "
                      f"…（本页另有 {rest} 处匹配）")

        if file_hits > 0:
            files_with_hits += 1
            total_hits += file_hits
            if args.files_only:
                pages = ", ".join(str(p) for p in pages_with_hits)
                print(f"{paint(shown_path, '36')}: {file_hits} 处（第 {pages} 页）")
            elif args.pages_only:
                for page in pages_with_hits:
                    print(f"{paint(shown_path, '36')}:{paint(str(page), '32')}")
        elif text_pages == 0:
            print(f"{TOOL_NAME}: 提示: {shown_path} 没有可提取的文字"
                  f"（可能是扫描版 PDF，需要先 OCR）", file=sys.stderr)

    if total_hits == 0:
        print(f"未找到「{args.needle}」（已搜索 {searched_files} 个 PDF）", file=sys.stderr)
        return 2 if had_error else 1

    if USE_COLOR and not args.files_only and not args.pages_only:
        print(f"共 {total_hits} 处匹配，位于 {files_with_hits} 个文件", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
