#!/bin/bash
# Clash 代理停止脚本

CLASH_DIR="/lc/data/script/clash"
PID_FILE="${CLASH_DIR}/clash.pid"

echo "=========================================="
echo "停止 Clash 代理服务"
echo "=========================================="

# 检查 PID 文件是否存在
if [ ! -f "${PID_FILE}" ]; then
    echo "⚠️  PID 文件不存在"
    echo "   尝试查找 clash 进程..."

    CLASH_PID=$(ps aux | grep '[c]lash -d' | awk '{print $2}')

    if [ -z "${CLASH_PID}" ]; then
        echo "✅ Clash 未在运行"
        exit 0
    else
        echo "   找到进程: ${CLASH_PID}"
    fi
else
    CLASH_PID=$(cat "${PID_FILE}")
    echo "PID 文件: ${PID_FILE}"
    echo "进程 PID: ${CLASH_PID}"
fi

# 检查进程是否存在
if ! ps -p "${CLASH_PID}" > /dev/null 2>&1; then
    echo "⚠️  进程 ${CLASH_PID} 不存在"
    rm -f "${PID_FILE}"
    echo "✅ 已清理 PID 文件"
    exit 0
fi

# 停止进程
echo "🛑 停止进程 ${CLASH_PID}..."
kill "${CLASH_PID}"

# 等待进程退出
sleep 2

# 验证是否已停止
if ps -p "${CLASH_PID}" > /dev/null 2>&1; then
    echo "⚠️  进程未响应，尝试强制停止..."
    kill -9 "${CLASH_PID}"
    sleep 1
fi

# 再次验证
if ps -p "${CLASH_PID}" > /dev/null 2>&1; then
    echo "❌ 无法停止进程 ${CLASH_PID}"
    exit 1
else
    echo "✅ 进程已停止"
    rm -f "${PID_FILE}"
    echo "✅ 已清理 PID 文件"
fi

echo "=========================================="
echo "✅ Clash 代理已停止"
echo "=========================================="
