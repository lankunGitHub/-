<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" %>
<%@ page import="java.net.InetAddress, java.util.Date, java.text.SimpleDateFormat" %>
<%
    // 会话计数器 - 用于验证会话保持和加权分发
    String serverName = System.getenv("SERVER_NAME");
    if (serverName == null || serverName.isEmpty()) serverName = "unknown";
    String serverCapacity = System.getenv("SERVER_CAPACITY");
    if (serverCapacity == null) serverCapacity = "NORMAL";

    InetAddress localHost = InetAddress.getLocalHost();

    // 获取或创建会话访问计数
    Integer visitCount = (Integer) session.getAttribute("visit_count");
    if (visitCount == null) visitCount = 0;
    visitCount++;
    session.setAttribute("visit_count", visitCount);

    String sessionId = session.getId();
    Date now = new Date();
    SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS");

    // 容量标签颜色
    String capColor = "#43e97b"; // LOW=green
    if ("HIGH".equals(serverCapacity)) capColor = "#667eea";    // purple
    else if ("MEDIUM".equals(serverCapacity)) capColor = "#f5576c"; // pink
%>
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <title>集群会话计数器 - <%= serverName %></title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Microsoft YaHei', sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%);
            min-height: 100vh;
            display: flex; justify-content: center; align-items: center;
        }
        .card {
            background: #fff;
            border-radius: 24px;
            padding: 48px 40px;
            max-width: 480px;
            width: 100%;
            box-shadow: 0 24px 80px rgba(0,0,0,0.4);
            text-align: center;
        }
        .server-icon {
            width: 80px; height: 80px;
            border-radius: 50%;
            background: <%= capColor %>;
            margin: 0 auto 20px;
            display: flex; align-items: center; justify-content: center;
            font-size: 36px; color: white; font-weight: bold;
        }
        h2 { color: #333; margin-bottom: 8px; }
        .capacity-badge {
            display: inline-block;
            padding: 4px 16px;
            border-radius: 12px;
            font-size: 12px;
            font-weight: bold;
            color: white;
            background: <%= capColor %>;
            margin-bottom: 24px;
        }
        .counter {
            font-size: 72px; font-weight: bold;
            color: <%= capColor %>;
            margin: 24px 0;
            font-variant-numeric: tabular-nums;
        }
        .counter-label {
            font-size: 14px; color: #888; text-transform: uppercase; letter-spacing: 2px;
        }
        .info-row {
            display: flex; justify-content: space-between;
            padding: 12px 0; border-bottom: 1px solid #f0f0f0;
            font-size: 13px;
        }
        .info-row .label { color: #888; }
        .info-row .value { color: #333; font-weight: 500; }
        .session-id {
            font-size: 11px; color: #aaa; word-break: break-all;
            margin-top: 20px; padding-top: 20px; border-top: 1px solid #eee;
        }
        .refresh-hint {
            margin-top: 24px;
            padding: 10px 24px;
            background: <%= capColor %>;
            color: white; border: none; border-radius: 8px;
            font-size: 14px; cursor: pointer; text-decoration: none; display: inline-block;
        }
        @keyframes pulse {
            0%,100% { transform: scale(1); }
            50% { transform: scale(1.05); }
        }
        .counter { animation: pulse 3s infinite; }
    </style>
</head>
<body>
    <div class="card">
        <div class="server-icon"><%= serverCapacity.charAt(0) %></div>
        <h2><%= serverName %></h2>
        <div class="capacity-badge"><%= serverCapacity %> Capacity</div>

        <div class="counter-label">会话访问次数</div>
        <div class="counter"><%= visitCount %></div>

        <div class="info-row">
            <span class="label">服务器IP</span>
            <span class="value"><%= localHost.getHostAddress() %></span>
        </div>
        <div class="info-row">
            <span class="label">当前时间</span>
            <span class="value"><%= sdf.format(now) %></span>
        </div>
        <div class="info-row">
            <span class="label">服务器能力</span>
            <span class="value"><%= serverCapacity %></span>
        </div>

        <div class="session-id">
            Session ID: <%= sessionId %>
        </div>

        <a href="javascript:location.reload()" class="refresh-hint">
            点击刷新 (第 <%= visitCount + 1 %> 次)
        </a>
    </div>
</body>
</html>
