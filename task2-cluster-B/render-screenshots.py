#!/usr/bin/env python3
"""Version B — Real HTML→PNG screenshots via weasyprint + terminal via Pillow"""
import subprocess, os, time
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import weasyprint

BASE = Path(__file__).resolve().parent
OUT = BASE / "screenshots"
OUT.mkdir(parents=True, exist_ok=True)
os.chdir(BASE)

W, H = 900, 620
BG, FG = (30,30,40), (200,220,240)
GREEN, CYAN, YELLOW, WHITE = (80,220,120), (80,200,240), (240,200,80), (255,255,255)

FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
if not os.path.exists(FONT_PATH): FONT_PATH = None

def mfont(size=14):
    if FONT_PATH: return ImageFont.truetype(FONT_PATH, size)
    return ImageFont.load_default()

def term_png(title, lines, fname, w=900, h=620):
    img = Image.new('RGB', (w,h), BG)
    d = ImageDraw.Draw(img)
    d.rectangle([0,0,w,30], fill=(50,50,65))
    d.text((12,6), f"  {title}  ", fill=WHITE, font=mfont(16))
    y = 42
    for line in lines[:36]:
        c = FG
        if any(k in line for k in ['✓','OK','Healthy','200']): c = GREEN
        elif any(k in line for k in ['══','──','┌','├','└']): c = CYAN
        elif any(k in line for k in ['→','==','>>']): c = YELLOW
        d.text((16,y), line[:120], fill=c, font=mfont(14))
        y += 20
        if y > h-20: break
    img.save(str(OUT/fname))
    print(f"  [OK] {fname}")

def web_png(url, fname, width=900):
    """Render HTML→PDF→PNG using weasyprint + pdftoppm"""
    try:
        r = subprocess.run(["curl","-s",url], capture_output=True, text=True, timeout=5)
        html = r.stdout
        if not html.strip():
            html = "<html><body><h1>No content</h1></body></html>"
        pdf_path = OUT / fname.replace('.png','.pdf')
        weasyprint.HTML(string=html).write_pdf(str(pdf_path), presentational_hints=True)
        png_base = str(OUT / fname.replace('.png',''))
        subprocess.run(["pdftoppm","-png","-r","150","-singlefile",str(pdf_path),png_base],
                      capture_output=True, timeout=10)
        pdf_path.unlink()
        print(f"  [OK] {fname} ({url})")
    except Exception as e:
        print(f"  [SKIP] {fname}: {e}")

def main():
    print("Version B: Generating real HTML→PNG screenshots...")

    # 1. Deploy status
    r = subprocess.run(["sudo","-S","docker","compose","ps"], input=b"691124\n", capture_output=True, timeout=15)
    lines = r.stdout.decode().split('\n')
    lines.append("")
    lines.append("=== 权重配置 ===")
    lines.append("  tomcat1 (HIGH):   172.29.0.11:8081  weight=3  (50%)")
    lines.append("  tomcat2 (MEDIUM): 172.29.0.12:8082  weight=2  (33%)")
    lines.append("  tomcat3 (LOW):    172.29.0.13:8083  weight=1  (17%)")
    term_png("docker compose ps — 部署状态 (版本B: 加权集群 3:2:1)", lines, "01-deploy-status.png")

    # 2-4. Web pages via weasyprint
    for port, name in [(8081,"tomcat1"),(8082,"tomcat2"),(8083,"tomcat3")]:
        web_png(f"http://localhost:{port}/", f"02-{name}.png")

    # 5. Nginx proxy
    web_png("http://localhost:80/", "02-nginx-proxy.png")

    # 6. Weighted RR 600
    subprocess.run(["sudo","-S","bash","nginx/switch-algorithm.sh","weighted-rr"], input=b"691124\n", capture_output=True, timeout=15)
    time.sleep(1)
    counts = {"tomcat1":0,"tomcat2":0,"tomcat3":0}
    for i in range(600):
        r = subprocess.run(["curl","-s","-I","http://localhost:80/"], capture_output=True, text=True, timeout=3)
        for ip,n in [("172.29.0.11","tomcat1"),("172.29.0.12","tomcat2"),("172.29.0.13","tomcat3")]:
            if ip in r.stdout: counts[n] += 1
    total = sum(counts.values())
    lines = ["┌──────────────────────────────────────────────────────────────┐",
             "│   加权轮询 (Weighted Round Robin, weight=3:2:1)             │",
             "│   600次请求分发统计   期望: 300(50%) : 200(33%) : 100(17%)   │",
             "├──────────┬────────┬──────────┬──────────┬──────────────────┤",
             "│  服务器   │  权重   │  期望     │  实际     │  偏差            │"]
    for n,w,exp in [("tomcat1",3,300),("tomcat2",2,200),("tomcat3",1,100)]:
        c = counts[n]; p = c*100/total if total else 0
        dev = (c-exp)/exp*100 if exp else 0
        lines.append(f"│ {n:8s} │  {w}     │  {exp:3d}(50%) │  {c:3d}({p:.1f}%)│  {dev:+.1f}%           │")
    lines.append(f"├──────────┴────────┼──────────┼──────────┼──────────────────┤")
    lines.append(f"│  总计              │  {total:4d}    │  100%    │                  │")
    lines.append("└───────────────────┴──────────┴──────────┴──────────────────┘")
    term_png("加权轮询 600次请求分发统计 (3:2:1)", lines, "03-weighted-rr-600.png")

    # 7. Weighted Least Conn
    subprocess.run(["sudo","-S","bash","nginx/switch-algorithm.sh","least-conn"], input=b"691124\n", capture_output=True, timeout=15)
    time.sleep(1)
    c2 = {"tomcat1":0,"tomcat2":0,"tomcat3":0}
    for i in range(600):
        r = subprocess.run(["curl","-s","-I","http://localhost:80/"], capture_output=True, text=True, timeout=3)
        for ip,n in [("172.29.0.11","tomcat1"),("172.29.0.12","tomcat2"),("172.29.0.13","tomcat3")]:
            if ip in r.stdout: c2[n] += 1
    t2 = sum(c2.values())
    lines2 = ["┌──────────────────────────────────────────────────────────────┐",
              "│  加权最少连接 (Weighted Least Connections, weight=3:2:1)    │",
              "│  600次请求分发统计                                           │",
              "├──────────┬────────┬──────────┬──────────┬──────────────────┤"]
    for n,w,exp in [("tomcat1",3,300),("tomcat2",2,200),("tomcat3",1,100)]:
        c = c2[n]; p = c*100/t2 if t2 else 0
        lines2.append(f"│ {n:8s} │  {w}     │  {exp:3d}(50%) │  {c:3d}({p:.1f}%)│   —              │")
    lines2.append(f"├──────────┴────────┼──────────┼──────────┼──────────────────┤")
    lines2.append(f"│  总计              │  {t2:4d}    │  100%    │                  │")
    lines2.append("└───────────────────┴──────────┴──────────┴──────────────────┘")
    term_png("加权最少连接 600次请求分发统计", lines2, "04-least-conn-600.png")

    # 8. IP Hash + backup
    subprocess.run(["sudo","-S","bash","nginx/switch-algorithm.sh","ip-hash"], input=b"691124\n", capture_output=True, timeout=15)
    time.sleep(1)
    first=""; c3={"tomcat1":0,"tomcat2":0,"tomcat3":0}
    for i in range(100):
        r = subprocess.run(["curl","-s","-I","http://localhost:80/"], capture_output=True, text=True, timeout=3)
        s="unknown"
        for ip,n in [("172.29.0.11","tomcat1"),("172.29.0.12","tomcat2"),("172.29.0.13","tomcat3")]:
            if ip in r.stdout: s=n; c3[n]+=1
        if not first: first=s
    stick = c3[first]
    term_png("IP哈希 + 备用服务器 会话保持测试", [
        "┌────────────────────────────────────────────────────┐",
        "│  IP哈希 (IP Hash) + backup  会话保持测试 (100次)  │",
        "├────────────────────────────────────────────────────┤",
        f"│  首次分配服务器:   {first:12s}                      │",
        f"│  会话保持次数:     {stick}/100 ({stick}%)                        │",
        f"│  服务器变更次数:   {100-stick}                                   │",
        f"│  backup(tomcat3):  {'未启用 (主节点正常)' if c3['tomcat3']==0 else '已接管!'}            │",
        "├────────────────────────────────────────────────────┤",
        "│  IP哈希保证同客户端始终访问同一节点                    │",
        "│  backup仅在所有主节点故障时才接管流量                  │",
        "└────────────────────────────────────────────────────┘"
    ], "05-ip-hash-session.png")

    # 9. Nginx status
    try:
        r = subprocess.run(["curl","-s","http://localhost:80/nginx_status"], capture_output=True, text=True, timeout=3)
        term_png("Nginx 状态页 (/nginx_status)", ["=== /nginx_status ==="]+r.stdout.split('\n'), "07-nginx-status.png")
    except: pass

    # 10. Algorithm switching
    term_png("算法切换流程演示", [
        "=== 三种负载均衡算法切换演示 ===","",
        ">>> Step 1: 加权轮询 (weighted-rr)",
        "    upstream tomcat_cluster {",
        "        server 172.29.0.11:8081 weight=3;  ← HIGH",
        "        server 172.29.0.12:8082 weight=2;  ← MEDIUM",
        "        server 172.29.0.13:8083 weight=1;  ← LOW",
        "    }","",
        ">>> Step 2: 加权最少连接 (least_conn)",
        "    upstream tomcat_cluster {",
        "        least_conn;",
        "        server 172.29.0.11:8081 weight=3;",
        "        server 172.29.0.12:8082 weight=2;",
        "        server 172.29.0.13:8083 weight=1;",
        "    }","",
        ">>> Step 3: IP哈希 + 备用服务器 (ip_hash + backup)",
        "    upstream tomcat_cluster {",
        "        ip_hash;",
        "        server 172.29.0.11:8081 weight=3;",
        "        server 172.29.0.12:8082 weight=2;",
        "        server 172.29.0.13:8083 weight=1 backup;  ← 冷备",
        "    }"
    ], "09-algorithm-switching.png")

    # 11. Nginx logs
    try:
        r = subprocess.run(["sudo","-S","docker","exec","nginx-lb","tail","-15","/var/log/nginx/loadbalance.log"],
                          input=b"691124\n", capture_output=True, timeout=5)
        term_png("Nginx 加权负载均衡日志", ["=== /var/log/nginx/loadbalance.log ==="]+r.stdout.decode().split('\n'), "08-nginx-logs.png")
    except: pass

    print(f"\nDone! {len(list(OUT.glob('*.png')))} screenshots in {OUT}/")

if __name__ == "__main__":
    main()
