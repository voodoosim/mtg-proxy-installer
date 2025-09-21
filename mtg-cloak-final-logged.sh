#!/bin/bash

echo "🚀 MTG + Cloak 3명용 프록시 한방 설치"
echo "====================================="

set -e
cd /root

# 기존 정리
echo "[LOG] 기존 프로세스 정리 중..."
pkill -f mtg 2>/dev/null || true
pkill -f ck-client 2>/dev/null || true
rm -f mtg-user*.toml mtg-user*.log cloak-client.log

# MTG 바이너리 준비
echo "[LOG] MTG 바이너리 확인 중..."
if [ ! -f "./mtg-2.1.7-linux-amd64/mtg" ]; then
    echo "[LOG] MTG 다운로드 중..."
    wget -q https://github.com/9seconds/mtg/releases/download/v2.1.7/mtg-2.1.7-linux-amd64.tar.gz
    tar -xzf mtg-2.1.7-linux-amd64.tar.gz
    chmod +x mtg-2.1.7-linux-amd64/mtg
    echo "[LOG] MTG 바이너리 다운로드 완료"
else
    echo "[LOG] MTG 바이너리 이미 존재"
fi
ln -sf /root/mtg-2.1.7-linux-amd64/mtg /root/mtg

# Cloak Client 바이너리 체크
echo "[LOG] Cloak Client 바이너리 확인 중..."
if [ ! -f "./ck-client-linux-amd64-v2.12.0" ]; then
    echo "[ERROR] Cloak Client 바이너리가 없습니다!"
    echo "        먼저 Cloak 바이너리를 다운로드하고 실행하세요."
    exit 1
fi
echo "[LOG] Cloak Client 바이너리 확인됨"

# internal-client.json 체크
echo "[LOG] Cloak 설정 파일 확인 중..."
if [ ! -f "./internal-client.json" ]; then
    echo "[ERROR] internal-client.json 파일이 없습니다!"
    echo "        먼저 Cloak 서버 설정을 완료하세요."
    exit 1
fi
echo "[LOG] Cloak 설정 파일 확인됨"

# Secret 생성
echo "[LOG] MTG 시크릿 생성 중..."
SECRET1=$(./mtg generate-secret cloudflare.com)
SECRET2=$(./mtg generate-secret github.com)
SECRET3=$(./mtg generate-secret microsoft.com)
echo "[LOG] 시크릿 생성 완료 (3개)"

# TOML 설정 파일 생성 (핵심: SOCKS5 upstream)
echo "[LOG] TOML 설정 파일 생성 중..."
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
echo "[LOG] TOML 설정 파일 3개 생성 완료"

# Cloak Client 먼저 시작 (핵심!)
echo "[LOG] 🌐 Cloak Client 시작 중..."
./ck-client-linux-amd64-v2.12.0 -c internal-client.json -l 9999 &
CLOAK_PID=$!
sleep 3

# Cloak 프로세스 확인
if ! kill -0 $CLOAK_PID 2>/dev/null; then
    echo "[ERROR] Cloak Client 시작 실패!"
    echo "        internal-client.json 설정을 확인하세요."
    exit 1
fi
echo "[LOG] ✅ Cloak Client 정상 시작 (PID: $CLOAK_PID)"

# SOCKS5 포트 확인
sleep 2
if ! netstat -ln | grep ":9999" > /dev/null; then
    echo "[ERROR] SOCKS5 포트 9999가 열리지 않았습니다!"
    echo "        Cloak Client 설정을 확인하세요."
    exit 1
fi
echo "[LOG] ✅ SOCKS5 포트 9999 정상 오픈"

# MTG 인스턴스 시작
echo "[LOG] 🚀 MTG 인스턴스 시작 중..."
./mtg run mtg-user1.toml &
MTG1_PID=$!
sleep 2
./mtg run mtg-user2.toml &
MTG2_PID=$!
sleep 2
./mtg run mtg-user3.toml &
MTG3_PID=$!
sleep 3

# MTG 프로세스 확인
for i in 1 2 3; do
    PID_VAR="MTG${i}_PID"
    PID_VALUE=$(eval echo \$$PID_VAR)
    PORT=$((8442 + i))

    if ! kill -0 $PID_VALUE 2>/dev/null; then
        echo "[ERROR] MTG User$i 시작 실패 (PID: $PID_VALUE)"
        echo "        mtg-user$i.toml 설정을 확인하세요."
    else
        echo "[LOG] ✅ MTG User$i 정상 시작 (PID: $PID_VALUE, Port: $PORT)"
    fi
done

# 포트 확인
echo "[LOG] 포트 바인딩 확인 중..."
for port in 8443 8444 8445; do
    if netstat -ln | grep ":$port" > /dev/null; then
        echo "[LOG] ✅ 포트 $port 정상 바인딩"
    else
        echo "[ERROR] 포트 $port 바인딩 실패!"
    fi
done

# 텔레그램 URL 생성
echo ""
echo "🎉 텔레그램 프록시 URL:"
echo "======================="
for i in 1 2 3; do
    echo "사용자 $i:"
    URL=$(./mtg access mtg-user$i.toml | grep tme_url | cut -d'"' -f4)
    if [ -n "$URL" ]; then
        echo "$URL"
        echo "[LOG] ✅ User$i URL 생성 성공"
    else
        echo "[ERROR] User$i URL 생성 실패"
    fi
    echo ""
done

# 자동 시작 스크립트 생성
echo "[LOG] 자동 시작 스크립트 생성 중..."
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
echo "[LOG] ✅ 자동 시작 스크립트 생성 완료"

# Systemd 서비스
echo "[LOG] Systemd 서비스 등록 중..."
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
echo "[LOG] ✅ Systemd 서비스 등록 완료"

echo ""
echo "✅ 모든 설치 완료!"
echo "재부팅시 자동 시작됩니다."
echo "관리 명령어: systemctl restart mtg-proxy"
echo ""
echo "[LOG] 최종 프로세스 상태:"
ps aux | grep -E "(mtg|ck-client)" | grep -v grep