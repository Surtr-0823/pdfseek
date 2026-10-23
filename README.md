# pdfseek

在 PDF 里搜文字，直接告诉你**哪个文件、第几页**。

默认忽略短语内部的换行和空格，所以特别适合在日语语法书 / 资料 PDF 中查找像
「に欠かせない」这样可能被排版拆成两行的语法点。

## 功能

- 一次搜索一个文件夹里的所有 PDF（含子文件夹）
- 日文短语跨行匹配：`に欠かせない` 能匹配 `に欠かせ\nない`
- 输出 `文件:页码: 上下文`，一眼就知道该翻到哪一页
- `-l` 只列文件，`-p` 只列页码
- 扫描版 PDF（没有文字层）会提示需要 OCR

## 两个版本

| 版本 | 适用平台 | 依赖 |
| --- | --- | --- |
| Swift 版 | macOS | 系统自带 PDFKit；构建需要 Xcode Command Line Tools |
| Python 版 | Windows / macOS / Linux | Python 3.8+，`pip install pypdf` |

## 构建（macOS Swift 版）

```bash
git clone https://github.com/Surtr-0823/pdfseek.git
cd pdfseek
./build.sh                       # 生成 ./pdfseek
cp pdfseek ~/.local/bin/         # 可选：装到 PATH 里，之后直接跑 pdfseek
```

如果没有 `swiftc`：

```bash
xcode-select --install
```

## 使用

```bash
# 搜索当前文件夹（递归）里的所有 PDF
./pdfseek "に欠かせない"

# 搜索指定文件夹
./pdfseek "に欠かせない" ~/Documents/日语资料

# 搜索指定的几个文件
./pdfseek "に欠かせない" 1.pdf 2.pdf 3.pdf

# 只想知道在哪几个文件里
./pdfseek -l "に欠かせない" .

# 只要页码
./pdfseek -p "に欠かせない" .

# 显示更长的上下文（前后各 120 字）
./pdfseek -C 120 "に欠かせない" .
```

输出示例：

```
1.pdf:12: …日常生活に欠かせない存在です…
5.pdf:3: …コミュニケーションに欠かせないスキル…
```

退出码：找到返回 `0`，没找到返回 `1`，参数 / 文件错误返回 `2`，方便脚本判断。

## Python 版

```bash
pip install pypdf
python3 pdfseek.py "に欠かせない" .
```

参数和 Swift 版完全一致。Windows 下把 `python3` 换成 `python`。

## 选项

```
-C, --context N       匹配前后各显示 N 个字符（默认 60）
-l, --files-only      只列出命中的文件和命中次数
-p, --pages-only      只列出命中的页码
-m, --max-per-page N  每页最多显示 N 条（默认 5，0 = 全部）
-i, --ignore-case     不区分拉丁字母大小写
-W, --whole           精确匹配，不忽略短语内部的空白/换行
-h, --help            显示帮助
-v, --version         显示版本
```

## 注意

- 只对**有文字层**的 PDF 有效。扫描件请先用 OCR 处理（macOS 预览的“实时文本”、
  Adobe Acrobat、ABBYY FineReader 等）。
- 默认的跨行匹配（字符之间允许 `\s*`）是刻意设计的，用来对付 PDF 排版把短语拆行
  的情况；如果只想精确匹配连续文本，加 `-W`。
