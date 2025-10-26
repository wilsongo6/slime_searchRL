#!/bin/bash
# 检查完整的网页抓取服务栈状态

# ========== 配置 ==========
CLASH_DIR="/lc/data/script/clash"
CLASH_PID_FILE="${CLASH_DIR}/clash.pid"
CLASH_LOG_FILE="${CLASH_DIR}/clash.log"
PROXY_PORT=7890

FETCH_SERVICE_DIR="/lc/data/deep_report-0811"
FETCH_SERVICE_PID_FILE="${FETCH_SERVICE_DIR}/fetch_service.pid"
FETCH_SERVICE_LOG_FILE="${FETCH_SERVICE_DIR}/tool_fast_api.log"
FETCH_SERVICE_PORT=9999

echo "=========================================="
echo "网页抓取服务栈状态"
echo "=========================================="
echo ""

# ========== Clash 状态 ==========
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "【Clash 代理服务】"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -f "${CLASH_PID_FILE}" ]; then
    CLASH_PID=$(cat "${CLASH_PID_FILE}")
    echo "PID 文件: 存在 (PID: ${CLASH_PID})"

    if ps -p "${CLASH_PID}" > /dev/null 2>&1; then
        echo "进程状态: ✅ 运行中"
        echo ""
        echo "进程详情:"
        ps -p "${CLASH_PID}" -o pid,user,%cpu,%mem,vsz,rss,etime,command 2>/dev/null | tail -n +2
    else
        echo "进程状态: ❌ 已停止（PID 文件存在但进程不存在）"
    fi
else
    echo "PID 文件: 不存在"

    CLASH_PIDS=$(ps aux | grep '[c]lash -d' | awk '{print $2}')
    if [ -n "${CLASH_PIDS}" ]; then
        echo "进程状态: ⚠️  有未记录的 clash 进程"
        echo "  PIDs: ${CLASH_PIDS}"
    else
        echo "进程状态: ❌ 未运行"
    fi
fi

echo ""
echo "端口监听:"
if netstat -tln 2>/dev/null | grep -q ":${PROXY_PORT} " || ss -tln 2>/dev/null | grep -q ":${PROXY_PORT} "; then
    echo "  ✅ 端口 ${PROXY_PORT} 已监听"
else
    echo "  ❌ 端口 ${PROXY_PORT} 未监听"
fi

echo ""
echo "日志文件:"
if [ -f "${CLASH_LOG_FILE}" ]; then
    LOG_SIZE=$(du -h "${CLASH_LOG_FILE}" 2>/dev/null | awk '{print $1}')
    LOG_LINES=$(wc -l < "${CLASH_LOG_FILE}" 2>/dev/null)
    echo "  路径: ${CLASH_LOG_FILE}"
    echo "  大小: ${LOG_SIZE}"
    echo "  行数: ${LOG_LINES}"
    echo ""
    echo "  最后 3 行:"
    tail -3 "${CLASH_LOG_FILE}" 2>/dev/null | sed 's/^/    /'
else
    echo "  ⚠️  日志文件不存在"
fi

echo ""
echo ""

# ========== 抓取服务状态 ==========
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "【Playwright 抓取服务】"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -f "${FETCH_SERVICE_PID_FILE}" ]; then
    FETCH_PID=$(cat "${FETCH_SERVICE_PID_FILE}")
    echo "PID 文件: 存在 (PID: ${FETCH_PID})"

    if ps -p "${FETCH_PID}" > /dev/null 2>&1; then
        echo "进程状态: ✅ 运行中"
        echo ""
        echo "进程详情:"
        ps -p "${FETCH_PID}" -o pid,user,%cpu,%mem,vsz,rss,etime,command 2>/dev/null | tail -n +2
    else
        echo "进程状态: ❌ 已停止（PID 文件存在但进程不存在）"
    fi
else
    echo "PID 文件: 不存在"

    FETCH_PIDS=$(ps aux | grep '[t]ool_fast_api.py' | awk '{print $2}')
    if [ -n "${FETCH_PIDS}" ]; then
        echo "进程状态: ⚠️  有未记录的抓取服务进程"
        echo "  PIDs: ${FETCH_PIDS}"
    else
        echo "进程状态: ❌ 未运行"
    fi
fi

echo ""
echo "端口监听:"
if netstat -tln 2>/dev/null | grep -q ":${FETCH_SERVICE_PORT} " || ss -tln 2>/dev/null | grep -q ":${FETCH_SERVICE_PORT} "; then
    echo "  ✅ 端口 ${FETCH_SERVICE_PORT} 已监听"
else
    echo "  ❌ 端口 ${FETCH_SERVICE_PORT} 未监听"
fi

echo ""
echo "服务测试:"
if command -v curl > /dev/null 2>&1; then
    TEST_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -m 5 \
        -X POST http://127.0.0.1:${FETCH_SERVICE_PORT}/fetch \
        -H "Content-Type: application/json" \
        -d '{"task_id":"health_check","url":"https://www.example.com","use_proxy":false}' 2>/dev/null)

    if [ "${TEST_RESPONSE}" = "200" ] || [ "${TEST_RESPONSE}" = "500" ]; then
        echo "  ✅ /fetch 接口响应正常 (HTTP ${TEST_RESPONSE})"
    else
        echo "  ❌ /fetch 接口响应异常 (HTTP ${TEST_RESPONSE:-无响应})"
    fi
else
    echo "  ⚠️  无法测试（需要 curl）"
fi

echo ""
echo "日志文件:"
if [ -f "${FETCH_SERVICE_LOG_FILE}" ]; then
    LOG_SIZE=$(du -h "${FETCH_SERVICE_LOG_FILE}" 2>/dev/null | awk '{print $1}')
    LOG_LINES=$(wc -l < "${FETCH_SERVICE_LOG_FILE}" 2>/dev/null)
    echo "  路径: ${FETCH_SERVICE_LOG_FILE}"
    echo "  大小: ${LOG_SIZE}"
    echo "  行数: ${LOG_LINES}"
    echo ""
    echo "  最后 3 行:"
    tail -3 "${FETCH_SERVICE_LOG_FILE}" 2>/dev/null | sed 's/^/    /'
else
    echo "  ⚠️  日志文件不存在"
fi

echo ""
echo ""

# ========== 总结 ==========
echo "=========================================="
echo "管理命令"
echo "=========================================="
echo "启动服务: bash proxy.bash"
echo "停止服务: bash stop_proxy.bash"
echo ""
echo "查看 Clash 日志: tail -f ${CLASH_LOG_FILE}"
echo "查看服务日志: tail -f ${FETCH_SERVICE_LOG_FILE}"
echo "=========================================="
