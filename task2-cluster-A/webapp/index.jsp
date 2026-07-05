<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" %>
<%@ page import="java.net.InetAddress, java.util.Date, java.text.SimpleDateFormat" %>
<%
    String serverName = System.getenv("SERVER_NAME");
    if (serverName == null || serverName.isEmpty()) serverName = "unknown";
    InetAddress localHost = InetAddress.getLocalHost();
    String sessionId = session.getId();
    session.setAttribute("last_access", new Date().toString());
    SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS");
    String xForwardedFor = request.getHeader("X-Forwarded-For");
%>
<!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8"><title>服务器信息 — <%= serverName %></title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:'Microsoft YaHei',sans-serif;background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);min-height:100vh;display:flex;justify-content:center;align-items:center;padding:20px}
.card{background:white;border-radius:20px;padding:40px;max-width:680px;width:100%;box-shadow:0 20px 60px rgba(0,0,0,0.3)}
h1{text-align:center;color:#333;font-size:26px;margin-bottom:6px}
.sub{text-align:center;color:#999;font-size:13px;margin-bottom:24px}
.badge{display:inline-block;padding:6px 22px;border-radius:20px;font-size:14px;font-weight:bold;color:white;margin-bottom:20px}
.b1{background:linear-gradient(135deg,#f093fb,#f5576c)}.b2{background:linear-gradient(135deg,#4facfe,#00f2fe)}.b3{background:linear-gradient(135deg,#43e97b,#38f9d7)}
.badge-row{text-align:center}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:13px;margin:20px 0}
.item{background:#f5f7fa;border-radius:12px;padding:15px;transition:transform .2s}.item:hover{transform:translateY(-2px)}
.item .lbl{font-size:11px;color:#999;letter-spacing:1px;margin-bottom:4px;text-transform:uppercase}
.item .val{font-size:16px;color:#333;font-weight:bold}
.full{grid-column:1/-1}
.status{text-align:center;margin:14px 0}.status span{display:inline-block;width:10px;height:10px;border-radius:50%;background:#43e97b;margin:0 4px;animation:pulse 2s infinite}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:.4}}
.foot{text-align:center;margin-top:18px;padding-top:18px;border-top:1px solid #eee;color:#bbb;font-size:11px}
</style></head><body>
<div class="card">
<h1>Tomcat 集群服务器信息</h1>
<p class="sub">Nginx 反向代理 · 负载均衡演示</p>
<div class="badge-row"><span class="badge <%= serverName.equals("tomcat2")?"b2":serverName.equals("tomcat3")?"b3":"b1" %>">当前服务器: <%= serverName %></span></div>
<div class="grid">
<div class="item"><div class="lbl">主机名</div><div class="val"><%= localHost.getHostName() %></div></div>
<div class="item"><div class="lbl">IP 地址</div><div class="val"><%= localHost.getHostAddress() %></div></div>
<div class="item"><div class="lbl">端口</div><div class="val"><%= request.getServerPort() %></div></div>
<div class="item"><div class="lbl">服务器时间</div><div class="val" style="font-size:14px"><%= sdf.format(new Date()) %></div></div>
<div class="item"><div class="lbl">请求方式</div><div class="val"><%= request.getMethod() %></div></div>
<div class="item"><div class="lbl">客户端 IP</div><div class="val"><%= request.getRemoteAddr() %></div></div>
<div class="item full"><div class="lbl">X-Forwarded-For</div><div class="val" style="font-size:13px;font-weight:normal"><%= xForwardedFor!=null?xForwardedFor:"无 (直连)" %></div></div>
<div class="item full"><div class="lbl">会话 Session ID</div><div class="val" style="font-size:11px;font-weight:normal"><%= sessionId %></div></div>
</div>
<div class="status"><span></span><span></span><span></span></div>
<div class="foot">Tomcat 9 Cluster · Nginx Load Balancer © 2026</div>
</div></body></html>
