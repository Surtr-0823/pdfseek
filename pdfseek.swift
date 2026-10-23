#!/usr/bin/env swift
//
// pdfseek — search text across PDF files (macOS, uses PDFKit)
//
// Build: ./build.sh   (or: swiftc -O pdfseek.swift -o pdfseek)
//

import Foundation
import Darwin
import PDFKit

let toolName = "pdfseek"
let toolVersion = "1.0.0"

struct Options {
    var needle = ""
    var paths: [String] = []
    var context = 60
    var filesOnly = false
    var pagesOnly = false
    var ignoreCase = false
    var exactMatch = false
    var maxPerPage = 5
}

func writeErr(_ line: String) {
    FileHandle.standardError.write((line + "\n").data(using: .utf8)!)
}

func printUsage() {
    print("""
    \(toolName) \(toolVersion) — 在 PDF 中搜索文字，输出文件名和页码

    用法:
      \(toolName) [选项] <要搜索的文字> [PDF 文件或文件夹...]

    不指定路径时搜索当前文件夹（递归所有 .pdf）。
    默认忽略短语内部的换行/空格，所以「に欠かせない」也能匹配被排版
    拆成两行的文字。

    选项:
      -C, --context N       匹配前后各显示 N 个字符（默认 60）
      -l, --files-only      只列出命中的文件和命中次数
      -p, --pages-only      只列出命中的页码（每行 file:page）
      -m, --max-per-page N  每页最多显示 N 条匹配（默认 5，0 表示全部）
      -i, --ignore-case     不区分拉丁字母大小写
      -W, --whole           精确匹配，不忽略短语内部的空白/换行
      -h, --help            显示帮助
      -v, --version         显示版本

    示例:
      \(toolName) "に欠かせない" ~/Documents/日语语法
      \(toolName) -l "に欠かせない" 1.pdf 2.pdf
      \(toolName) -p -C 20 "文法" .
    """)
}

// MARK: - 参数解析

var opts = Options()
var positional: [String] = []
let args = Array(CommandLine.arguments.dropFirst())
var optionsEnded = false
var i = 0

while i < args.count {
    let arg = args[i]
    if optionsEnded {
        positional.append(arg)
    } else {
        switch arg {
        case "-h", "--help":
            printUsage()
            exit(0)
        case "-v", "--version":
            print("\(toolName) \(toolVersion)")
            exit(0)
        case "-l", "--files-only":
            opts.filesOnly = true
        case "-p", "--pages-only":
            opts.pagesOnly = true
        case "-i", "--ignore-case":
            opts.ignoreCase = true
        case "-W", "--whole":
            opts.exactMatch = true
        case "-C", "--context":
            i += 1
            guard i < args.count, let value = Int(args[i]), value >= 0 else {
                writeErr("\(toolName): \(arg) 需要一个非负整数")
                exit(2)
            }
            opts.context = value
        case "-m", "--max-per-page":
            i += 1
            guard i < args.count, let value = Int(args[i]), value >= 0 else {
                writeErr("\(toolName): \(arg) 需要一个非负整数")
                exit(2)
            }
            opts.maxPerPage = value
        case "--":
            optionsEnded = true
        default:
            if arg.hasPrefix("-") && arg != "-" {
                writeErr("\(toolName): 未知选项 \(arg)（用 -h 查看帮助）")
                exit(2)
            }
            positional.append(arg)
        }
    }
    i += 1
}

guard let needle = positional.first, !needle.isEmpty else {
    printUsage()
    exit(2)
}
opts.needle = needle
opts.paths = positional.count > 1 ? Array(positional.dropFirst()) : ["."]

// MARK: - 文件收集

func collectPDFs(in path: String) -> [String] {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
        writeErr("\(toolName): 找不到路径: \(path)")
        return []
    }
    var results: [String] = []
    if isDir.boolValue {
        guard let enumerator = fm.enumerator(atPath: path) else { return [] }
        for case let relative as String in enumerator {
            if relative.lowercased().hasSuffix(".pdf") {
                results.append((path as NSString).appendingPathComponent(relative))
            }
        }
    } else {
        results.append(path)
    }
    return results
}

var pdfs = opts.paths.flatMap { collectPDFs(in: $0) }

// 去重（按标准化后的路径），然后按“自然顺序”排序：2.pdf 排在 10.pdf 前面
var seenPaths = Set<String>()
pdfs = pdfs.filter { seenPaths.insert(($0 as NSString).standardizingPath).inserted }
pdfs.sort { $0.localizedStandardCompare($1) == .orderedAscending }

guard !pdfs.isEmpty else {
    writeErr("\(toolName): 没有找到 PDF 文件")
    exit(2)
}

// MARK: - 搜索模式

// NFKC 归一化：有些 PDF 会把汉字提取成康熙部首等兼容字符，
// 归一化后「⽋」和「欠」才能匹配上
let normalizedNeedle = opts.needle.precomposedStringWithCompatibilityMapping

// 默认在字符之间允许任意空白（含换行），这样被 PDF 排版拆行的短语也能命中
let escapedChars = normalizedNeedle.map { NSRegularExpression.escapedPattern(for: String($0)) }
let pattern = opts.exactMatch ? escapedChars.joined() : escapedChars.joined(separator: "\\s*")

let regex: NSRegularExpression
do {
    var regexOptions: NSRegularExpression.Options = []
    if opts.ignoreCase { regexOptions.insert(.caseInsensitive) }
    regex = try NSRegularExpression(pattern: pattern, options: regexOptions)
} catch {
    writeErr("\(toolName): 无法构造搜索模式: \(error)")
    exit(2)
}

// MARK: - 输出辅助

let isTTY = isatty(STDOUT_FILENO) == 1

func paint(_ text: String, _ code: String) -> String {
    isTTY ? "\u{001B}[\(code)m\(text)\u{001B}[0m" : text
}

let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL.path

func displayPath(_ path: String) -> String {
    let abs = URL(fileURLWithPath: path).standardizedFileURL.path
    if abs == cwd { return "." }
    if abs.hasPrefix(cwd + "/") { return String(abs.dropFirst(cwd.count + 1)) }
    return path
}

func contextText(_ text: NSString, match: NSRange, context: Int) -> String {
    let lo = max(0, match.location - context)
    let hi = min(text.length, match.location + match.length + context)
    let raw = text.substring(with: NSRange(location: lo, length: hi - lo))
    let collapsed = raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - 搜索

var totalHits = 0
var filesWithHits = 0
var searchedFileCount = 0
var hadOpenError = false

for pdfPath in pdfs {
    let url = URL(fileURLWithPath: pdfPath)
    guard let doc = PDFDocument(url: url) else {
        writeErr("\(toolName): 无法打开 \(displayPath(pdfPath))（可能不是 PDF 或文件损坏）")
        hadOpenError = true
        continue
    }

    searchedFileCount += 1
    let shownPath = displayPath(pdfPath)
    var fileHits = 0
    var pagesWithHits: [Int] = []
    var textPageCount = 0

    for pageIndex in 0..<doc.pageCount {
        guard let text = doc.page(at: pageIndex)?.string else { continue }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
        textPageCount += 1

        let normalizedText = text.precomposedStringWithCompatibilityMapping
        let nsText = normalizedText as NSString
        let matches = regex.matches(in: normalizedText, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { continue }

        fileHits += matches.count
        pagesWithHits.append(pageIndex + 1)

        if opts.filesOnly || opts.pagesOnly { continue }

        var shown = 0
        for match in matches {
            if opts.maxPerPage > 0 && shown >= opts.maxPerPage { break }
            shown += 1
            let context = contextText(nsText, match: match.range, context: opts.context)
            print("\(paint(shownPath, "36")):\(paint(String(pageIndex + 1), "32")): \(context)")
        }
        if opts.maxPerPage > 0 && matches.count > opts.maxPerPage {
            let rest = matches.count - opts.maxPerPage
            print("\(paint(shownPath, "36")):\(paint(String(pageIndex + 1), "32")): …（本页另有 \(rest) 处匹配）")
        }
    }

    if fileHits > 0 {
        filesWithHits += 1
        totalHits += fileHits
        if opts.filesOnly {
            let pageList = pagesWithHits.map(String.init).joined(separator: ", ")
            print("\(paint(shownPath, "36")): \(fileHits) 处（第 \(pageList) 页）")
        } else if opts.pagesOnly {
            for page in pagesWithHits {
                print("\(paint(shownPath, "36")):\(paint(String(page), "32"))")
            }
        }
    } else if textPageCount == 0 {
        writeErr("\(toolName): 提示: \(shownPath) 没有可提取的文字（可能是扫描版 PDF，需要先 OCR）")
    }
}

if totalHits == 0 {
    writeErr("未找到「\(opts.needle)」（已搜索 \(searchedFileCount) 个 PDF）")
    exit(hadOpenError ? 2 : 1)
}

if isTTY && !opts.filesOnly && !opts.pagesOnly {
    writeErr("共 \(totalHits) 处匹配，位于 \(filesWithHits) 个文件")
}
