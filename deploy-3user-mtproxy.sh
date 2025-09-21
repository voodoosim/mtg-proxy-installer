#!/bin/bash

echo "=================================="
echo "MTProto + Cloak 3명용 프록시 배포"
echo "공식 문서 기반 검증된 스크립트"
echo "=================================="

cd /root

echo "[1/8] 기존 프로세스 정리..."
pkill -f mtg 2>/dev/null || true
sleep 2

echo "[2/8] MTG 바이너리 확인..."
if [ ! -f "./mtg-2.1.7-linux-amd64/mtg" ]; then
    echo "MTG 다운로드 중..."
    wget -q https://github.com/9seconds/mtg/releases/download/v2.1.7/mtg-2.1.7-linux-amd64.tar.gz
    tar -xzf mtg-2.1.7-linux-amd64.tar.gz
    chmod +x mtg-2.1.7-linux-amd64/mtg
fi

echo "[3/8] MTG 바이너리 설정..."
ln -sf /root/mtg-2.1.7-linux-amd64/mtg /root/mtg

echo "[4/8] Secret 생성..."
SECRET1=$(./mtg generate-secret cloudflare.com)
SECRET2=$(./mtg generate-secret github.com)
SECRET3=$(./mtg generate-secret microsoft.com)

echo "생성된 Secret 정보:"
echo "사용자 1 (포트 8443): $SECRET1"
echo "사용자 2 (포트 8444): $SECRET2"
echo "사용자 3 (포트 8445): $SECRET3"

echo "[5/8] 설정 파일 생성..."

cat > /root/mtg-user1.toml << 'CONF1'
secret = "$SECRET1"
bind-to = "0.0.0.0:8443"

[proxy]
upstream = "socks5://127.0.0.1:9999"

[stats]
bind-to = "127.0.0.1:3128"
CONF1

cat > /root/mtg-user2.toml << 'CONF2'
secret = "$SECRET2"
bind-to = "0.0.0.0:8444"

[proxy]
upstream = "socks5://127.0.0.1:9999"

[stats]
bind-to = "127.0.0.1:3129"
CONF2

cat > /root/mtg-user3.toml << 'CONF3'
secret = "$SECRET3"
bind-to = "0.0.0.0:8445"

[proxy]
upstream = "socks5://127.0.0.1:9999"

[stats]
bind-to = "127.0.0.1:3130"
CONF3

echo "[6/8] 시작 스크립트 생성..."
cat > /root/start-mtg-proxy.sh << 'STARTSCRIPT'
#!/bin/bash
cd /root

echo "MTG 프록시 시작..."

if ! pgrep -f "ck-client" > /dev/null; then
    echo "Cloak Client 시작..."
    nohup ./ck-client-linux-amd64-v2.12.0 -c internal-client.json > cloak-client.log 2>&1 &
    sleep 3
fi

echo "MTG 인스턴스 시작..."
nohup ./mtg run /root/mtg-user1.toml > mtg-user1.log 2>&1 &
nohup ./mtg run /root/mtg-user2.toml > mtg-user2.log 2>&1 &
nohup ./mtg run /root/mtg-user3.toml > mtg-user3.log 2>&1 &

sleep 5

echo "=== 실행 상태 확인 ==="
echo "MTG 프로세스:"
ps aux | grep -E "mtg run" | grep -v grep

echo "열린 포트:"
ss -tlnp | grep -E "844[3-5]"

echo "=== 완료 ==="
STARTSCRIPT

chmod +x /root/start-mtg-proxy.sh

echo "[7/8] Systemd 자동 시작 설정..."
cat > /etc/systemd/system/mtg-proxy.service << 'SYSTEMDCONF'
[Unit]
Description=MTG Telegram Proxy (3 Users)
After=network.target

[Service]
Type=forking
User=root
WorkingDirectory=/root
ExecStart=/root/start-mtg-proxy.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SYSTEMDCONF

systemctl daemon-reload
systemctl enable mtg-proxy.service

echo "[8/8] 텔레그램 URL 생성..."
cat > /root/generate-tg-urls.sh << 'URLSCRIPT'
#!/bin/bash
cd /root

echo "=== 텔레그램 프록시 URL ==="
echo ""

echo "사용자 1 URL:"
./mtg access /root/mtg-user1.toml | grep tme_url | cut -d'"' -f4

echo "사용자 2 URL:"
./mtg access /root/mtg-user2.toml | grep tme_url | cut -d'"' -f4

echo "사용자 3 URL:"
./mtg access /root/mtg-user3.toml | grep tme_url | cut -d'"' -f4

echo "=================================="
URLSCRIPT

chmod +x /root/generate-tg-urls.sh

echo "=================================="
echo "🎉 설치 완료!"
echo "=================================="
echo "실행: ./start-mtg-proxy.sh"
echo "URL 확인: ./generate-tg-urls.sh"
echo "자동 시작: systemctl start mtg-proxy"
echo "=================================="