<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" %>
<%@ page import="java.net.InetAddress, java.util.Date, java.text.SimpleDateFormat" %>
<%
    String serverName = System.getenv("SERVER_NAME");
    if (serverName == null || serverName.isEmpty()) serverName = "unknown";
    String serverCapacity = System.getenv("SERVER_CAPACITY");
    if (serverCapacity == null) serverCapacity = "NORMAL";
    InetAddress localHost = InetAddress.getLocalHost();
    Integer visitCount = (Integer) session.getAttribute("visit_count");
    if (visitCount == null) visitCount = 0;
    visitCount++;
    session.setAttribute("visit_count", visitCount);
    String sessionId = session.getId();
    SimpleDateFormat sdf = new SimpleDateFormat("HH:mm:ss");
    String capIcon = "H".equals(serverCapacity)?"⚡":"M".equals(serverCapacity)?"⚙":"📡";
    String capColor = "HIGH".equals(serverCapacity)?"#00d4ff":"MEDIUM".equals(serverCapacity)?"#ff9f43":"#10ac84";
%>
<!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8"><title>运维监控 — <%= serverName %></title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:'SF Mono','JetBrains Mono','Consolas',monospace;background:#0a0e17;color:#c8d6e5;min-height:100vh;display:flex}
.sidebar{width:240px;background:#0d1117;padding:24px 18px;border-right:1px solid #1a2332;display:flex;flex-direction:column}
.sidebar .logo{font-size:20px;font-weight:bold;color:#00d4ff;margin-bottom:8px;letter-spacing:2px}
.sidebar .ver{font-size:10px;color:#576574;margin-bottom:30px}
.sidebar .nav{list-style:none}.sidebar .nav li{padding:10px 12px;margin:3px 0;border-radius:6px;color:#8395a7;font-size:13px;cursor:pointer;transition:.2s}
.sidebar .nav li:hover,.sidebar .nav li.active{background:#1a2332;color:#c8d6e5}
.main{flex:1;padding:30px 36px;overflow-y:auto}
.topbar{display:flex;justify-content:space-between;align-items:center;margin-bottom:28px}
.topbar h1{font-size:22px;font-weight:600;color:#dfe6e9}
.topbar .time{font-size:13px;color:#576574;font-family:monospace}
.stats-row{display:grid;grid-template-columns:repeat(3,1fr);gap:16px;margin-bottom:24px}
.stat-card{background:#111820;border:1px solid #1a2332;border-radius:10px;padding:20px;text-align:center;transition:.2s}
.stat-card:hover{border-color:<%= capColor %>}
.stat-card .num{font-size:36px;font-weight:bold;color:<%= capColor %>;font-family:monospace}
.stat-card .lbl{font-size:11px;color:#576574;margin-top:6px;letter-spacing:1px}
.panel{background:#111820;border:1px solid #1a2332;border-radius:10px;padding:24px;margin-bottom:18px}
.panel h3{font-size:14px;color:#576574;margin-bottom:16px;letter-spacing:1px;text-transform:uppercase}
.info-row{display:flex;justify-content:space-between;padding:10px 0;border-bottom:1px solid #151d28;font-size:13px}
.info-row .k{color:#576574}.info-row .v{color:#c8d6e5;font-family:monospace}
.tags{display:flex;gap:8px;margin-top:12px}
.tag{padding:4px 12px;border-radius:4px;font-size:10px;letter-spacing:1px}
.tag-h{background:rgba(0,212,255,.15);color:#00d4ff}.tag-m{background:rgba(255,159,67,.15);color:#ff9f43}.tag-l{background:rgba(16,172,132,.15);color:#10ac84}
.server-indicator{display:flex;align-items:center;gap:8px;font-size:14px;color:#00d4ff}
.server-indicator .dot{width:8px;height:8px;border-radius:50%;background:<%= capColor %>;animation:pulse 2s infinite}
@keyframes pulse{0%,100%{opacity:1;box-shadow:0 0 8px <%= capColor %>}50%{opacity:.4;box-shadow:0 0 2px <%= capColor %>}}
.capacity-bar{height:4px;background:#1a2332;border-radius:2px;margin-top:8px;overflow:hidden}
.capacity-bar .fill{height:100%;background:<%= capColor %>;border-radius:2px;width:<%= "HIGH".equals(serverCapacity)?"100":"MEDIUM".equals(serverCapacity)?"66":"33" %>%}
.session-id{font-size:10px;color:#3d4f5f;word-break:break-all;margin-top:16px}
</style></head><body>
<div class="sidebar">
<div class="logo">■ CLUSTER</div><div class="ver">v2.0 · weighted LB</div>
<ul class="nav">
<li class="active">📊 集群概览</li>
<li>🖥 节点管理</li>
<li>📈 流量分析</li>
<li>⚙ 负载均衡</li>
<li>🔔 告警规则</li>
</ul>
</div>
<div class="main">
<div class="topbar">
<div><h1><%= serverName %></h1><div class="server-indicator"><span class="dot"></span> 运行中 · <%= serverCapacity %> Capacity</div></div>
<div class="time"><%= sdf.format(new Date()) %></div>
</div>
<div class="stats-row">
<div class="stat-card"><div class="num"><%= visitCount %></div><div class="lbl">会话请求次数</div></div>
<div class="stat-card"><div class="num"><%= request.getServerPort() %></div><div class="lbl">服务端口</div></div>
<div class="stat-card"><div class="num"><%= capIcon %></div><div class="lbl">性能等级</div></div>
</div>
<div class="panel">
<h3>📋 节点信息</h3>
<div class="info-row"><span class="k">主机名</span><span class="v"><%= localHost.getHostName() %></span></div>
<div class="info-row"><span class="k">IP 地址</span><span class="v"><%= localHost.getHostAddress() %></span></div>
<div class="info-row"><span class="k">客户端 IP</span><span class="v"><%= request.getRemoteAddr() %></span></div>
<div class="info-row"><span class="k">请求方式</span><span class="v"><%= request.getMethod() %> <%= request.getRequestURI() %></span></div>
<div style="margin-top:12px">
<span style="font-size:11px;color:#576574">处理能力</span>
<div class="capacity-bar"><div class="fill"></div></div>
</div>
<div class="tags">
<span class="tag tag-<%= "HIGH".equals(serverCapacity)?"h":"MEDIUM".equals(serverCapacity)?"m":"l" %>"><%= serverCapacity %></span>
<span class="tag tag-h">weight=<%= "HIGH".equals(serverCapacity)?"3":"MEDIUM".equals(serverCapacity)?"2":"1" %></span>
</div>
</div>
<div class="panel">
<h3>🔗 代理信息</h3>
<div class="info-row"><span class="k">X-Forwarded-For</span><span class="v"><%= request.getHeader("X-Forwarded-For")!=null?request.getHeader("X-Forwarded-For"):"—" %></span></div>
<div class="info-row"><span class="k">X-Real-IP</span><span class="v"><%= request.getHeader("X-Real-IP")!=null?request.getHeader("X-Real-IP"):"—" %></span></div>
</div>
<div class="session-id">SESSION <%= sessionId %></div>
</div></body></html>
