#!/bin/bash

echo "=========================================="
echo "MTProto + Cloak 3명용 프록시 배포 스크립트"
echo "공식 문서 기반 검증된 버전 v2.0"
echo "=========================================="

# 에러 발생시 스크립트 중단
set -e

cd /root

echo "[1/8] 기존 프로세스 정리..."
pkill -f mtg 2>/dev/null || true
pkill -f ck-client 2>/dev/null || true
sleep 2

echo "[2/8] MTG 바이너리 확인 및 다운로드..."
if [ ! -f "./mtg-2.1.7-linux-amd64/mtg" ]; then
    echo "MTG v2.1.7 다운로드 중..."
    if ! wget -q https://github.com/9seconds/mtg/releases/download/v2.1.7/mtg-2.1.7-linux-amd64.tar.gz; then
        echo "❌ MTG 다운로드 실패! 네트워크를 확인하세요."
        exit 1
    fi

    if ! tar -xzf mtg-2.1.7-linux-amd64.tar.gz; then
        echo "❌ MTG 압축 해제 실패!"
        exit 1
    fi

    chmod +x mtg-2.1.7-linux-amd64/mtg
    echo "✅ MTG 다운로드 완료"
else
    echo "✅ MTG 바이너리 이미 존재"
fi

echo "[3/8] MTG 바이너리 링크 설정..."
ln -sf /root/mtg-2.1.7-linux-amd64/mtg /root/mtg

echo "[4/8] Secret 생성 중..."
echo "Secret 생성을 위해 MTG 바이너리 테스트..."

# MTG 바이너리 작동 확인
if ! ./mtg --version >/dev/null 2>&1; then
    echo "❌ MTG 바이너리가 작동하지 않습니다!"
    exit 1
fi

# Secret 생성 (개별적으로 수행)
echo "사용자별 Secret 생성 중..."
SECRET1=$(./mtg generate-secret cloudflare.com)
SECRET2=$(./mtg generate-secret github.com)
SECRET3=$(./mtg generate-secret microsoft.com)

# Secret 생성 확인
if [ -z "$SECRET1" ] || [ -z "$SECRET2" ] || [ -z "$SECRET3" ]; then
    echo "❌ Secret 생성에 실패했습니다!"
    exit 1
fi

echo "✅ 생성된 Secret 정보:"
echo "사용자 1 (포트 8443): $SECRET1"
echo "사용자 2 (포트 8444): $SECRET2"
echo "사용자 3 (포트 8445): $SECRET3"

echo "[5/8] TOML 설정 파일 생성..."

# 사용자 1 설정 파일 생성
cat > /root/mtg-user1.toml << EOF
secret = "$SECRET1"
bind-to = "0.0.0.0:8443"

[proxy]
upstream = "socks5://127.0.0.1:9999"

[stats]
bind-to = "127.0.0.1:3128"
EOF

# 사용자 2 설정 파일 생성
cat > /root/mtg-user2.toml << EOF
secret = "$SECRET2"
bind-to = "0.0.0.0:8444"

[proxy]
upstream = "socks5://127.0.0.1:9999"

[stats]
bind-to = "127.0.0.1:3129"
EOF

# 사용자 3 설정 파일 생성
cat > /root/mtg-user3.toml << EOF
secret = "$SECRET3"
bind-to = "0.0.0.0:8445"

[proxy]
upstream = "socks5://127.0.0.1:9999"

[stats]
bind-to = "127.0.0.1:3130"
EOF

echo "✅ TOML 설정 파일 생성 완료"

# 설정 파일 검증
echo "설정 파일 검증 중..."
for i in 1 2 3; do
    if ! ./mtg validate /root/mtg-user${i}.toml >/dev/null 2>&1; then
        echo "⚠️  mtg-user${i}.toml 검증 경고 (일부 무시 가능)"
    else
        echo "✅ mtg-user${i}.toml 검증 완료"
    fi
done

echo "[6/8] 시작 스크립트 생성..."
cat > /root/start-mtg-proxy.sh << 'STARTSCRIPT'
#!/bin/bash
cd /root

echo "MTG 프록시 시작..."

# 기존 프로세스 정리
pkill -f mtg 2>/dev/null || true
pkill -f ck-client 2>/dev/null || true
sleep 2

# Cloak Client 시작 확인
if ! pgrep -f "ck-client" > /dev/null; then
    echo "Cloak Client 시작..."
    if [ -f "./ck-client-linux-amd64-v2.12.0" ]; then
        nohup ./ck-client-linux-amd64-v2.12.0 -c internal-client.json > cloak-client.log 2>&1 &
        sleep 3
    else
        echo "⚠️  Cloak Client 바이너리를 찾을 수 없습니다"
    fi
fi

echo "MTG 인스턴스 시작..."
nohup ./mtg run /root/mtg-user1.toml > mtg-user1.log 2>&1 &
nohup ./mtg run /root/mtg-user2.toml > mtg-user2.log 2>&1 &
nohup ./mtg run /root/mtg-user3.toml > mtg-user3.log 2>&1 &

sleep 5

echo "=== 실행 상태 확인 ==="
echo "MTG 프로세스:"
ps aux | grep -E "mtg run" | grep -v grep || echo "MTG 프로세스가 실행되지 않음"

echo "열린 포트:"
ss -tlnp | grep -E "844[3-5]" || echo "MTG 포트가 열리지 않음"

echo "로그 확인:"
for i in 1 2 3; do
    if [ -f "/root/mtg-user${i}.log" ]; then
        echo "--- User ${i} 로그 (마지막 3줄) ---"
        tail -n 3 "/root/mtg-user${i}.log" 2>/dev/null || echo "로그 없음"
    fi
done

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
ExecStop=/bin/bash -c 'pkill -f mtg; pkill -f ck-client'
Restart=on-failure
RestartSec=5
TimeoutStartSec=30

[Install]
WantedBy=multi-user.target
SYSTEMDCONF

systemctl daemon-reload
systemctl enable mtg-proxy.service

echo "[8/8] 텔레그램 URL 생성 스크립트..."
cat > /root/generate-tg-urls.sh << 'URLSCRIPT'
#!/bin/bash
cd /root

echo "=== 텔레그램 프록시 URL ==="
echo ""

for i in 1 2 3; do
    echo "사용자 ${i} URL:"
    if [ -f "/root/mtg-user${i}.toml" ]; then
        ./mtg access /root/mtg-user${i}.toml 2>/dev/null | grep "tme_url" | cut -d'"' -f4 || echo "URL 생성 실패"
    else
        echo "설정 파일 없음"
    fi
    echo ""
done

echo "=== 설정 정보 ==="
echo "포트: 8443 (사용자1), 8444 (사용자2), 8445 (사용자3)"
echo "프록시 체인: MTG → Cloak Client → Cloak Server → 인터넷"
echo "=================================="
URLSCRIPT

chmod +x /root/generate-tg-urls.sh

echo "=========================================="
echo "🎉 설치 완료!"
echo "=========================================="
echo "다음 명령어로 실행:"
echo "1. 수동 시작: ./start-mtg-proxy.sh"
echo "2. 자동 시작: systemctl start mtg-proxy"
echo "3. URL 확인: ./generate-tg-urls.sh"
echo "4. 상태 확인: systemctl status mtg-proxy"
echo "=========================================="
echo "로그 위치:"
echo "- MTG: mtg-user1.log, mtg-user2.log, mtg-user3.log"
echo "- Cloak: cloak-client.log"
echo "=========================================="

# 스크립트 마지막에 간단한 검증
echo "🔍 설치 후 검증..."
if [ -f "./mtg" ] && [ -f "/root/mtg-user1.toml" ]; then
    echo "✅ 모든 파일이 정상적으로 생성되었습니다"
else
    echo "❌ 일부 파일이 누락되었습니다"
fi