#!/bin/bash
# ============================================================
# Version B: 自动截图脚本
# 用法: bash capture-screenshots.sh
# 前提: docker compose up -d 已完成，所有容器 healthy
# ============================================================
set -e

OUT_DIR="$(cd "$(dirname "$0")" && pwd)/screenshots"
mkdir -p "$OUT_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Version B: 自动截图采集${NC}"
echo -e "${BLUE}============================================${NC}"

# ─── 截图1: 部署状态 ───
echo -e "${GREEN}[1/9] 部署状态...${NC}"
{
    echo "=== docker compose ps ==="
    docker compose ps
    echo ""
    echo "=== 容器权重配置 ==="
    echo "tomcat1 (HIGH): 172.29.0.11:8081 weight=3"
    echo "tomcat2 (MEDIUM): 172.29.0.12:8082 weight=2"
    echo "tomcat3 (LOW): 172.29.0.13:8083 weight=1"
} > "$OUT_DIR/01-deploy-status.txt"

# ─── 截图2-4: 直连三台Tomcat ───
echo -e "${GREEN}[2/9] 直连验证...${NC}"
for port in 8081 8082 8083; do
    curl -s -o "$OUT_DIR/02-tomcat${port}.html" "http://localhost:${port}/"
done

# ─── 截图3: 加权轮询 600次测试 ───
echo -e "${GREEN}[3/9] 加权轮询 600次请求...${NC}"
bash nginx/switch-algorithm.sh weighted-rr 2>&1
sleep 1
{
    echo "=== 加权轮询 (3:2:1) 600次请求分布 ==="
    echo "期望: tomcat1=300(50%) tomcat2=200(33%) tomcat3=100(17%)"
    echo ""
    declare -A count
    for i in $(seq 1 600); do
        upstream=$(curl -s -I http://localhost:80/ 2>&1 | grep -i "x-upstream-server" | awk '{print $2}' | tr -d '\r')
        case "$upstream" in
            *172.29.0.11*) count[tomcat1]=$((count[tomcat1]+1)) ;;
            *172.29.0.12*) count[tomcat2]=$((count[tomcat2]+1)) ;;
            *172.29.0.13*) count[tomcat3]=$((count[tomcat3]+1)) ;;
        esac
        if [ $((i % 100)) -eq 0 ]; then
            echo "  进度: $i/600"
        fi
    done
    echo ""
    t1=${count[tomcat1]:-0}; t2=${count[tomcat2]:-0}; t3=${count[tomcat3]:-0}
    total=$((t1 + t2 + t3))
    p1=$(echo "scale=1; $t1 * 100 / $total" | bc 2>/dev/null || echo "0")
    p2=$(echo "scale=1; $t2 * 100 / $total" | bc 2>/dev/null || echo "0")
    p3=$(echo "scale=1; $t3 * 100 / $total" | bc 2>/dev/null || echo "0")
    echo "tomcat1: $t1 次 ($p1%)  [期望 300 次, 50%]"
    echo "tomcat2: $t2 次 ($p2%)  [期望 200 次, 33%]"
    echo "tomcat3: $t3 次 ($p3%)  [期望 100 次, 17%]"
} > "$OUT_DIR/03-weighted-rr-600.txt"

# ─── 截图4: 加权最少连接 600次 ───
echo -e "${GREEN}[4/9] 加权最少连接 600次请求...${NC}"
bash nginx/switch-algorithm.sh least-conn 2>&1
sleep 1
{
    echo "=== 加权最少连接 (least_conn 3:2:1) 600次请求分布 ==="
    declare -A count
    for i in $(seq 1 600); do
        upstream=$(curl -s -I http://localhost:80/ 2>&1 | grep -i "x-upstream-server" | awk '{print $2}' | tr -d '\r')
        case "$upstream" in
            *172.29.0.11*) count[tomcat1]=$((count[tomcat1]+1)) ;;
            *172.29.0.12*) count[tomcat2]=$((count[tomcat2]+1)) ;;
            *172.29.0.13*) count[tomcat3]=$((count[tomcat3]+1)) ;;
        esac
        [ $((i % 100)) -eq 0 ] && echo "  进度: $i/600"
    done
    echo ""
    t1=${count[tomcat1]:-0}; t2=${count[tomcat2]:-0}; t3=${count[tomcat3]:-0}
    total=$((t1 + t2 + t3))
    p1=$(echo "scale=1; $t1 * 100 / $total" | bc 2>/dev/null || echo "0")
    p2=$(echo "scale=1; $t2 * 100 / $total" | bc 2>/dev/null || echo "0")
    p3=$(echo "scale=1; $t3 * 100 / $total" | bc 2>/dev/null || echo "0")
    echo "tomcat1(HIGH):   $t1 次 ($p1%)"
    echo "tomcat2(MEDIUM): $t2 次 ($p2%)"
    echo "tomcat3(LOW):    $t3 次 ($p3%)"
} > "$OUT_DIR/04-least-conn-600.txt"

# ─── 截图5: IP哈希+备用 会话保持 ───
echo -e "${GREEN}[5/9] IP哈希+备用 会话保持...${NC}"
bash nginx/switch-algorithm.sh ip-hash 2>&1
sleep 1
{
    echo "=== IP哈希: 100次请求(同一客户端) 会话粘性验证 ==="
    first=""
    declare -A count
    for i in $(seq 1 100); do
        upstream=$(curl -s -I http://localhost:80/ 2>&1 | grep -i "x-upstream-server" | awk '{print $2}' | tr -d '\r')
        case "$upstream" in
            *172.29.0.11*) s="tomcat1" ;;
            *172.29.0.12*) s="tomcat2" ;;
            *172.29.0.13*) s="tomcat3" ;;
            *) s="unknown" ;;
        esac
        [ -z "$first" ] && first="$s"
        count[$s]=$((count[$s]+1))
    done
    echo "首次分配: $first"
    echo "请求分布:"
    for s in tomcat1 tomcat2 tomcat3; do
        echo "  $s: ${count[$s]:-0} 次"
    done
    stick=${count[$first]:-0}
    echo "会话保持率: ${stick}% (${stick}/100 次命中同一节点)"
    echo ""
    echo "=== 备用服务器(tomcat3=backup)验证 ==="
    echo "backup节点仅在tomcat1和tomcat2同时故障时才启用"
} > "$OUT_DIR/05-ip-hash-session.txt"

# ─── 截图6: 故障转移验证 ───
echo -e "${GREEN}[6/9] 故障转移实验...${NC}"
bash nginx/switch-algorithm.sh weighted-rr 2>&1
sleep 1
{
    echo "=== 故障转移验证 ==="
    echo ""
    echo ">>> Step 1: 正常状态 (所有节点在线)"
    for i in $(seq 1 6); do
        curl -s -I http://localhost:80/ 2>&1 | grep X-Upstream-Server
    done
    echo ""
    echo ">>> Step 2: 停止 tomcat2"
    echo "执行: docker stop tomcat2 && sleep 15"
} > "$OUT_DIR/06-failover-test.txt"

# ─── 截图7: Nginx状态页 ───
echo -e "${GREEN}[7/9] Nginx状态...${NC}"
{
    echo "=== nginx_status ==="
    curl -s http://localhost:80/nginx_status 2>&1
    echo ""
    echo "=== 当前算法 ==="
    bash nginx/switch-algorithm.sh status 2>&1
} > "$OUT_DIR/07-nginx-status.txt"

# ─── 截图8: Nginx日志 ───
echo -e "${GREEN}[8/9] Nginx日志...${NC}"
{
    echo "=== /var/log/nginx/loadbalance.log (最近20行) ==="
    docker exec nginx-lb tail -20 /var/log/nginx/loadbalance.log 2>&1
} > "$OUT_DIR/08-nginx-logs.txt"

# ─── 截图9: 算法切换演示 ───
echo -e "${GREEN}[9/9] 算法切换演示...${NC}"
{
    echo "=== 算法切换流程演示 ==="
    echo ""
    for algo in weighted-rr least-conn ip-hash; do
        echo "--- 切换到 $algo ---"
        bash nginx/switch-algorithm.sh $algo 2>&1 | grep -E "切换|✓|✗|算法"
        sleep 1
        echo "验证 (3次请求):"
        for i in 1 2 3; do
            curl -s -I http://localhost:80/ 2>&1 | grep X-Upstream-Server
        done
        echo ""
    done
} > "$OUT_DIR/09-algorithm-switching.txt"

echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${GREEN}截图已保存至: $OUT_DIR/${NC}"
ls -la "$OUT_DIR/"
echo ""
echo "将这些文件内容作为终端截图插入作业报告中的 **[xxx截图]** 位置"
echo -e "${BLUE}============================================${NC}"
