#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v swiftc >/dev/null 2>&1; then
    echo "error: 找不到 swiftc，请先安装 Xcode Command Line Tools：" >&2
    echo "       xcode-select --install" >&2
    exit 1
fi

echo "Compiling pdfseek..."
swiftc -O pdfseek.swift -o pdfseek
echo "Done: $(pwd)/pdfseek"
