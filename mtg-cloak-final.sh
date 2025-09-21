#!/bin/bash

echo "🚀 MTG + Cloak 3명용 프록시 한방 설치"
echo "====================================="

set -e
cd /root

# 기존 정리
pkill -f mtg 2>/dev/null || true
pkill -f ck-client 2>/dev/null || true
rm -f mtg-user*.toml mtg-user*.log cloak-client.log

# MTG 바이너리 준비
if [ ! -f "./mtg-2.1.7-linux-amd64/mtg" ]; then
    wget -q https://github.com/9seconds/mtg/releases/download/v2.1.7/mtg-2.1.7-linux-amd64.tar.gz
    tar -xzf mtg-2.1.7-linux-amd64.tar.gz
    chmod +x mtg-2.1.7-linux-amd64/mtg
fi
ln -sf /root/mtg-2.1.7-linux-amd64/mtg /root/mtg

# Secret 생성
SECRET1=$(./mtg generate-secret cloudflare.com)
SECRET2=$(./mtg generate-secret github.com)
SECRET3=$(./mtg generate-secret microsoft.com)

# TOML 설정 파일 생성 (핵심: SOCKS5 upstream)
cat > mtg-user1.toml << EOF
secret = "$SECRET1"
bind-to = "0.0.0.0:8443"

[network]
proxies = ["socks5://127.0.0.1:9999"]
EOF

cat > mtg-user2.toml << EOF
secret = "$SECRET2"
bind-to = "0.0.0.0:8444"

[network]
proxies = ["socks5://127.0.0.1:9999"]
EOF

cat > mtg-user3.toml << EOF
secret = "$SECRET3"
bind-to = "0.0.0.0:8445"

[network]
proxies = ["socks5://127.0.0.1:9999"]
EOF

# Cloak Client 먼저 시작 (핵심!)
echo "🌐 Cloak Client 시작..."
./ck-client-linux-amd64-v2.12.0 -c internal-client.json -l 9999 &
sleep 5

# MTG 인스턴스 시작
echo "🚀 MTG 인스턴스 시작..."
./mtg run mtg-user1.toml &
sleep 2
./mtg run mtg-user2.toml &
sleep 2
./mtg run mtg-user3.toml &
sleep 5

# 텔레그램 URL 생성
echo ""
echo "🎉 텔레그램 프록시 URL:"
echo "======================="
for i in 1 2 3; do
    echo "사용자 $i:"
    ./mtg access mtg-user$i.toml | grep tme_url | cut -d'"' -f4
    echo ""
done

# 자동 시작 스크립트 생성
cat > /root/start-proxy.sh << 'START'
#!/bin/bash
cd /root
pkill -f mtg 2>/dev/null || true
pkill -f ck-client 2>/dev/null || true
sleep 2
./ck-client-linux-amd64-v2.12.0 -c internal-client.json -l 9999 &
sleep 5
./mtg run mtg-user1.toml &
./mtg run mtg-user2.toml &
./mtg run mtg-user3.toml &
START

chmod +x /root/start-proxy.sh

# Systemd 서비스
cat > /etc/systemd/system/mtg-proxy.service << 'SYSTEMD'
[Unit]
Description=MTG Proxy Service
After=network.target

[Service]
Type=forking
User=root
WorkingDirectory=/root
ExecStart=/root/start-proxy.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SYSTEMD

systemctl daemon-reload
systemctl enable mtg-proxy

echo "✅ 완료! 재부팅시 자동 시작됩니다."
echo "관리: systemctl restart mtg-proxy"