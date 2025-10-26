#!/bin/bash
# 停止完整的网页抓取服务栈

# ========== 配置 ==========
CLASH_DIR="/lc/data/script/clash"
CLASH_PID_FILE="${CLASH_DIR}/clash.pid"

FETCH_SERVICE_DIR="/lc/data/deep_report-0811"
FETCH_SERVICE_PID_FILE="${FETCH_SERVICE_DIR}/fetch_service.pid"

echo "=========================================="
echo "停止网页抓取服务栈"
echo "=========================================="
echo ""

# ========== 停止抓取服务 ==========
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "停止 Playwright 抓取服务"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -f "${FETCH_SERVICE_PID_FILE}" ]; then
    FETCH_PID=$(cat "${FETCH_SERVICE_PID_FILE}")
    echo "PID: ${FETCH_PID}"

    if ps -p "${FETCH_PID}" > /dev/null 2>&1; then
        echo "🛑 停止进程..."
        kill "${FETCH_PID}"
        sleep 2

        # 验证是否已停止
        if ps -p "${FETCH_PID}" > /dev/null 2>&1; then
            echo "⚠️  进程未响应，强制停止..."
            kill -9 "${FETCH_PID}"
            sleep 1
        fi

        if ps -p "${FETCH_PID}" > /dev/null 2>&1; then
            echo "❌ 无法停止进程"
        else
            echo "✅ 服务已停止"
            rm -f "${FETCH_SERVICE_PID_FILE}"
        fi
    else
        echo "⚠️  进程不存在"
        rm -f "${FETCH_SERVICE_PID_FILE}"
    fi
else
    echo "⚠️  PID 文件不存在"

    # 尝试查找进程
    FETCH_PIDS=$(ps aux | grep '[t]ool_fast_api.py' | awk '{print $2}')
    if [ -n "${FETCH_PIDS}" ]; then
        echo "   找到进程: ${FETCH_PIDS}"
        echo "   手动停止: kill ${FETCH_PIDS}"
    else
        echo "✅ 服务未运行"
    fi
fi

echo ""

# ========== 停止 Clash ==========
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "停止 Clash 代理服务"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -f "${CLASH_PID_FILE}" ]; then
    CLASH_PID=$(cat "${CLASH_PID_FILE}")
    echo "PID: ${CLASH_PID}"

    if ps -p "${CLASH_PID}" > /dev/null 2>&1; then
        echo "🛑 停止进程..."
        kill "${CLASH_PID}"
        sleep 2

        # 验证是否已停止
        if ps -p "${CLASH_PID}" > /dev/null 2>&1; then
            echo "⚠️  进程未响应，强制停止..."
            kill -9 "${CLASH_PID}"
            sleep 1
        fi

        if ps -p "${CLASH_PID}" > /dev/null 2>&1; then
            echo "❌ 无法停止进程"
        else
            echo "✅ Clash 已停止"
            rm -f "${CLASH_PID_FILE}"
        fi
    else
        echo "⚠️  进程不存在"
        rm -f "${CLASH_PID_FILE}"
    fi
else
    echo "⚠️  PID 文件不存在"

    # 尝试查找进程
    CLASH_PIDS=$(ps aux | grep '[c]lash -d' | awk '{print $2}')
    if [ -n "${CLASH_PIDS}" ]; then
        echo "   找到进程: ${CLASH_PIDS}"
        echo "   手动停止: kill ${CLASH_PIDS}"
    else
        echo "✅ Clash 未运行"
    fi
fi

echo ""
echo "=========================================="
echo "✅ 服务栈已停止"
echo "=========================================="
