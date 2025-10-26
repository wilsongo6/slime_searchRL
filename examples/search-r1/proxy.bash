#!/bin/bash
# Clash 代理启动脚本（用于服务器）

CLASH_DIR="/lc/data/script/clash"
PID_FILE="${CLASH_DIR}/clash.pid"
LOG_FILE="${CLASH_DIR}/clash.log"
PROXY_PORT=7890

echo "=========================================="
echo "启动 Clash 代理服务"
echo "=========================================="

# 检查目录是否存在
if [ ! -d "${CLASH_DIR}" ]; then
    echo "❌ 错误: Clash 目录不存在: ${CLASH_DIR}"
    exit 1
fi

cd "${CLASH_DIR}" || {
    echo "❌ 错误: 无法进入目录: ${CLASH_DIR}"
    exit 1
}

# 检查 clash 可执行文件
if [ ! -f "./clash" ]; then
    echo "❌ 错误: clash 可执行文件不存在"
    exit 1
fi

if [ ! -x "./clash" ]; then
    echo "⚠️  添加执行权限..."
    chmod +x ./clash
fi

# 检查是否已经在运行
if [ -f "${PID_FILE}" ]; then
    OLD_PID=$(cat "${PID_FILE}")
    if ps -p "${OLD_PID}" > /dev/null 2>&1; then
        echo "⚠️  Clash 已在运行 (PID: ${OLD_PID})"
        echo "   如需重启，请先执行: kill ${OLD_PID}"
        exit 0
    else
        echo "⚠️  清理旧的 PID 文件"
        rm -f "${PID_FILE}"
    fi
fi

# 启动 clash
echo "🚀 启动 Clash..."
nohup ./clash -d . > "${LOG_FILE}" 2>&1 &
CLASH_PID=$!

# 保存 PID
echo "${CLASH_PID}" > "${PID_FILE}"
echo "   进程 PID: ${CLASH_PID}"

# 等待启动
echo "⏳ 等待服务启动..."
sleep 5

# 验证进程是否还在运行
if ! ps -p "${CLASH_PID}" > /dev/null 2>&1; then
    echo "❌ 启动失败！进程已退出"
    echo "   查看日志: tail ${LOG_FILE}"
    rm -f "${PID_FILE}"
    exit 1
fi

# 验证端口是否监听
if command -v netstat > /dev/null 2>&1; then
    if netstat -tln | grep -q ":${PROXY_PORT} "; then
        echo "✅ 代理端口 ${PROXY_PORT} 已监听"
    else
        echo "⚠️  警告: 端口 ${PROXY_PORT} 未监听，请检查配置"
        echo "   查看日志: tail ${LOG_FILE}"
    fi
elif command -v ss > /dev/null 2>&1; then
    if ss -tln | grep -q ":${PROXY_PORT} "; then
        echo "✅ 代理端口 ${PROXY_PORT} 已监听"
    else
        echo "⚠️  警告: 端口 ${PROXY_PORT} 未监听，请检查配置"
        echo "   查看日志: tail ${LOG_FILE}"
    fi
else
    echo "⚠️  无法检查端口状态（需要 netstat 或 ss 命令）"
fi

echo ""
echo "=========================================="
echo "✅ Clash 代理启动完成"
echo "=========================================="
echo "PID: ${CLASH_PID}"
echo "代理地址: http://127.0.0.1:${PROXY_PORT}"
echo "日志文件: ${LOG_FILE}"
echo ""
echo "管理命令:"
echo "  查看日志: tail -f ${LOG_FILE}"
echo "  查看状态: ps -p ${CLASH_PID}"
echo "  停止服务: kill ${CLASH_PID}"
echo "=========================================="
