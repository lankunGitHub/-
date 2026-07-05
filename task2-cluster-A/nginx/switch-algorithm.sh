#!/bin/bash
# ============================================================
# Nginx 负载均衡算法切换脚本
# 用法: ./switch-algorithm.sh [round-robin|least-conn|ip-hash|status]
# ============================================================

set -e

NGINX_CONF="/home/lk/服务器运维作业/task2-cluster-A/nginx/nginx.conf"
NGINX_CONTAINER="nginx-lb"
ALGORITHM_DIR="/home/lk/服务器运维作业/task2-cluster-A/nginx"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ==================== 函数定义 ====================

# 显示当前算法
show_current_algorithm() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Nginx 负载均衡集群 - 当前状态${NC}"
    echo -e "${BLUE}========================================${NC}"

    # 检查容器是否运行
    if docker ps --format '{{.Names}}' | grep -q "^${NGINX_CONTAINER}$"; then
        echo -e "${GREEN}Nginx 容器状态: 运行中${NC}"

        # 检查 nginx.conf 中是否包含算法指令
        if grep -q "least_conn;" "$NGINX_CONF" 2>/dev/null; then
            echo -e "${YELLOW}当前负载均衡算法: least_conn (最少连接)${NC}"
        elif grep -q "ip_hash;" "$NGINX_CONF" 2>/dev/null; then
            echo -e "${YELLOW}当前负载均衡算法: ip_hash (IP 哈希)${NC}"
        else
            echo -e "${YELLOW}当前负载均衡算法: round-robin (轮询) - 默认算法${NC}"
        fi

        # 显示上游服务器
        echo -e "\n${BLUE}上游 Tomcat 服务器:${NC}"
        echo "  tomcat1: 172.28.0.11:8081"
        echo "  tomcat2: 172.28.0.12:8082"
        echo "  tomcat3: 172.28.0.13:8083"

        # 获取容器 IP
        NGINX_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${NGINX_CONTAINER} 2>/dev/null)
        echo -e "\n${BLUE}Nginx 访问地址:${NC}"
        echo "  http://localhost:80"
        echo "  http://${NGINX_IP}:80"
    else
        echo -e "${RED}Nginx 容器未运行!${NC}"
        echo "请先执行: docker compose up -d"
    fi

    echo -e "${BLUE}========================================${NC}"
}

# 切换到指定算法
switch_algorithm() {
    local ALGO=$1
    local CONF_FILE=""
    local ALGO_NAME=""

    case "$ALGO" in
        round-robin|rr)
            CONF_FILE="${ALGORITHM_DIR}/nginx-round-robin.conf"
            ALGO_NAME="round-robin (轮询)"
            ;;
        least-conn|lc)
            CONF_FILE="${ALGORITHM_DIR}/nginx-least-conn.conf"
            ALGO_NAME="least_conn (最少连接)"
            ;;
        ip-hash|iph|ip_hash)
            CONF_FILE="${ALGORITHM_DIR}/nginx-ip-hash.conf"
            ALGO_NAME="ip_hash (IP 哈希)"
            ;;
        *)
            echo -e "${RED}错误: 未知算法 '${ALGO}'${NC}"
            echo "支持的算法: round-robin, least-conn, ip-hash"
            echo "用法: $0 [round-robin|least-conn|ip-hash|status]"
            exit 1
            ;;
    esac

    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  切换负载均衡算法为: ${ALGO_NAME}${NC}"
    echo -e "${BLUE}========================================${NC}"

    # 检查配置文件是否存在
    if [ ! -f "$CONF_FILE" ]; then
        echo -e "${RED}错误: 找不到配置文件 ${CONF_FILE}${NC}"
        exit 1
    fi

    # 备份当前配置
    if [ -f "$NGINX_CONF" ]; then
        cp "$NGINX_CONF" "${NGINX_CONF}.bak"
        echo -e "${GREEN}已备份当前配置到: ${NGINX_CONF}.bak${NC}"
    fi

    # 从配置文件中提取 upstream 块
    # 使用 sed 替换 nginx.conf 中的 upstream 块
    echo -e "${YELLOW}正在更新 Nginx 配置...${NC}"

    # 读取 nginx-round-robin.conf (或其他算法配置文件) 中的 upstream 块
    UPSTREAM_BLOCK=$(cat "$CONF_FILE")

    # 替换 nginx.conf 中的 upstream 块
    # 使用 awk 进行精确替换
    awk -v new_upstream="$UPSTREAM_BLOCK" '
    BEGIN { in_upstream = 0; upstream_printed = 0; }
    /^upstream tomcat_cluster/ { in_upstream = 1; }
    {
        if (in_upstream && /^}/) {
            if (!upstream_printed) {
                print new_upstream;
                upstream_printed = 1;
            }
            in_upstream = 0;
            next;
        }
        if (!in_upstream) print;
    }
    ' "$NGINX_CONF" > "${NGINX_CONF}.tmp" && mv "${NGINX_CONF}.tmp" "$NGINX_CONF"

    echo -e "${GREEN}配置文件已更新${NC}"

    # 重新加载 Nginx 配置
    echo -e "${YELLOW}正在重新加载 Nginx 配置...${NC}"

    # 检查容器是否运行
    if docker ps --format '{{.Names}}' | grep -q "^${NGINX_CONTAINER}$"; then
        # 测试 Nginx 配置语法
        if docker exec ${NGINX_CONTAINER} nginx -t 2>&1; then
            docker exec ${NGINX_CONTAINER} nginx -s reload
            echo -e "${GREEN}✓ Nginx 配置已安全重新加载${NC}"
            echo -e "${GREEN}✓ 当前算法: ${ALGO_NAME}${NC}"
        else
            echo -e "${RED}✗ Nginx 配置测试失败，正在恢复备份...${NC}"
            if [ -f "${NGINX_CONF}.bak" ]; then
                cp "${NGINX_CONF}.bak" "$NGINX_CONF"
                docker exec ${NGINX_CONTAINER} nginx -s reload
                echo -e "${GREEN}已恢复之前的配置${NC}"
            fi
            exit 1
        fi
    else
        echo -e "${YELLOW}Nginx 容器未运行，配置已更新但未生效。${NC}"
        echo "请执行 'docker compose up -d' 启动服务"
    fi

    echo -e "${BLUE}========================================${NC}"
}

# ==================== 主逻辑 ====================

case "${1:-status}" in
    status)
        show_current_algorithm
        ;;
    round-robin|rr|least-conn|lc|ip-hash|iph|ip_hash)
        switch_algorithm "$1"
        ;;
    *)
        echo "用法: $0 [round-robin|least-conn|ip-hash|status]"
        echo ""
        echo "示例:"
        echo "  $0 status          # 查看当前状态"
        echo "  $0 round-robin     # 切换到轮询算法"
        echo "  $0 least-conn      # 切换到最少连接算法"
        echo "  $0 ip-hash         # 切换到 IP 哈希算法"
        exit 1
        ;;
esac
