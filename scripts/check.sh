#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════
# 简瘦 FitTrack — 提交门禁
# 用法（Git Bash）: bash scripts/check.sh
# 规矩：本脚本不绿，不许提交。
# ═══════════════════════════════════════════════════════════
set -uo pipefail

FLUTTER="${FLUTTER_BIN:-/d/dev/flutter/bin/flutter.bat}"

# 本机 Clash 系统代理（127.0.0.1:51650）会拦截 flutter_tester 的本地
# WebSocket 连接，导致测试报 "Invalid WebSocket upgrade request"。
# 分析和测试都是本地运行，无需网络，直接绕过代理。
export NO_PROXY="127.0.0.1,localhost"
export HTTP_PROXY= HTTPS_PROXY= http_proxy= https_proxy=

echo "==> [0/3] 生成物守卫（.g.dart 不入库，缺了或比源码旧就重新生成）"
GEN_TARGETS=("lib/core/database/database.dart")
NEED_BUILD=0
for src in "${GEN_TARGETS[@]}"; do
  gen="${src%.dart}.g.dart"
  if [ ! -f "$gen" ]; then
    echo "    缺失: $gen —— 需要生成"
    NEED_BUILD=1
  elif [ "$src" -nt "$gen" ]; then
    echo "    过期: $gen 比 $src 旧 —— 需要重新生成"
    NEED_BUILD=1
  fi
done

if [ "$NEED_BUILD" -eq 1 ]; then
  echo "    运行 build_runner ..."
  if ! "$FLUTTER" pub run build_runner build; then
    echo ""
    echo "❌ 代码生成失败 —— 先修好 build_runner 报错（常见原因：表定义写错）"
    exit 1
  fi
else
  echo "    生成物是最新的"
fi

echo ""
echo "==> [1/3] 静态分析（要求 0 issue）"
if ! "$FLUTTER" analyze; then
  echo ""
  echo "❌ 静态分析未通过 —— 先修掉上面列出的问题，再提交"
  exit 1
fi

echo ""
echo "==> [2/3] 单元测试"
if ! "$FLUTTER" test; then
  echo ""
  echo "❌ 测试未通过 —— 修复后再提交"
  exit 1
fi

echo ""
echo "OK — 全部通过，可以提交"
