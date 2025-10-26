#!/bin/bash
# 启动完整的网页抓取服务栈（Clash + Playwright）

# ========== 配置 ==========
CLASH_DIR="/lc/data/script/clash"
CLASH_PID_FILE="${CLASH_DIR}/clash.pid"
CLASH_LOG_FILE="${CLASH_DIR}/clash.log"
PROXY_PORT=7890

FETCH_SERVICE_DIR="/lc/data/deep_report-0811"
FETCH_SERVICE_SCRIPT="${FETCH_SERVICE_DIR}/tool_fast_api.py"
FETCH_SERVICE_PID_FILE="${FETCH_SERVICE_DIR}/fetch_service.pid"
FETCH_SERVICE_LOG_FILE="${FETCH_SERVICE_DIR}/tool_fast_api.log"
FETCH_SERVICE_PORT=9999

CONDA_ENV="dra"
CONDA_PATH="/lc/data/env/anaconda3"

echo "=========================================="
echo "启动网页抓取服务栈"
echo "=========================================="
echo ""

# ========== 第1步: 启动 Clash 代理 ==========
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "第1步: 启动 Clash 代理服务"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 检查 Clash 目录
if [ ! -d "${CLASH_DIR}" ]; then
    echo "❌ 错误: Clash 目录不存在: ${CLASH_DIR}"
    exit 1
fi

cd "${CLASH_DIR}" || {
    echo "❌ 错误: 无法进入目录: ${CLASH_DIR}"
    exit 1
}

# 检查可执行文件
if [ ! -f "./clash" ]; then
    echo "❌ 错误: clash 可执行文件不存在"
    exit 1
fi

if [ ! -x "./clash" ]; then
    echo "⚠️  添加执行权限..."
    chmod +x ./clash
fi

# 检查是否已运行
if [ -f "${CLASH_PID_FILE}" ]; then
    OLD_PID=$(cat "${CLASH_PID_FILE}")
    if ps -p "${OLD_PID}" > /dev/null 2>&1; then
        echo "✅ Clash 已在运行 (PID: ${OLD_PID})"
        CLASH_PID=${OLD_PID}
        CLASH_RUNNING=true
    else
        echo "⚠️  清理旧的 PID 文件"
        rm -f "${CLASH_PID_FILE}"
        CLASH_RUNNING=false
    fi
else
    CLASH_RUNNING=false
fi

# 启动 Clash（如果未运行）
if [ "${CLASH_RUNNING}" = false ]; then
    echo "🚀 启动 Clash..."
    nohup ./clash -d . > "${CLASH_LOG_FILE}" 2>&1 &
    CLASH_PID=$!
    echo "${CLASH_PID}" > "${CLASH_PID_FILE}"
    echo "   进程 PID: ${CLASH_PID}"

    echo "⏳ 等待 Clash 启动..."
    sleep 5

    # 验证进程
    if ! ps -p "${CLASH_PID}" > /dev/null 2>&1; then
        echo "❌ Clash 启动失败！进程已退出"
        echo "   查看日志: tail ${CLASH_LOG_FILE}"
        rm -f "${CLASH_PID_FILE}"
        exit 1
    fi

    # 验证端口
    for i in {1..5}; do
        if netstat -tln 2>/dev/null | grep -q ":${PROXY_PORT} " || ss -tln 2>/dev/null | grep -q ":${PROXY_PORT} "; then
            echo "✅ Clash 代理端口 ${PROXY_PORT} 已监听"
            break
        fi
        if [ $i -eq 5 ]; then
            echo "⚠️  警告: 端口 ${PROXY_PORT} 未监听"
        fi
        sleep 1
    done
fi

echo ""

# ========== 第2步: 配置 Conda 环境 ==========
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "第2步: 配置 Conda 环境"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 设置 PATH
export PATH="${CONDA_PATH}/bin:$PATH"

# 初始化 conda（如果需要）
if ! command -v conda > /dev/null 2>&1; then
    echo "⚠️  初始化 Conda..."
    source "${CONDA_PATH}/etc/profile.d/conda.sh"
fi

# 激活环境
echo "🔄 激活 Conda 环境: ${CONDA_ENV}"
source deactivate 2>/dev/null || true
eval "$(conda shell.bash hook)"
conda activate "${CONDA_ENV}"

if [ $? -ne 0 ]; then
    echo "❌ 无法激活 Conda 环境: ${CONDA_ENV}"
    exit 1
fi

echo "✅ Conda 环境已激活: $(conda info --envs | grep '*' | awk '{print $1}')"
echo ""

# ========== 第3步: 安装 Playwright（可选） ==========
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "第3步: 检查 Playwright"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 检查是否需要安装
if python -c "import playwright" 2>/dev/null; then
    echo "✅ Playwright 已安装"
else
    echo "⚠️  Playwright 未安装，跳过安装"
    echo "   如需安装，请手动执行:"
    echo "   playwright install chromium --with-deps --no-shell"
fi

echo ""

# ========== 第4步: 启动抓取服务 ==========
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "第4步: 启动 Playwright 抓取服务"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 检查脚本是否存在
if [ ! -f "${FETCH_SERVICE_SCRIPT}" ]; then
    echo "❌ 错误: 抓取服务脚本不存在: ${FETCH_SERVICE_SCRIPT}"
    exit 1
fi

# 检查端口是否被占用
if netstat -tln 2>/dev/null | grep -q ":${FETCH_SERVICE_PORT} " || ss -tln 2>/dev/null | grep -q ":${FETCH_SERVICE_PORT} "; then
    echo "⚠️  端口 ${FETCH_SERVICE_PORT} 已被占用"

    if [ -f "${FETCH_SERVICE_PID_FILE}" ]; then
        OLD_PID=$(cat "${FETCH_SERVICE_PID_FILE}")
        if ps -p "${OLD_PID}" > /dev/null 2>&1; then
            echo "✅ 抓取服务已在运行 (PID: ${OLD_PID})"
            FETCH_SERVICE_RUNNING=true
        else
            echo "⚠️  端口被其他进程占用，请手动检查"
            FETCH_SERVICE_RUNNING=false
        fi
    else
        echo "⚠️  端口被未知进程占用"
        FETCH_SERVICE_RUNNING=false
    fi
else
    FETCH_SERVICE_RUNNING=false
fi

# 启动服务（如果未运行）
if [ "${FETCH_SERVICE_RUNNING}" = false ]; then
    echo "🚀 启动抓取服务..."
    cd "${FETCH_SERVICE_DIR}" || exit 1

    nohup python "${FETCH_SERVICE_SCRIPT}" > "${FETCH_SERVICE_LOG_FILE}" 2>&1 &
    FETCH_SERVICE_PID=$!
    echo "${FETCH_SERVICE_PID}" > "${FETCH_SERVICE_PID_FILE}"
    echo "   进程 PID: ${FETCH_SERVICE_PID}"

    echo "⏳ 等待服务启动（预计30秒）..."
    sleep 10

    # 验证进程
    if ! ps -p "${FETCH_SERVICE_PID}" > /dev/null 2>&1; then
        echo "❌ 服务启动失败！进程已退出"
        echo "   查看日志: tail ${FETCH_SERVICE_LOG_FILE}"
        rm -f "${FETCH_SERVICE_PID_FILE}"
        exit 1
    fi

    # 等待端口监听
    for i in {1..20}; do
        if netstat -tln 2>/dev/null | grep -q ":${FETCH_SERVICE_PORT} " || ss -tln 2>/dev/null | grep -q ":${FETCH_SERVICE_PORT} "; then
            echo "✅ 服务端口 ${FETCH_SERVICE_PORT} 已监听"
            break
        fi
        if [ $i -eq 20 ]; then
            echo "⚠️  警告: 端口 ${FETCH_SERVICE_PORT} 未监听（可能仍在启动）"
        fi
        sleep 1
    done
fi

echo ""

# ========== 第5步: 健康检查 ==========
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "第5步: 服务健康检查"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 测试 /fetch 接口（可选）
if command -v curl > /dev/null 2>&1; then
    echo "🧪 测试 /fetch 接口..."
    TEST_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -m 5 \
        -X POST http://127.0.0.1:${FETCH_SERVICE_PORT}/fetch \
        -H "Content-Type: application/json" \
        -d '{"task_id":"test","url":"https://www.example.com","use_proxy":false}' 2>/dev/null)

    if [ "${TEST_RESPONSE}" = "200" ] || [ "${TEST_RESPONSE}" = "500" ]; then
        echo "✅ 服务响应正常 (HTTP ${TEST_RESPONSE})"
    else
        echo "⚠️  服务响应异常 (HTTP ${TEST_RESPONSE:-无响应})"
    fi
else
    echo "⚠️  跳过接口测试（需要 curl 命令）"
fi

echo ""

# ========== 总结 ==========
echo "=========================================="
echo "✅ 服务栈启动完成"
echo "=========================================="
echo ""
echo "【Clash 代理】"
echo "  PID: $(cat ${CLASH_PID_FILE} 2>/dev/null || echo '未知')"
echo "  端口: ${PROXY_PORT}"
echo "  日志: ${CLASH_LOG_FILE}"
echo ""
echo "【Playwright 抓取服务】"
echo "  PID: $(cat ${FETCH_SERVICE_PID_FILE} 2>/dev/null || echo '未知')"
echo "  端口: ${FETCH_SERVICE_PORT}"
echo "  接口: http://127.0.0.1:${FETCH_SERVICE_PORT}/fetch"
echo "  日志: ${FETCH_SERVICE_LOG_FILE}"
echo ""
echo "【管理命令】"
echo "  查看 Clash 日志: tail -f ${CLASH_LOG_FILE}"
echo "  查看服务日志: tail -f ${FETCH_SERVICE_LOG_FILE}"
echo "  停止服务: bash stop_proxy.bash"
echo "  检查状态: bash check_proxy.bash"
echo "=========================================="
