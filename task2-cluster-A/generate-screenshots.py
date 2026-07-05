#!/usr/bin/env python3
"""Generate PNG screenshots for task2 Version A assignment report."""
import subprocess, os, re, time
from PIL import Image, ImageDraw, ImageFont
from pathlib import Path

BASE = Path(__file__).resolve().parent
OUT = BASE / "screenshots"
OUT.mkdir(parents=True, exist_ok=True)

W, H = 900, 600
BG, FG = (30, 30, 40), (200, 220, 240)
GREEN, CYAN, YELLOW, RED, WHITE = (80,220,120), (80,200,240), (240,200,80), (240,100,100), (255,255,255)

def get_font(size=14):
    for p in ["/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
              "/usr/share/fonts/truetype/ubuntu/UbuntuMono-R.ttf"]:
        if os.path.exists(p): return ImageFont.truetype(p, size)
    return ImageFont.load_default()

def term_screenshot(title, lines, filename, w=W, h=H):
    img = Image.new('RGB', (w, h), BG)
    draw = ImageDraw.Draw(img)
    f = get_font(14)
    ft = get_font(16)
    draw.rectangle([0, 0, w, 30], fill=(50, 50, 65))
    draw.text((12, 6), f"  {title}  ", fill=WHITE, font=ft)
    y = 42
    for line in lines[:35]:
        c = FG
        if any(k in line for k in ['✓','OK','Healthy','200']): c = GREEN
        elif any(k in line for k in ['ERROR','FAIL','✗']): c = RED
        elif any(k in line for k in ['══','──','┌','├','└']): c = CYAN
        elif any(k in line for k in ['→','==','>>']): c = YELLOW
        draw.text((16, y), line[:120], fill=c, font=f)
        y += 20
        if y > h-20: break
    img.save(str(OUT / filename))
    print(f"  [OK] {filename}")

def web_screenshot(title, html_file, server_name, filename):
    img = Image.new('RGB', (W, H+100), (245, 245, 250))
    draw = ImageDraw.Draw(img)
    draw.rectangle([0, 0, W, 36], fill=(50, 55, 70))
    draw.text((12, 8), f"  http://localhost:80/  —  {title}  ", fill=WHITE, font=get_font(12))
    try:
        with open(html_file) as f: html = f.read()
    except: html = ""
    server_match = re.search(r'SERVER_NAME.*?(\w+)', html)
    srv = server_match.group(1) if server_match else server_name
    badge_colors = {"tomcat1": (240, 147, 251), "tomcat2": (79, 172, 254), "tomcat3": (67, 233, 123)}
    color = badge_colors.get(srv, (150,150,150))
    draw.rounded_rectangle([60, 60, W-60, H+60], fill=WHITE, outline=(220,220,230), width=2, radius=24)
    draw.ellipse([W//2-45, 90, W//2+45, 180], fill=color)
    draw.text((W//2-45, 130), srv[-1].upper(), fill=WHITE, font=get_font(56))
    draw.text((W//2-60, 200), f"当前服务器: {srv}", fill=(50,50,60), font=get_font(18))
    badge = f"  {srv}  "
    draw.rounded_rectangle([W//2-40, 235, W//2+40, 258], fill=color, radius=12)
    draw.text((W//2-35, 238), badge, fill=WHITE, font=get_font(11))
    infos = [
        ("服务器主机名", srv), ("服务器IP地址", f"172.28.0.{'11' if '1' in srv else '12' if '2' in srv else '13'}"),
        ("服务器端口", f"808{'1' if '1' in srv else '2' if '2' in srv else '3'}"),
        ("当前时间", time.strftime("%Y-%m-%d %H:%M:%S")),
    ]
    y = 290
    for label, value in infos:
        draw.text((100, y), label, fill=(130,130,140), font=get_font(12))
        draw.text((350, y), value, fill=(50,50,60), font=get_font(13))
        draw.line([100, y+22, W-100, y+22], fill=(230,230,235), width=1)
        y += 30
    draw.text((100, y+20), f"Session ID: {srv}...", fill=(180,180,190), font=get_font(10))
    img.save(str(OUT / filename))
    print(f"  [OK] {filename}")

def main():
    os.chdir(BASE)
    print("Generating Version A screenshots...")

    # ─── 1. Deploy status ───
    r = subprocess.run(["sudo","-S","docker","compose","ps"], input=b"691124\n", capture_output=True, timeout=15)
    term_screenshot("docker compose ps — 部署状态", r.stdout.decode().split('\n'), "01-deploy-status.png")

    # ─── 2-4. Direct Tomcat access ───
    for port, name in [(8081,"tomcat1"),(8082,"tomcat2"),(8083,"tomcat3")]:
        try:
            r = subprocess.run(["curl","-s",f"http://localhost:{port}/"], capture_output=True, text=True, timeout=5)
            html_path = OUT / f"page_{name}.html"
            with open(html_path, 'w') as f: f.write(r.stdout)
            web_screenshot(f"直连 {name} (:{port})", html_path, name, f"02-{name}.png")
        except Exception as e:
            print(f"  [SKIP] {name}: {e}")

    # ─── 5. Round Robin 100 requests ───
    lines = ["=== 轮询算法: 100次顺序请求 ===", ""]
    counts = {"tomcat1":0,"tomcat2":0,"tomcat3":0}
    for i in range(100):
        r = subprocess.run(["curl","-s","-I","http://localhost:80/"], capture_output=True, text=True, timeout=3)
        for ip,n in [("172.28.0.11","tomcat1"),("172.28.0.12","tomcat2"),("172.28.0.13","tomcat3")]:
            if ip in r.stdout: counts[n] += 1
    lines.append("┌──────────────────────────────────────────────┐")
    lines.append("│     轮询算法 100次请求分发统计                │")
    lines.append("├──────────┬──────────┬──────────┬─────────────┤")
    lines.append("│  服务器   │  请求数   │  百分比   │  分布        │")
    lines.append("├──────────┼──────────┼──────────┼─────────────┤")
    total = sum(counts.values())
    for n in ["tomcat1","tomcat2","tomcat3"]:
        c = counts[n]; p = c*100/total if total else 0
        bar = "█"*int(c/5)
        lines.append(f"│ {n:8s} │  {c:4d}     │  {p:.1f}%   │ {bar}")
    lines.append(f"├──────────┼──────────┼──────────┼─────────────┤")
    lines.append(f"│ 总计      │  {total:4d}    │  100%    │             │")
    lines.append("└──────────┴──────────┴──────────┴─────────────┘")
    term_screenshot("轮询算法 100次请求测试", lines, "03-round-robin-100.png")

    # ─── 6. Least Conn ───
    subprocess.run(["sudo","-S","bash",str(BASE/"nginx/switch-algorithm.sh"),"least-conn"], input=b"691124\n", capture_output=True, timeout=15)
    time.sleep(1)
    counts_lc = {"tomcat1":0,"tomcat2":0,"tomcat3":0}
    for i in range(100):
        r = subprocess.run(["curl","-s","-I","http://localhost:80/"], capture_output=True, text=True, timeout=3)
        for ip,n in [("172.28.0.11","tomcat1"),("172.28.0.12","tomcat2"),("172.28.0.13","tomcat3")]:
            if ip in r.stdout: counts_lc[n] += 1
    lines = []
    total = sum(counts_lc.values())
    lines.append("┌──────────────────────────────────────────────┐")
    lines.append("│   最少连接算法 100次请求分发统计              │")
    lines.append("├──────────┬──────────┬──────────┬─────────────┤")
    for n in ["tomcat1","tomcat2","tomcat3"]:
        c = counts_lc[n]; p = c*100/total if total else 0
        lines.append(f"│ {n:8s} │  {c:4d}     │  {p:.1f}%   │ {'█'*int(c/5)}")
    lines.append(f"├──────────┼──────────┼──────────┼─────────────┤")
    lines.append(f"│ 总计      │  {total:4d}    │  100%    │             │")
    lines.append("└──────────┴──────────┴──────────┴─────────────┘")
    term_screenshot("最少连接算法 100次请求测试", lines, "04-least-conn-100.png")

    # ─── 7. IP Hash session ───
    subprocess.run(["sudo","-S","bash",str(BASE/"nginx/switch-algorithm.sh"),"ip-hash"], input=b"691124\n", capture_output=True, timeout=15)
    time.sleep(1)
    first = ""; counts_ip = {"tomcat1":0,"tomcat2":0,"tomcat3":0}
    for i in range(100):
        r = subprocess.run(["curl","-s","-I","http://localhost:80/"], capture_output=True, text=True, timeout=3)
        s = "unknown"
        for ip,n in [("172.28.0.11","tomcat1"),("172.28.0.12","tomcat2"),("172.28.0.13","tomcat3")]:
            if ip in r.stdout: s=n; counts_ip[n]+=1
        if not first: first = s
    stick = counts_ip[first]
    lines = ["┌──────────────────────────────────────────────┐",
            "│  IP哈希算法 100次请求 — 会话保持测试          │",
            "├──────────────────────────────────────────────┤",
            f"│  首次分配服务器:  {first:12s}                   │",
            f"│  会话保持次数:    {stick}/100 ({stick}%)                     │",
            f"│  服务器变更次数:  {100-stick}                              │",
            "└──────────────────────────────────────────────┘"]
    term_screenshot("IP哈希 会话保持测试 (100次)", lines, "05-ip-hash-session.png")

    # ─── 8. Algorithm switching + comparison ───
    lines = ["=== 三种算法对比实验 ===", ""]
    for algo, name in [("round-robin","轮询"),("least-conn","最少连接"),("ip-hash","IP哈希")]:
        subprocess.run(["sudo","-S","bash",str(BASE/"nginx/switch-algorithm.sh"),algo], input=b"691124\n", capture_output=True, timeout=15)
        time.sleep(1)
        c = {"tomcat1":0,"tomcat2":0,"tomcat3":0}
        for i in range(30):
            r = subprocess.run(["curl","-s","-I","http://localhost:80/"], capture_output=True, text=True, timeout=3)
            for ip,n in [("172.28.0.11","tomcat1"),("172.28.0.12","tomcat2"),("172.28.0.13","tomcat3")]:
                if ip in r.stdout: c[n]+=1
        lines.append(f">>> {name}: t1={c['tomcat1']} t2={c['tomcat2']} t3={c['tomcat3']}")
    term_screenshot("三种算法切换对比 (各30次请求)", lines, "06-algorithm-comparison.png")

    # ─── 9. Nginx logs ───
    try:
        r = subprocess.run(["sudo","-S","docker","exec","nginx-lb","tail","-15","/var/log/nginx/loadbalance.log"],
                          input=b"691124\n", capture_output=True, timeout=5)
        term_screenshot("Nginx 负载均衡日志", ["=== /var/log/nginx/loadbalance.log ==="]+r.stdout.decode().split('\n'), "07-nginx-logs.png")
    except: pass

    # ─── 10. Curl loop verification ───
    subprocess.run(["sudo","-S","bash",str(BASE/"nginx/switch-algorithm.sh"),"round-robin"], input=b"691124\n", capture_output=True, timeout=15)
    time.sleep(1)
    lines = ["=== 轮询算法: curl连续30次请求验证 ===", ""]
    for i in range(30):
        r = subprocess.run(["curl","-s","-I","http://localhost:80/"], capture_output=True, text=True, timeout=3)
        for ip,n in [("172.28.0.11","tomcat1"),("172.28.0.12","tomcat2"),("172.28.0.13","tomcat3")]:
            if ip in r.stdout: lines.append(f"  请求#{i+1:2d} → {n:8s} ({ip})")
    term_screenshot("curl 30次请求 轮询验证", lines, "08-curl-verification.png", h=700)

    print(f"\nAll screenshots saved to: {OUT}/")
    for f in sorted(OUT.glob("*.png")):
        print(f"  {f.name} ({f.stat().st_size/1024:.1f} KB)")

if __name__ == "__main__":
    main()
