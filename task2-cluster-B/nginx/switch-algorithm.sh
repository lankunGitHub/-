#!/bin/bash
export DOCKER_HOST="${DOCKER_HOST:-unix:///var/run/docker.sock}"
unset DOCKER_HOST
# Version B: Nginx 负载均衡算法切换脚本
# 支持: weighted-rr (加权轮询), least-conn (加权最少连接),
#       ip-hash-backup (IP哈希+备用服务器)
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NGINX_CONF="$SCRIPT_DIR/nginx.conf"
NGINX_CONTAINER="nginx-lb"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

show_status() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Version B: 加权负载均衡集群 - 状态${NC}"
    echo -e "${BLUE}========================================${NC}"
    if docker ps --format '{{.Names}}' | grep -q "^${NGINX_CONTAINER}$"; then
        echo -e "${GREEN}Nginx: 运行中${NC}"
        if grep -q "least_conn;" "$NGINX_CONF" 2>/dev/null; then
            echo -e "${YELLOW}算法: 加权最少连接 (weight=3:2:1)${NC}"
        elif grep -q "ip_hash;" "$NGINX_CONF" 2>/dev/null; then
            echo -e "${YELLOW}算法: IP哈希 + 备用服务器${NC}"
        else
            echo -e "${YELLOW}算法: 加权轮询 (weight=3:2:1)${NC}"
        fi
        echo "  权重: tomcat1=3 (HIGH)  tomcat2=2 (MEDIUM)  tomcat3=1 (LOW)"
    else
        echo -e "${RED}Nginx 未运行${NC}"
    fi
    echo -e "${BLUE}========================================${NC}"
}

switch_to() {
    local algo="$1" algo_name="$2" conf_file=""
    case "$algo" in
        weighted-rr) conf_file="$SCRIPT_DIR/nginx.conf"; algo_name="加权轮询 (3:2:1)";;
        least-conn)  conf_file="$SCRIPT_DIR/nginx-least-conn.conf"; algo_name="加权最少连接 (3:2:1)";;
        ip-hash)     conf_file="$SCRIPT_DIR/nginx-ip-hash.conf"; algo_name="IP哈希 + 备用服务器";;
        *) echo -e "${RED}未知算法: $algo${NC}"; echo "用法: $0 [weighted-rr|least-conn|ip-hash|status]"; exit 1;;
    esac

    echo -e "${BLUE}切换至: ${algo_name}${NC}"
    cp "$NGINX_CONF" "${NGINX_CONF}.bak"
    local upstream=$(cat "$conf_file")
    awk -v new_ups="$upstream" '
    BEGIN { in_ups=0; printed=0 }
    /^upstream tomcat_cluster/ { in_ups=1 }
    { if (in_ups && /^}/) { if(!printed){print new_ups; printed=1} in_ups=0; next } if(!in_ups) print }
    ' "$NGINX_CONF" > "${NGINX_CONF}.tmp" && mv "${NGINX_CONF}.tmp" "$NGINX_CONF"

    if docker ps --format '{{.Names}}' | grep -q "^${NGINX_CONTAINER}$"; then
        if docker exec ${NGINX_CONTAINER} nginx -t 2>&1; then
            docker exec ${NGINX_CONTAINER} nginx -s reload
            echo -e "${GREEN}✓ 已切换至: ${algo_name}${NC}"
        else
            cp "${NGINX_CONF}.bak" "$NGINX_CONF"
            echo -e "${RED}✗ 配置测试失败，已恢复${NC}"; exit 1
        fi
    fi
}

case "${1:-status}" in
    status)       show_status;;
    weighted-rr) switch_to "weighted-rr";;
    least-conn)  switch_to "least-conn";;
    ip-hash)     switch_to "ip-hash";;
    *) echo "用法: $0 [weighted-rr|least-conn|ip-hash|status]";;
esac
