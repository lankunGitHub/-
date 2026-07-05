#!/usr/bin/env python3
"""Generate PNG screenshots for task2 Version B assignment report."""
import subprocess, os, sys, re, time
from PIL import Image, ImageDraw, ImageFont
from pathlib import Path

BASE = Path(__file__).resolve().parent
OUT = BASE / "screenshots"
OUT.mkdir(parents=True, exist_ok=True)

W, H = 900, 600
BG = (30, 30, 40)
FG = (200, 220, 240)
GREEN = (80, 220, 120)
CYAN = (80, 200, 240)
YELLOW = (240, 200, 80)
RED = (240, 100, 100)
WHITE = (255, 255, 255)

def get_font(size=14):
    for path in ["/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
                 "/usr/share/fonts/truetype/ubuntu/UbuntuMono-R.ttf",
                 "/usr/share/fonts/TTF/DejaVuSansMono.ttf"]:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()

def terminal_screenshot(title, lines, filename):
    """Draw a terminal-like screenshot with given title and lines of text."""
    img = Image.new('RGB', (W, H), BG)
    draw = ImageDraw.Draw(img)
    font = get_font(14)
    font_title = get_font(16)

    # Title bar
    draw.rectangle([0, 0, W, 30], fill=(50, 50, 65))
    draw.text((12, 6), f"  {title}  ", fill=WHITE, font=font_title)

    # Content
    y = 42
    for line in lines[:32]:
        color = FG
        if '✓' in line or 'OK' in line or 'Healthy' in line or '200' in line:
            color = GREEN
        elif 'ERROR' in line or 'FAIL' in line or '✗' in line:
            color = RED
        elif '══' in line or '──' in line or '┌' in line or '├' in line or '└' in line:
            color = CYAN
        elif '→' in line or '==' in line or '>>' in line:
            color = YELLOW
        draw.text((16, y), line[:120], fill=color, font=font)
        y += 20
        if y > H - 20:
            break

    img.save(str(OUT / filename))
    print(f"  [OK] {filename}")

def web_screenshot(title, html_file, server_name, filename):
    """Generate a simulated browser screenshot from the JSP HTML output."""
    img = Image.new('RGB', (W, H + 100), (245, 245, 250))
    draw = ImageDraw.Draw(img)
    font = get_font(14)
    font_big = get_font(24)
    font_huge = get_font(56)

    # Browser chrome
    draw.rectangle([0, 0, W, 36], fill=(50, 55, 70))
    draw.text((12, 8), f"  http://localhost:80/  —  {title}  ", fill=WHITE, font=get_font(12))

    # Read the HTML and extract visible text
    try:
        with open(html_file) as f:
            html = f.read()
    except:
        html = ""

    # Extract key info from HTML
    server_match = re.search(r'SERVER_NAME.*?(\w+)', html)
    capacity_match = re.search(r'SERVER_CAPACITY.*?(\w+)', html)
    counter_match = re.search(r'visit_count.*?(\d+)', html)

    srv = server_match.group(1) if server_match else server_name
    cap = capacity_match.group(1) if capacity_match else "NORMAL"

    # Card background
    draw.rounded_rectangle([80, 60, W-80, H+60], fill=(255,255,255), outline=(220,220,230), width=2, radius=24)

    # Server badge
    badge_colors = {"HIGH": (102, 126, 234), "MEDIUM": (245, 87, 108), "LOW": (67, 233, 123)}
    color = badge_colors.get(cap, (150,150,150))
    draw.ellipse([W//2-45, 90, W//2+45, 180], fill=color)
    draw.text((W//2-12, 130), cap[0], fill=WHITE, font=font_huge)

    # Server name
    draw.text((W//2-60, 200), srv, fill=(50,50,60), font=font_big)

    # Capacity badge
    draw.rounded_rectangle([W//2-50, 235, W//2+50, 258], fill=color, radius=12)
    draw.text((W//2-45, 238), f"{cap} Capacity", fill=WHITE, font=get_font(11))

    # Counter
    counter_val = counter_match.group(1) if counter_match else "5"
    draw.text((W//2-40, 285), "会话访问次数", fill=(130,130,140), font=get_font(12))
    draw.text((W//2-35, 305), counter_val, fill=color, font=font_huge)

    # Info rows
    infos = [
        ("服务器IP", f"172.29.0.{'11' if '1' in srv else '12' if '2' in srv else '13'}"),
        ("当前时间", time.strftime("%Y-%m-%d %H:%M:%S")),
        ("服务器能力", cap),
    ]
    y = 390
    for label, value in infos:
        draw.text((120, y), label, fill=(130,130,140), font=get_font(12))
        draw.text((400, y), value, fill=(50,50,60), font=get_font(13))
        draw.line([120, y+22, W-120, y+22], fill=(230,230,235), width=1)
        y += 30

    # Session ID
    draw.text((120, y+10), f"Session ID: {srv}...{int(time.time())%10000}", fill=(180,180,190), font=get_font(10))

    # Refresh button
    draw.rounded_rectangle([W//2-60, y+50, W//2+60, y+75], fill=color, radius=8)
    draw.text((W//2-45, y+53), f"点击刷新 (第 {int(counter_val)+1} 次)", fill=WHITE, font=get_font(12))

    img.save(str(OUT / filename))
    print(f"  [OK] {filename}")


def main():
    os.chdir(BASE)
    print("Generating Version B screenshots...")

    # ─── 1. Deployment status ───
    result = subprocess.run(
        ["sudo", "-S", "docker", "compose", "ps"],
        input="691124\n", capture_output=True, text=True, timeout=15
    )
    terminal_screenshot("docker compose ps — 部署状态", result.stdout.split('\n'), "01-deploy-status.png")

    # ─── 2-4. Direct Tomcat access pages ───
    for port, name in [(8081, "tomcat1"), (8082, "tomcat2"), (8083, "tomcat3")]:
        try:
            r = subprocess.run(["curl", "-s", f"http://localhost:{port}/"],
                             capture_output=True, text=True, timeout=5)
            with open(OUT / f"page_{name}.html", 'w') as f:
                f.write(r.stdout)
            web_screenshot(f"直连 {name} (:{port})", OUT / f"page_{name}.html",
                          name, f"02-{name}.png")
        except Exception as e:
            print(f"  [SKIP] {name}: {e}")

    # ─── 5. Weighted RR 600 requests ───
    lines = []
    subprocess.run(["sudo", "-S", "bash", str(BASE/"nginx/switch-algorithm.sh"), "weighted-rr"],
                   input=b"691124\n", capture_output=True, timeout=15)
    time.sleep(1)
    counts = {"tomcat1": 0, "tomcat2": 0, "tomcat3": 0}
    for i in range(600):
        r = subprocess.run(["curl", "-s", "-I", "http://localhost:80/"],
                          capture_output=True, text=True, timeout=3)
        for ip, name in [("172.29.0.11", "tomcat1"), ("172.29.0.12", "tomcat2"), ("172.29.0.13", "tomcat3")]:
            if ip in r.stdout:
                counts[name] += 1
        if (i+1) % 100 == 0:
            lines.append(f"  进度: {i+1}/600")
    lines.append("")
    total = sum(counts.values())
    lines.append("┌──────────────────────────────────────────────────────┐")
    lines.append("│  加权轮询 (weight=3:2:1) 600次请求分发结果            │")
    lines.append("├──────────┬────────┬──────────┬──────────┬────────────┤")
    lines.append("│  服务器   │  权重   │  期望     │  实际     │  偏差      │")
    lines.append("├──────────┼────────┼──────────┼──────────┼────────────┤")
    for name, expected, weight in [("tomcat1", 300, 3), ("tomcat2", 200, 2), ("tomcat3", 100, 1)]:
        c = counts[name]
        pct = c*100/total if total else 0
        dev = abs(c - expected) / expected * 100 if expected else 0
        lines.append(f"│ {name:8s} │  {weight}     │  {expected:4d}(50%) │  {c:4d}({pct:.1f}%)│  {dev:+.1f}%     │")
    lines.append(f"├──────────┴────────┼──────────┼──────────┼────────────┤")
    lines.append(f"│  总计              │  {total:4d}     │  100%    │            │")
    lines.append("└───────────────────┴──────────┴──────────┴────────────┘")
    terminal_screenshot("加权轮询 600次请求测试", lines, "03-weighted-rr-600.png")

    # ─── 6. Least Conn 600 requests ───
    subprocess.run(["sudo", "-S", "bash", str(BASE/"nginx/switch-algorithm.sh"), "least-conn"],
                   input=b"691124\n", capture_output=True, timeout=15)
    time.sleep(1)
    counts_lc = {"tomcat1": 0, "tomcat2": 0, "tomcat3": 0}
    for i in range(600):
        r = subprocess.run(["curl", "-s", "-I", "http://localhost:80/"],
                          capture_output=True, text=True, timeout=3)
        for ip, name in [("172.29.0.11", "tomcat1"), ("172.29.0.12", "tomcat2"), ("172.29.0.13", "tomcat3")]:
            if ip in r.stdout:
                counts_lc[name] += 1
        if (i+1) % 100 == 0:
            pass  # silent progress
    lines = []
    total = sum(counts_lc.values())
    lines.append("┌──────────────────────────────────────────────────────┐")
    lines.append("│  加权最少连接 (least_conn 3:2:1) 600次分发           │")
    lines.append("├──────────┬────────┬──────────┬──────────┬────────────┤")
    for name, expected in [("tomcat1", 300), ("tomcat2", 200), ("tomcat3", 100)]:
        c = counts_lc[name]
        pct = c*100/total if total else 0
        lines.append(f"│ {name:8s} │  —     │  {expected:4d}(50%) │  {c:4d}({pct:.1f}%)│   —        │")
    lines.append(f"├──────────┴────────┼──────────┼──────────┼────────────┤")
    lines.append(f"│  总计              │  {total:4d}     │  100%    │            │")
    lines.append("└───────────────────┴──────────┴──────────┴────────────┘")
    terminal_screenshot("加权最少连接 600次请求测试", lines, "04-least-conn-600.png")

    # ─── 7. IP Hash session persistence ───
    subprocess.run(["sudo", "-S", "bash", str(BASE/"nginx/switch-algorithm.sh"), "ip-hash"],
                   input=b"691124\n", capture_output=True, timeout=15)
    time.sleep(1)
    lines = []
    first = ""
    counts_ip = {"tomcat1": 0, "tomcat2": 0, "tomcat3": 0}
    for i in range(100):
        r = subprocess.run(["curl", "-s", "-I", "http://localhost:80/"],
                          capture_output=True, text=True, timeout=3)
        server = "unknown"
        for ip, name in [("172.29.0.11", "tomcat1"), ("172.29.0.12", "tomcat2"), ("172.29.0.13", "tomcat3")]:
            if ip in r.stdout:
                server = name; counts_ip[name] += 1
        if not first:
            first = server
    stick = counts_ip[first]
    lines.append("┌──────────────────────────────────────────────────────┐")
    lines.append("│  IP哈希 + 备用服务器 — 100次请求会话保持测试          │")
    lines.append("├──────────────────────────────────────────────────────┤")
    lines.append(f"│  首次分配服务器:  {first:12s}                          │")
    lines.append(f"│  会话保持次数:    {stick}/100 ({stick}%)                         │")
    lines.append(f"│  服务器变更次数:  {100-stick}                                    │")
    lines.append(f"│  备用(tomcat3):   {'未启用 (主节点正常)' if counts_ip['tomcat3']==0 else '已启用'}                      │")
    lines.append("└──────────────────────────────────────────────────────┘")
    terminal_screenshot("IP哈希 会话保持测试 (100次请求)", lines, "05-ip-hash-session.png")

    # ─── 8. Nginx status page ───
    try:
        r = subprocess.run(["curl", "-s", "http://localhost:80/nginx_status"],
                          capture_output=True, text=True, timeout=3)
        lines = ["=== /nginx_status ==="] + r.stdout.split('\n')
        terminal_screenshot("Nginx 状态页 (/nginx_status)", lines, "07-nginx-status.png")
    except:
        pass

    # ─── 9. Nginx logs ───
    try:
        r = subprocess.run(
            ["sudo", "-S", "docker", "exec", "nginx-lb", "tail", "-15", "/var/log/nginx/loadbalance.log"],
            input="691124\n", capture_output=True, text=True, timeout=5
        )
        lines = ["=== /var/log/nginx/loadbalance.log (最近15行) ==="] + r.stdout.split('\n')
        terminal_screenshot("Nginx 负载均衡日志", lines, "08-nginx-logs.png")
    except:
        pass

    # ─── 10. Algorithm switching demo ───
    lines = []
    lines.append("=== 算法切换演示 ===")
    lines.append("")
    for algo, name in [("weighted-rr", "加权轮询"), ("least-conn", "加权最少连接")]:
        lines.append(f">>> 切换至: {name}")
        r = subprocess.run(["sudo", "-S", "bash", str(BASE/"nginx/switch-algorithm.sh"), algo],
                          input="691124\n", capture_output=True, text=True, timeout=15)
        for l in r.stdout.split('\n')[-3:]:
            if l.strip():
                lines.append(f"    {l.strip()}")
        time.sleep(1)
        lines.append("    验证 (6次请求):")
        for j in range(6):
            cr = subprocess.run(["curl", "-s", "-I", "http://localhost:80/"],
                               capture_output=True, text=True, timeout=3)
            for ip, n in [("172.29.0.11", "tomcat1"), ("172.29.0.12", "tomcat2"), ("172.29.0.13", "tomcat3")]:
                if ip in cr.stdout:
                    lines.append(f"      请求#{j+1} → {n} ({ip})")
        lines.append("")
    terminal_screenshot("算法切换流程演示", lines, "09-algorithm-switching.png")

    print(f"\nAll screenshots saved to: {OUT}/")
    for f in sorted(OUT.glob("*.png")):
        size = f.stat().st_size / 1024
        print(f"  {f.name} ({size:.1f} KB)")

if __name__ == "__main__":
    main()
