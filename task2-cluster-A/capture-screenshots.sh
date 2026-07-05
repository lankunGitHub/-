#!/bin/bash
# ============================================================
# Version A: 自动截图脚本
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
echo -e "${BLUE}  Version A: 自动截图采集${NC}"
echo -e "${BLUE}============================================${NC}"

# ─── 截图1: 部署状态 ───
echo -e "${GREEN}[1/8] 部署状态...${NC}"
{
    echo "=== docker compose ps ==="
    docker compose ps
    echo ""
    echo "=== docker compose logs nginx --tail 5 ==="
    docker compose logs nginx --tail 5 2>&1
} > "$OUT_DIR/01-deploy-status.txt"

# ─── 截图2-4: 直连三个Tomcat ───
echo -e "${GREEN}[2/8] 直连验证...${NC}"
for port in 8081 8082 8083; do
    curl -s -o "$OUT_DIR/02-tomcat${port}.html" "http://localhost:${port}/"
done

# ─── 截图3: Nginx代理访问 (轮询) ───
echo -e "${GREEN}[3/8] Nginx代理访问(轮询)...${NC}"
{
    echo "=== 轮询算法: 连续30次请求的上游服务器 ==="
    for i in $(seq 1 30); do
        upstream=$(curl -s -I http://localhost:80/ 2>&1 | grep -i "x-upstream-server" | awk '{print $2}' | tr -d '\r')
        echo "请求 #$i → $upstream"
    done
} > "$OUT_DIR/03-round-robin-30.txt"

# ─── 截图4: 最少连接算法 ───
echo -e "${GREEN}[4/8] 切换到最少连接...${NC}"
bash nginx/switch-algorithm.sh least-conn 2>&1
sleep 2
{
    echo "=== 最少连接算法: 连续30次请求的上游服务器 ==="
    for i in $(seq 1 30); do
        upstream=$(curl -s -I http://localhost:80/ 2>&1 | grep -i "x-upstream-server" | awk '{print $2}' | tr -d '\r')
        echo "请求 #$i → $upstream"
    done
} > "$OUT_DIR/04-least-conn-30.txt"

# ─── 截图5: IP哈希算法 ───
echo -e "${GREEN}[5/8] 切换到IP哈希...${NC}"
bash nginx/switch-algorithm.sh ip-hash 2>&1
sleep 2
{
    echo "=== IP哈希算法: 连续30次请求的上游服务器(同一客户端IP) ==="
    for i in $(seq 1 30); do
        upstream=$(curl -s -I http://localhost:80/ 2>&1 | grep -i "x-upstream-server" | awk '{print $2}' | tr -d '\r')
        echo "请求 #$i → $upstream"
    done
} > "$OUT_DIR/05-ip-hash-30.txt"

# ─── 截图6: 响应时间对比 ───
echo -e "${GREEN}[6/8] 响应时间测试...${NC}"
bash nginx/switch-algorithm.sh round-robin 2>&1
sleep 1
{
    echo "=== 三种算法响应时间对比 (各30次) ==="
    for algo in round-robin least-conn ip-hash; do
        bash nginx/switch-algorithm.sh $algo 2>&1 | tail -1
        sleep 1
        echo "--- $algo ---"
        for i in $(seq 1 30); do
            t=$(curl -s -o /dev/null -w "%{time_total}" http://localhost:80/)
            echo "$t"
        done
    done
} > "$OUT_DIR/06-response-times.txt"

# ─── 截图7: Nginx日志 ───
echo -e "${GREEN}[7/8] Nginx负载均衡日志...${NC}"
{
    echo "=== /var/log/nginx/loadbalance.log (最近20行) ==="
    docker exec nginx-lb tail -20 /var/log/nginx/loadbalance.log 2>&1
} > "$OUT_DIR/07-nginx-logs.txt"

# ─── 截图8: 测试脚本示例 ───
echo -e "${GREEN}[8/8] 测试统计...${NC}"
bash nginx/switch-algorithm.sh round-robin 2>&1 | tail -1
{
    echo "=== 100次请求分布统计 ==="
    declare -A count
    for i in $(seq 1 100); do
        upstream=$(curl -s -I http://localhost:80/ 2>&1 | grep -i "x-upstream-server" | awk '{print $2}' | tr -d '\r')
        case "$upstream" in
            *172.28.0.11*) count[tomcat1]=$((count[tomcat1]+1)) ;;
            *172.28.0.12*) count[tomcat2]=$((count[tomcat2]+1)) ;;
            *172.28.0.13*) count[tomcat3]=$((count[tomcat3]+1)) ;;
        esac
    done
    echo "tomcat1: ${count[tomcat1]:-0} 次"
    echo "tomcat2: ${count[tomcat2]:-0} 次"
    echo "tomcat3: ${count[tomcat3]:-0} 次"
} > "$OUT_DIR/08-distribution-stats.txt"

echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${GREEN}截图已保存至: $OUT_DIR/${NC}"
ls -la "$OUT_DIR/"
echo ""
echo "将这些文件内容作为终端截图插入作业报告中的 **[xxx截图]** 位置"
echo -e "${BLUE}============================================${NC}"
