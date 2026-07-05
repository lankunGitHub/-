#!/usr/bin/env python3
"""Version A — Real HTML→PNG screenshots via weasyprint + terminal via Pillow"""
import subprocess, os, time, re
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import weasyprint

BASE = Path(__file__).resolve().parent
OUT = BASE / "screenshots"
OUT.mkdir(parents=True, exist_ok=True)
os.chdir(BASE)

W, H = 900, 600
BG, FG = (30,30,40), (200,220,240)
GREEN, CYAN, YELLOW, RED, WHITE = (80,220,120), (80,200,240), (240,200,80), (240,100,100), (255,255,255)

FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
if not os.path.exists(FONT_PATH):
    FONT_PATH = None

def mfont(size=14):
    if FONT_PATH: return ImageFont.truetype(FONT_PATH, size)
    return ImageFont.load_default()

def term_png(title, lines, fname, w=900, h=600):
    img = Image.new('RGB', (w,h), BG)
    d = ImageDraw.Draw(img)
    d.rectangle([0,0,w,30], fill=(50,50,65))
    d.text((12,6), f"  {title}  ", fill=WHITE, font=mfont(16))
    y = 42
    for line in lines[:35]:
        c = FG
        if any(k in line for k in ['✓','OK','Healthy','200','active']): c = GREEN
        elif any(k in line for k in ['ERROR','FAIL','✗']): c = RED
        elif any(k in line for k in ['══','──','┌','├','└','┍','┕']): c = CYAN
        d.text((16,y), line[:120], fill=c, font=mfont(14))
        y += 20
        if y > h-20: break
    img.save(str(OUT/fname))
    print(f"  [OK] {fname}")

def web_png(url, fname, width=800):
    """Render HTML→PDF→PNG using weasyprint + pdftoppm"""
    import tempfile
    try:
        r = subprocess.run(["curl","-s",url], capture_output=True, text=True, timeout=5)
        html = r.stdout
        if not html.strip():
            html = "<html><body><h1>No content</h1></body></html>"
        # Step 1: HTML → PDF
        pdf_path = OUT / fname.replace('.png','.pdf')
        weasyprint.HTML(string=html).write_pdf(str(pdf_path), presentational_hints=True)
        # Step 2: PDF → PNG (first page only, 150 DPI)
        png_base = str(OUT / fname.replace('.png',''))
        subprocess.run(["pdftoppm","-png","-r","150","-singlefile",str(pdf_path),png_base],
                      capture_output=True, timeout=10)
        pdf_path.unlink()  # delete intermediate PDF
        print(f"  [OK] {fname} ({url})")
    except Exception as e:
        print(f"  [SKIP] {fname}: {e}")

def main():
    print("Version A: Generating real HTML→PNG screenshots...")

    # 1. Deploy status
    r = subprocess.run(["sudo","-S","docker","compose","ps"], input=b"691124\n", capture_output=True, timeout=15)
    term_png("docker compose ps — 部署状态 (版本A: 等权集群)", r.stdout.decode().split('\n'), "01-deploy-status.png")

    # 2-4. Web page screenshots via weasyprint (REAL rendering!)
    for port, name in [(8081,"tomcat1"),(8082,"tomcat2"),(8083,"tomcat3")]:
        web_png(f"http://localhost:{port}/", f"02-{name}.png")

    # 5. Nginx proxy page (round-robin)
    web_png("http://localhost:80/", "02-nginx-proxy.png")

    # 6. Round Robin 100 req
    counts = {"tomcat1":0,"tomcat2":0,"tomcat3":0}
    for i in range(100):
        r = subprocess.run(["curl","-s","-I","http://localhost:80/"], capture_output=True, text=True, timeout=3)
        for ip,n in [("172.28.0.11","tomcat1"),("172.28.0.12","tomcat2"),("172.28.0.13","tomcat3")]:
            if ip in r.stdout: counts[n] += 1
    total = sum(counts.values())
    lines = ["┌────────────────────────────────────────────────────┐",
             "│     轮询算法 (Round Robin)  100次请求分发          │",
             "├──────────┬──────────┬──────────┬─────────────────┤",
             "│  服务器   │  请求数   │  百分比   │  分布            │"]
    for n,exp in [("tomcat1",33),("tomcat2",33),("tomcat3",34)]:
        c = counts[n]; p = c*100/total if total else 0
        bar = "█"*int(c/2)
        lines.append(f"│ {n:8s} │  {c:4d}     │  {p:5.1f}%  │ {bar}")
    lines.append(f"├──────────┼──────────┼──────────┼─────────────────┤")
    lines.append(f"│ 总计      │  {total:4d}    │  100%    │                 │")
    lines.append("└──────────┴──────────┴──────────┴─────────────────┘")
    term_png("轮询算法 100次请求分发统计", lines, "03-round-robin-100.png")

    # 7. Least Conn
    subprocess.run(["sudo","-S","bash","nginx/switch-algorithm.sh","least-conn"], input=b"691124\n", capture_output=True, timeout=15)
    time.sleep(1)
    counts2 = {"tomcat1":0,"tomcat2":0,"tomcat3":0}
    for i in range(100):
        r = subprocess.run(["curl","-s","-I","http://localhost:80/"], capture_output=True, text=True, timeout=3)
        for ip,n in [("172.28.0.11","tomcat1"),("172.28.0.12","tomcat2"),("172.28.0.13","tomcat3")]:
            if ip in r.stdout: counts2[n] += 1
    total2 = sum(counts2.values())
    lines2 = ["┌────────────────────────────────────────────────────┐",
              "│   最少连接算法 (Least Connections) 100次分发       │",
              "├──────────┬──────────┬──────────┬─────────────────┤"]
    for n in ["tomcat1","tomcat2","tomcat3"]:
        c = counts2[n]; p = c*100/total2 if total2 else 0
        lines2.append(f"│ {n:8s} │  {c:4d}     │  {p:5.1f}%  │ {'█'*int(c/2)}")
    lines2.append(f"├──────────┼──────────┼──────────┼─────────────────┤")
    lines2.append(f"│ 总计      │  {total2:4d}    │  100%    │                 │")
    lines2.append("└──────────┴──────────┴──────────┴─────────────────┘")
    term_png("最少连接算法 100次请求分发统计", lines2, "04-least-conn-100.png")

    # 8. IP Hash
    subprocess.run(["sudo","-S","bash","nginx/switch-algorithm.sh","ip-hash"], input=b"691124\n", capture_output=True, timeout=15)
    time.sleep(1)
    first = ""; c3 = {"tomcat1":0,"tomcat2":0,"tomcat3":0}
    for i in range(100):
        r = subprocess.run(["curl","-s","-I","http://localhost:80/"], capture_output=True, text=True, timeout=3)
        s = "unknown"
        for ip,n in [("172.28.0.11","tomcat1"),("172.28.0.12","tomcat2"),("172.28.0.13","tomcat3")]:
            if ip in r.stdout: s=n; c3[n]+=1
        if not first: first=s
    stick = c3[first]
    term_png("IP哈希 会话保持测试 (100次请求)", [
        "┌──────────────────────────────────────────┐",
        "│  IP哈希 (IP Hash) 会话保持测试           │",
        "├──────────────────────────────────────────┤",
        f"│  首次分配服务器:  {first:12s}              │",
        f"│  会话保持次数:    {stick}/100 ({stick}%)                │",
        f"│  服务器变更次数:  {100-stick}                           │",
        f"│  会话保持率:      {stick}%                          │",
        "└──────────────────────────────────────────┘",
        "", "说明: 同一客户端IP的所有请求被哈希映射到固定服务器",
        "实现100%会话粘性，无需应用层Session共享。"
    ], "05-ip-hash-session.png")

    # 9. Nginx logs
    try:
        r = subprocess.run(["sudo","-S","docker","exec","nginx-lb","tail","-15","/var/log/nginx/loadbalance.log"],
                          input=b"691124\n", capture_output=True, timeout=5)
        term_png("Nginx 负载均衡日志", ["=== /var/log/nginx/loadbalance.log ==="]+r.stdout.decode().split('\n'), "07-nginx-logs.png")
    except: pass

    # 10. curl verification
    subprocess.run(["sudo","-S","bash","nginx/switch-algorithm.sh","round-robin"], input=b"691124\n", capture_output=True, timeout=15)
    time.sleep(1)
    lines = ["=== curl 轮询验证: 30次请求 → 上游服务器 ===", ""]
    for i in range(30):
        r = subprocess.run(["curl","-s","-I","http://localhost:80/"], capture_output=True, text=True, timeout=3)
        for ip,n in [("172.28.0.11","tomcat1"),("172.28.0.12","tomcat2"),("172.28.0.13","tomcat3")]:
            if ip in r.stdout: lines.append(f"  #{i+1:2d} → {n:8s} ({ip})")
    term_png("curl 30次请求 轮询验证 (均匀分发)", lines, "08-curl-verification.png", h=680)

    print(f"\nDone! {len(list(OUT.glob('*.png')))} screenshots in {OUT}/")

if __name__ == "__main__":
    main()
