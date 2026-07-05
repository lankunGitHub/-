#!/bin/bash
# Nginx 负载均衡算法切换脚本 — 可靠版（完整配置替换）
unset DOCKER_HOST
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
CONTAINER="nginx-lb"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

show_status() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Nginx 负载均衡集群 - 当前状态${NC}"
    echo -e "${BLUE}========================================${NC}"
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
        echo -e "${GREEN}Nginx 容器: 运行中${NC}"
        if grep -q "least_conn;" "$DIR/nginx.conf" 2>/dev/null; then
            echo -e "${YELLOW}算法: least_conn (最少连接)${NC}"
        elif grep -q "ip_hash;" "$DIR/nginx.conf" 2>/dev/null; then
            echo -e "${YELLOW}算法: ip_hash (IP 哈希)${NC}"
        else
            echo -e "${YELLOW}算法: round-robin (轮询)${NC}"
        fi
        echo "  tomcat1: 172.28.0.11:8081  tomcat2: 172.28.0.12:8082  tomcat3: 172.28.0.13:8083"
    else
        echo -e "${RED}Nginx 容器未运行!${NC}"
    fi
    echo -e "${BLUE}========================================${NC}"
}

switch_to() {
    local algo="$1" name="$2"
    echo -e "${BLUE}切换至: ${name}${NC}"
    cp "$DIR/nginx-${algo}-full.conf" "$DIR/nginx.conf"
    echo -e "${GREEN}配置文件已更新${NC}"
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
        docker restart ${CONTAINER} >/dev/null 2>&1
        for i in $(seq 1 15); do
            sleep 1
            if curl -s -o /dev/null http://localhost:80/ 2>/dev/null; then
                echo -e "${GREEN}✓ 已切换至: ${name} (${i}s)${NC}"
                return
            fi
            echo -n "."
        done
        echo -e "\n${RED}✗ Nginx 启动超时!${NC}"
    fi
}

case "${1:-status}" in
    status)        show_status ;;
    round-robin|rr) switch_to "round-robin" "轮询 (Round Robin)" ;;
    least-conn|lc)  switch_to "least-conn" "最少连接 (Least Connections)" ;;
    ip-hash|iph)    switch_to "ip-hash" "IP 哈希 (IP Hash)" ;;
    *) echo "用法: $0 [round-robin|least-conn|ip-hash|status]" ;;
esac
