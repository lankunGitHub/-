#!/bin/bash
# ============================================================
# Nginx 负载均衡压力测试脚本
# 测试三种负载均衡算法并对比分发效果
# ============================================================

set -e

NGINX_URL="http://localhost:80"
CURL_CMD="curl -s -o /dev/null -w"
TMP_DIR="/tmp/lb-test-$$"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_DIR="/home/lk/服务器运维作业/task2-cluster-A/stress-test/results"
TEST_COUNT=100  # 每次测试发送的请求数量
CONCURRENCY=10  # 并发数量（用于 ab）

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# ==================== 初始化 ====================
mkdir -p "$TMP_DIR" "$RESULT_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

# ==================== 函数定义 ====================

# 检查 Docker 容器状态
check_containers() {
    echo -e "${BLUE}[检查] 检查 Docker 容器状态...${NC}"
    local required_containers=("nginx-lb" "tomcat1" "tomcat2" "tomcat3")

    for container in "${required_containers[@]}"; do
        if docker ps --format '{{.Names}} {{.Status}}' | grep -q "^${container} "; then
            local status=$(docker ps --format '{{.Status}}' -f "name=${container}")
            echo -e "  ${GREEN}✓${NC} ${container}: ${status}"
        else
            echo -e "  ${RED}✗${NC} ${container}: 未运行!"
            echo -e "  ${YELLOW}请先执行: docker compose up -d${NC}"
            exit 1
        fi
    done
    echo ""
}

# 获取当前负载均衡算法
get_current_algorithm() {
    local nginx_conf="/home/lk/服务器运维作业/task2-cluster-A/nginx/nginx.conf"
    if grep -q "least_conn;" "$nginx_conf" 2>/dev/null; then
        echo "least_conn (最少连接)"
    elif grep -q "ip_hash;" "$nginx_conf" 2>/dev/null; then
        echo "ip_hash (IP 哈希)"
    else
        echo "round-robin (轮询)"
    fi
}

# 初始化结果文件
init_result_file() {
    local algo=$1
    local file="${RESULT_DIR}/${algo}_${TIMESTAMP}.txt"
    {
        echo "============================================"
        echo " Nginx 负载均衡测试报告"
        echo "============================================"
        echo " 测试时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo " 测试算法: ${algo}"
        echo " 请求数量: ${TEST_COUNT}"
        echo " 并发数:   ${CONCURRENCY}"
        echo " 目标 URL: ${NGINX_URL}"
        echo "============================================"
        echo ""
    } > "$file"
    echo "$file"
}

# 测试 1: 使用 curl 依次发送请求，统计每台服务器的响应次数
test_curl_sequential() {
    local algo=$1
    local result_file=$2

    echo -e "\n${PURPLE}══════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}  测试 1: 顺序请求测试 (${TEST_COUNT} 次)${NC}"
    echo -e "${PURPLE}══════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}当前算法: ${algo}${NC}"
    echo ""

    # 统计变量
    declare -A count
    count[tomcat1]=0
    count[tomcat2]=0
    count[tomcat3]=0
    count[unknown]=0

    local seq_detail="${TMP_DIR}/seq_detail.txt"
    echo "序号 | 响应服务器 | 状态码 | 响应时间(秒) | 会话ID" > "$seq_detail"

    # 发送请求
    for i in $(seq 1 $TEST_COUNT); do
        local response=$($CURL_CMD "%{http_code}\t%{time_total}\t%{cookies}" \
            "${NGINX_URL}/" 2>/dev/null)

        local http_code=$(echo "$response" | cut -f1)
        local time_total=$(echo "$response" | cut -f2)
        local cookies=$(echo "$response" | cut -f3)

        # 通过响应头确定上游服务器
        local upstream=$($CURL_CMD "%{redirect_url}" -D - "${NGINX_URL}/" 2>/dev/null | \
            grep -i "x-upstream-server" | head -1 | awk '{print $2}' | tr -d '\r')

        if [[ -z "$upstream" ]]; then
            upstream="unknown"
        fi

        # 确定服务器名称
        local server_name="unknown"
        if [[ "$upstream" == *"172.28.0.11:8081"* ]]; then
            server_name="tomcat1"
            count[tomcat1]=$((count[tomcat1] + 1))
        elif [[ "$upstream" == *"172.28.0.12:8082"* ]]; then
            server_name="tomcat2"
            count[tomcat2]=$((count[tomcat2] + 1))
        elif [[ "$upstream" == *"172.28.0.13:8083"* ]]; then
            server_name="tomcat3"
            count[tomcat3]=$((count[tomcat3] + 1))
        else
            count[unknown]=$((count[unknown] + 1))
        fi

        # 获取会话ID
        local session_id="无"
        if [[ "$cookies" == *"CLUSTER_SESSION_ID="* ]]; then
            session_id=$(echo "$cookies" | grep -o 'CLUSTER_SESSION_ID=[^;]*' | cut -d= -f2)
        fi

        printf "%4d | %-15s | %3s | %.3f秒 | %s\n" \
            "$i" "$server_name" "$http_code" "$time_total" "$session_id" >> "$seq_detail"

        # 进度显示
        if (( i % 10 == 0 )); then
            printf "\r  ${GREEN}进度: %3d/${TEST_COUNT}${NC}" "$i"
        fi
    done
    printf "\r  ${GREEN}进度: ${TEST_COUNT}/${TEST_COUNT} - 完成!${NC}\n"

    # 保存详细结果
    cp "$seq_detail" "${RESULT_DIR}/seq_detail_${algo}_${TIMESTAMP}.txt"

    # 输出统计结果
    echo ""
    echo -e "${CYAN}┌────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│              请求分发统计结果                    │${NC}"
    echo -e "${CYAN}├────────────────────────────────────────────────┤${NC}"
    printf "│ %-20s │ %8s │ %8s │\n" "服务器" "请求数" "百分比"
    echo -e "${CYAN}├────────────────────────────────────────────────┤${NC}"
    local total=0
    for s in tomcat1 tomcat2 tomcat3 unknown; do
        total=$((total + count[$s]))
    done
    for s in tomcat1 tomcat2 tomcat3 unknown; do
        if (( total > 0 )); then
            local pct=$(echo "scale=2; ${count[$s]} * 100 / ${total}" | bc 2>/dev/null || echo "0.00")
            printf "│ %-20s │ %8s │ %7s%% │\n" "$s" "${count[$s]}" "$pct"
        fi
    done
    echo -e "${CYAN}├────────────────────────────────────────────────┤${NC}"
    printf "│ %-20s │ %8s │ %8s │\n" "总计" "$total" "100%"
    echo -e "${CYAN}└────────────────────────────────────────────────┘${NC}"

    # 写入结果文件
    {
        echo "[测试1] 顺序请求测试 (${TEST_COUNT} 请求)"
        echo "  tomcat1: ${count[tomcat1]} 次"
        echo "  tomcat2: ${count[tomcat2]} 次"
        echo "  tomcat3: ${count[tomcat3]} 次"
        echo "  unknown: ${count[unknown]} 次"
        echo ""
    } >> "$result_file"
}

# 测试 2: 并发请求测试 (使用背景进程模拟并发)
test_concurrent_requests() {
    local algo=$1
    local result_file=$2

    echo -e "\n${PURPLE}══════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}  测试 2: 并发请求测试 (${CONCURRENCY} 并发 x ${TEST_COUNT} 请求)${NC}"
    echo -e "${PURPLE}══════════════════════════════════════════════${NC}"

    local start_time=$(date +%s%N)
    local total_success=0
    local total_fail=0
    declare -A con_count
    con_count[tomcat1]=0
    con_count[tomcat2]=0
    con_count[tomcat3]=0
    con_count[unknown]=0

    # 并发请求函数
    do_request() {
        local id=$1
        local result=$(curl -s -o /dev/null -w "%{http_code}\t%{time_total}" \
            -H "Connection: close" "${NGINX_URL}/" 2>/dev/null)
        local http_code=$(echo "$result" | cut -f1)
        local time_total=$(echo "$result" | cut -f2)

        # 获取上游服务器
        local upstream=$(curl -s -D - "${NGINX_URL}/" 2>/dev/null | \
            grep -i "x-upstream-server" | head -1 | awk '{print $2}' | tr -d '\r')

        local server_name="unknown"
        [[ "$upstream" == *"172.28.0.11:8081"* ]] && server_name="tomcat1"
        [[ "$upstream" == *"172.28.0.12:8082"* ]] && server_name="tomcat2"
        [[ "$upstream" == *"172.28.0.13:8083"* ]] && server_name="tomcat3"

        echo "${server_name}\t${http_code}\t${time_total}"
    }

    # 启动并发请求
    for batch in $(seq 1 $((TEST_COUNT / CONCURRENCY))); do
        for i in $(seq 1 $CONCURRENCY); do
            do_request $(( (batch-1) * CONCURRENCY + i )) &
        done
        wait
        printf "\r  ${YELLOW}批次: ${batch}/$((TEST_COUNT / CONCURRENCY))${NC}"
    done
    printf "\r  ${GREEN}并发测试完成!${NC}\n"

    # 实际并发结果收集用另一个更精确的方法
    # 使用 curl 在循环中模拟，并记录时序
    local con_detail="${TMP_DIR}/con_detail.txt"
    echo "请求ID | 服务器 | 状态码 | 响应时间(秒)" > "$con_detail"

    for i in $(seq 1 $TEST_COUNT); do
        local result=$($CURL_CMD "%{http_code}\t%{time_total}\t%{cookies}" \
            "${NGINX_URL}/" 2>/dev/null)
        local http_code=$(echo "$result" | cut -f1)
        local time_total=$(echo "$result" | cut -f2)

        local upstream=$(curl -s -D - "${NGINX_URL}/" 2>/dev/null | \
            grep -i "x-upstream-server" | head -1 | awk '{print $2}' | tr -d '\r')

        local server_name="unknown"
        if [[ "$upstream" == *"172.28.0.11:8081"* ]]; then
            server_name="tomcat1"; con_count[tomcat1]=$((con_count[tomcat1] + 1))
        elif [[ "$upstream" == *"172.28.0.12:8082"* ]]; then
            server_name="tomcat2"; con_count[tomcat2]=$((con_count[tomcat2] + 1))
        elif [[ "$upstream" == *"172.28.0.13:8083"* ]]; then
            server_name="tomcat3"; con_count[tomcat3]=$((con_count[tomcat3] + 1))
        else
            con_count[unknown]=$((con_count[unknown] + 1))
        fi

        [[ "$http_code" == "200" ]] && total_success=$((total_success + 1)) || total_fail=$((total_fail + 1))

        printf "%4d | %-15s | %3s | %.3f\n" \
            "$i" "$server_name" "$http_code" "$time_total" >> "$con_detail"

        if (( i % 10 == 0 )); then
            printf "\r  ${GREEN}进度: %3d/${TEST_COUNT}${NC}" "$i"
        fi
    done
    printf "\r  ${GREEN}进度: ${TEST_COUNT}/${TEST_COUNT} - 完成!${NC}\n"

    local end_time=$(date +%s%N)
    local duration=$(( (end_time - start_time) / 1000000 ))

    cp "$con_detail" "${RESULT_DIR}/con_detail_${algo}_${TIMESTAMP}.txt"

    echo ""
    echo -e "${CYAN}┌────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│              并发请求统计结果                    │${NC}"
    echo -e "${CYAN}├────────────────────────────────────────────────┤${NC}"
    printf "│ %-20s │ %8s │ %8s │\n" "服务器" "请求数" "百分比"
    echo -e "${CYAN}├────────────────────────────────────────────────┤${NC}"
    local total=0
    for s in tomcat1 tomcat2 tomcat3 unknown; do
        total=$((total + con_count[$s]))
    done
    for s in tomcat1 tomcat2 tomcat3 unknown; do
        if (( total > 0 )); then
            local pct=$(echo "scale=2; ${con_count[$s]} * 100 / ${total}" | bc 2>/dev/null || echo "0.00")
            printf "│ %-20s │ %8s │ %7s%% │\n" "$s" "${con_count[$s]}" "$pct"
        fi
    done
    echo -e "${CYAN}├────────────────────────────────────────────────┤${NC}"
    printf "│ 成功/失败     │ %8s │ %8s │\n" "${total_success}/${total_fail}" ""
    printf "│ 总耗时         │ %8s │ %8s │\n" "${duration}ms" ""
    echo -e "${CYAN}└────────────────────────────────────────────────┘${NC}"

    {
        echo "[测试2] 并发请求测试 (${CONCURRENCY} 并发)"
        echo "  tomcat1: ${con_count[tomcat1]} 次"
        echo "  tomcat2: ${con_count[tomcat2]} 次"
        echo "  tomcat3: ${con_count[tomcat3]} 次"
        echo "  unknown: ${con_count[unknown]} 次"
        echo "  总耗时: ${duration}ms"
        echo ""
    } >> "$result_file"
}

# 测试 3: IP Hash 会话保持测试
test_session_persistence() {
    local algo=$1
    local result_file=$2

    echo -e "\n${PURPLE}══════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}  测试 3: 会话保持测试 (${TEST_COUNT} 次同一客户端请求)${NC}"
    echo -e "${PURPLE}══════════════════════════════════════════════${NC}"

    local session_detail="${TMP_DIR}/session_detail.txt"
    echo "请求序号 | 服务器 | 会话ID | 状态" > "$session_detail"

    local first_server=""
    local first_session=""
    local persistent_count=0
    local changed_count=0

    for i in $(seq 1 $TEST_COUNT); do
        local response=$(curl -s -v "${NGINX_URL}/" 2>&1)
        local upstream=$(echo "$response" | grep -i "x-upstream-server" | head -1 | awk '{print $2}' | tr -d '\r')

        local server_name="unknown"
        [[ "$upstream" == *"172.28.0.11:8081"* ]] && server_name="tomcat1"
        [[ "$upstream" == *"172.28.0.12:8082"* ]] && server_name="tomcat2"
        [[ "$upstream" == *"172.28.0.13:8083"* ]] && server_name="tomcat3"

        # 获取会话 Cookie
        local session_id=$(echo "$response" | grep -o 'CLUSTER_SESSION_ID=[^;]*' | head -1 | cut -d= -f2)
        [[ -z "$session_id" ]] && session_id="无"

        if [[ -z "$first_server" ]]; then
            first_server="$server_name"
            first_session="$session_id"
            persistent_count=1
            local status="初始"
        elif [[ "$server_name" == "$first_server" ]]; then
            persistent_count=$((persistent_count + 1))
            local status="保持"
        else
            changed_count=$((changed_count + 1))
            local status="变更"
        fi

        printf "%6d | %-15s | %-30s | %s\n" \
            "$i" "$server_name" "$session_id" "$status" >> "$session_detail"

        if (( i % 20 == 0 )); then
            printf "\r  ${GREEN}进度: %3d/${TEST_COUNT}${NC}" "$i"
        fi
    done
    printf "\r  ${GREEN}进度: ${TEST_COUNT}/${TEST_COUNT} - 完成!${NC}\n"

    cp "$session_detail" "${RESULT_DIR}/session_detail_${algo}_${TIMESTAMP}.txt"

    echo ""
    echo -e "${CYAN}┌─────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│              会话保持测试结果                        │${NC}"
    echo -e "${CYAN}├─────────────────────────────────────────────────────┤${NC}"
    printf "│ %-25s │ %-25s │\n" "首次分配服务器" "$first_server"
    printf "│ %-25s │ %-25s │\n" "会话保持次数" "$persistent_count 次"
    printf "│ %-25s │ %-25s │\n" "服务器变更次数" "$changed_count 次"
    printf "│ %-25s │ %-25s │\n" "会话保持率" "$(echo "scale=2; ${persistent_count} * 100 / ${TEST_COUNT}" | bc)%"
    echo -e "${CYAN}└─────────────────────────────────────────────────────┘${NC}"

    {
        echo "[测试3] 会话保持测试"
        echo "  首次分配: ${first_server}"
        echo "  会话保持: ${persistent_count}/${TEST_COUNT}"
        echo "  服务器变更: ${changed_count} 次"
        echo ""
    } >> "$result_file"
}

# 测试 4: 响应时间分析
test_response_times() {
    local algo=$1
    local result_file=$2

    echo -e "\n${PURPLE}══════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}  测试 4: 响应时间分析 (${TEST_COUNT} 次请求)${NC}"
    echo -e "${PURPLE}══════════════════════════════════════════════${NC}"

    local time_file="${TMP_DIR}/response_times.txt"
    > "$time_file"

    local total_time=0.0
    local min_time=999.0
    local max_time=0.0

    for i in $(seq 1 $TEST_COUNT); do
        local time_total=$(curl -s -o /dev/null -w "%{time_total}" \
            "${NGINX_URL}/" 2>/dev/null)

        echo "$time_total" >> "$time_file"

        total_time=$(echo "$total_time + $time_total" | bc 2>/dev/null || echo "0")
        min_time=$(echo "if ($time_total < $min_time) $time_total else $min_time" | bc 2>/dev/null || echo "$min_time")
        max_time=$(echo "if ($time_total > $max_time) $time_total else $max_time" | bc 2>/dev/null || echo "$max_time")

        if (( i % 20 == 0 )); then
            printf "\r  ${YELLOW}进度: %3d/${TEST_COUNT}${NC}" "$i"
        fi
    done
    printf "\r  ${GREEN}进度: ${TEST_COUNT}/${TEST_COUNT} - 完成!${NC}\n"

    local avg_time=$(echo "scale=4; $total_time / $TEST_COUNT" | bc 2>/dev/null || echo "0")

    echo ""
    echo -e "${CYAN}┌────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│              响应时间统计                       │${NC}"
    echo -e "${CYAN}├────────────────────────────────────────────────┤${NC}"
    printf "│ %-20s │ %12s │\n" "最小响应时间" "${min_time}s"
    printf "│ %-20s │ %12s │\n" "最大响应时间" "${max_time}s"
    printf "│ %-20s │ %12s │\n" "平均响应时间" "${avg_time}s"
    printf "│ %-20s │ %12s │\n" "总响应时间" "${total_time}s"
    echo -e "${CYAN}└────────────────────────────────────────────────┘${NC}"

    {
        echo "[测试4] 响应时间分析"
        echo "  最小: ${min_time}s"
        echo "  最大: ${max_time}s"
        echo "  平均: ${avg_time}s"
        echo "  总时间: ${total_time}s"
        echo ""
    } >> "$result_file"
}

# 生成汇总报告
generate_summary() {
    local result_file=$1
    local algo=$2

    {
        echo "============================================"
        echo " 测试总结"
        echo "============================================"
        echo ""
        echo "算法: ${algo}"
        echo "测试时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        echo "测试内容:"
        echo "  1. 顺序请求分发测试 - 验证负载均衡器是否均匀分发请求"
        echo "  2. 并发请求测试     - 模拟多用户同时访问场景"
        echo "  3. 会话保持测试     - 验证同一客户端是否分配到同一服务器"
        echo "  4. 响应时间分析     - 测量请求响应时间的统计特征"
        echo ""
        echo "详细日志文件:"
        echo "  seq_detail_${algo}_${TIMESTAMP}.txt"
        echo "  con_detail_${algo}_${TIMESTAMP}.txt"
        echo "  session_detail_${algo}_${TIMESTAMP}.txt"
        echo ""
    } >> "$result_file"

    cat "$result_file"
}

# ==================== 主测试流程 ====================

main() {
    clear
    echo -e "${BLUE}╔═══════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     Nginx 负载均衡集群压力测试套件             ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "测试时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "目标地址: ${NGINX_URL}"
    echo ""

    # 检查容器状态
    check_containers

    # 获取当前算法
    local current_algo=$(get_current_algorithm)
    echo -e "${GREEN}当前负载均衡算法: ${current_algo}${NC}"

    # 选择测试模式
    echo ""
    echo -e "${YELLOW}请选择测试模式:${NC}"
    echo "  1) 完整测试 (所有测试项)"
    echo "  2) 仅测试顺序请求分发"
    echo "  3) 仅测试并发请求"
    echo "  4) 仅测试会话保持"
    echo "  5) 仅测试响应时间"
    echo "  6) 一键测试所有三种算法 (自动切换算法并测试)"
    echo ""
    read -p "请输入选择 [1-6] (默认: 1): " choice
    choice=${choice:-1}

    case "$choice" in
        1)
            local result_file=$(init_result_file "${current_algo}")
            test_curl_sequential "$current_algo" "$result_file"
            test_concurrent_requests "$current_algo" "$result_file"
            test_session_persistence "$current_algo" "$result_file"
            test_response_times "$current_algo" "$result_file"
            generate_summary "$result_file" "$current_algo"
            ;;
        2)
            local result_file=$(init_result_file "${current_algo}")
            test_curl_sequential "$current_algo" "$result_file"
            generate_summary "$result_file" "$current_algo"
            ;;
        3)
            local result_file=$(init_result_file "${current_algo}")
            test_concurrent_requests "$current_algo" "$result_file"
            generate_summary "$result_file" "$current_algo"
            ;;
        4)
            local result_file=$(init_result_file "${current_algo}")
            test_session_persistence "$current_algo" "$result_file"
            generate_summary "$result_file" "$current_algo"
            ;;
        5)
            local result_file=$(init_result_file "${current_algo}")
            test_response_times "$current_algo" "$result_file"
            generate_summary "$result_file" "$current_algo"
            ;;
        6)
            echo -e "\n${BLUE}══════════════════════════════════════════════${NC}"
            echo -e "${BLUE}  一键测试所有三种算法${NC}"
            echo -e "${BLUE}══════════════════════════════════════════════${NC}"
            echo -e "${YELLOW}注意: 此模式会自动切换 Nginx 负载均衡算法${NC}"
            echo ""

            local switch_script="/home/lk/服务器运维作业/task2-cluster-A/nginx/switch-algorithm.sh"
            local algorithms=("round-robin" "least-conn" "ip-hash")
            local algo_names=("轮询 (Round Robin)" "最少连接 (Least Connections)" "IP 哈希 (IP Hash)")

            for i in 0 1 2; do
                echo -e "\n${GREEN}══════════════════════════════════════════════${NC}"
                echo -e "${GREEN}  测试算法: ${algo_names[$i]}${NC}"
                echo -e "${GREEN}══════════════════════════════════════════════${NC}"

                # 切换算法
                bash "$switch_script" "${algorithms[$i]}"
                echo ""

                # 等待配置生效
                sleep 2

                # 运行测试
                local result_file=$(init_result_file "${algorithms[$i]}")
                test_curl_sequential "${algorithms[$i]}" "$result_file"
                test_response_times "${algorithms[$i]}" "$result_file"
                generate_summary "$result_file" "${algorithms[$i]}"

                echo ""
                echo -e "${YELLOW}按 Enter 继续下一个算法测试...${NC}"
                read
            done
            echo -e "${GREEN}所有算法测试完成!${NC}"
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            exit 1
            ;;
    esac

    # 清理
    rm -rf "$TMP_DIR"

    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  测试完成!                                   ║${NC}"
    echo -e "${GREEN}║  结果保存在: ${RESULT_DIR}${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════╝${NC}"
}

main
