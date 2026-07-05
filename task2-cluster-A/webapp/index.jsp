<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" %>
<%@ page import="java.net.InetAddress, java.util.Date, java.text.SimpleDateFormat" %>
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Tomcat 集群 - 服务器信息</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: 'Microsoft YaHei', 'PingFang SC', Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
            padding: 20px;
        }
        .container {
            background: white;
            border-radius: 20px;
            padding: 40px;
            max-width: 700px;
            width: 100%;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            animation: fadeIn 0.5s ease-in-out;
        }
        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(20px); }
            to { opacity: 1; transform: translateY(0); }
        }
        h1 {
            text-align: center;
            color: #333;
            font-size: 28px;
            margin-bottom: 10px;
        }
        .subtitle {
            text-align: center;
            color: #888;
            font-size: 14px;
            margin-bottom: 30px;
        }
        .server-badge {
            display: inline-block;
            padding: 6px 20px;
            border-radius: 20px;
            font-size: 14px;
            font-weight: bold;
            color: white;
            margin-bottom: 20px;
        }
        .badge-tomcat1 { background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%); }
        .badge-tomcat2 { background: linear-gradient(135deg, #4facfe 0%, #00f2fe 100%); }
        .badge-tomcat3 { background: linear-gradient(135deg, #43e97b 0%, #38f9d7 100%); }
        .badge-unknown { background: linear-gradient(135deg, #a8a8a8 0%, #666 100%); }

        .info-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 15px;
            margin: 25px 0;
        }
        .info-item {
            background: #f5f7fa;
            border-radius: 12px;
            padding: 18px;
            transition: transform 0.2s;
        }
        .info-item:hover {
            transform: translateY(-2px);
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
        }
        .info-item .label {
            font-size: 12px;
            color: #888;
            text-transform: uppercase;
            letter-spacing: 1px;
            margin-bottom: 5px;
        }
        .info-item .value {
            font-size: 18px;
            color: #333;
            font-weight: bold;
            word-break: break-all;
        }
        .info-item.full-width {
            grid-column: 1 / -1;
        }

        .footer {
            text-align: center;
            margin-top: 25px;
            padding-top: 20px;
            border-top: 1px solid #eee;
            color: #aaa;
            font-size: 12px;
        }

        .status-bar {
            display: flex;
            justify-content: center;
            gap: 10px;
            margin: 20px 0;
        }
        .status-dot {
            width: 12px;
            height: 12px;
            border-radius: 50%;
            background: #ddd;
            animation: pulse 2s infinite;
        }
        .status-dot.active {
            background: #43e97b;
        }
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }

        .request-info {
            background: #fff3cd;
            border-radius: 12px;
            padding: 15px;
            margin-bottom: 20px;
            border-left: 4px solid #ffc107;
        }
        .request-info .label {
            font-size: 12px;
            color: #856404;
        }
        .request-info .value {
            font-size: 14px;
            color: #533f03;
            font-weight: bold;
        }

        @media (max-width: 600px) {
            .container { padding: 25px; }
            .info-grid { grid-template-columns: 1fr; }
        }
    </style>
</head>
<body>
    <div class="container">
        <%
            // 获取服务器信息
            String serverName = System.getenv("SERVER_NAME");
            if (serverName == null || serverName.isEmpty()) {
                serverName = "unknown";
            }

            InetAddress localHost = InetAddress.getLocalHost();
            String hostName = localHost.getHostName();
            String hostAddress = localHost.getHostAddress();

            String serverPort = request.getServerPort() + "";
            String protocol = request.getProtocol();
            String scheme = request.getScheme();
            String method = request.getMethod();
            String requestURI = request.getRequestURI();
            String queryString = request.getQueryString();
            String remoteAddr = request.getRemoteAddr();
            String remoteHost = request.getRemoteHost();
            String sessionId = request.getRequestedSessionId();
            if (sessionId == null) {
                sessionId = "N/A (无会话)";
            }

            // 尝试创建会话以获取 ID
            session.setAttribute("last_access", new Date().toString());

            // 日期格式化
            SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS");
            String currentTime = sdf.format(new Date());

            // 获取请求头中的代理信息
            String xForwardedFor = request.getHeader("X-Forwarded-For");
            String xRealIP = request.getHeader("X-Real-IP");
            String userAgent = request.getHeader("User-Agent");

            // 确定 badge 样式
            String badgeClass = "badge-unknown";
            if ("tomcat1".equals(serverName)) badgeClass = "badge-tomcat1";
            else if ("tomcat2".equals(serverName)) badgeClass = "badge-tomcat2";
            else if ("tomcat3".equals(serverName)) badgeClass = "badge-tomcat3";
        %>

        <h1>Tomcat 集群服务器信息</h1>
        <p class="subtitle">该页面显示处理当前请求的 Tomcat 实例详情</p>

        <div style="text-align: center;">
            <span class="server-badge <%= badgeClass %>">
                当前服务器: <%= serverName %>
            </span>
        </div>

        <div class="request-info">
            <table style="width:100%; border-collapse: collapse;">
                <tr>
                    <td style="width:50%; padding: 5px;">
                        <div class="label">请求方式</div>
                        <div class="value"><%= method %> <%= requestURI %></div>
                    </td>
                    <td style="width:50%; padding: 5px;">
                        <div class="label">客户端 IP</div>
                        <div class="value"><%= remoteAddr %></div>
                    </td>
                </tr>
            </table>
        </div>

        <div class="info-grid">
            <div class="info-item">
                <div class="label">服务器主机名</div>
                <div class="value"><%= hostName %></div>
            </div>
            <div class="info-item">
                <div class="label">服务器 IP 地址</div>
                <div class="value"><%= hostAddress %></div>
            </div>
            <div class="info-item">
                <div class="label">服务器端口</div>
                <div class="value"><%= serverPort %></div>
            </div>
            <div class="info-item">
                <div class="label">服务器名称</div>
                <div class="value"><%= serverName %></div>
            </div>
            <div class="info-item">
                <div class="label">当前时间</div>
                <div class="value"><%= currentTime %></div>
            </div>
            <div class="info-item">
                <div class="label">会话 ID</div>
                <div class="value" style="font-size:14px;"><%= sessionId %></div>
            </div>
            <div class="info-item full-width">
                <div class="label">客户端代理信息</div>
                <div class="value" style="font-size:13px; font-weight:normal;">
                    X-Forwarded-For: <%= xForwardedFor != null ? xForwardedFor : "无" %><br>
                    X-Real-IP: <%= xRealIP != null ? xRealIP : "无" %><br>
                    User-Agent: <%= userAgent != null ? userAgent : "无" %>
                </div>
            </div>
        </div>

        <div class="status-bar">
            <span class="status-dot active"></span>
            <span style="font-size:13px; color:#666;">Tomcat 集群运行中 · 3 个节点</span>
            <span class="status-dot active"></span>
        </div>

        <div class="footer">
            Tomcat 9 Cluster - Nginx 负载均衡演示 &copy; 2026
        </div>
    </div>
</body>
</html>
