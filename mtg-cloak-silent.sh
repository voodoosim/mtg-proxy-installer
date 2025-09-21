#!/bin/bash

echo "🚀 MTG + Cloak 3명용 프록시 설치 (Silent)"
echo "========================================"

cd /root

# 기존 프로세스 정리 (출력 숨김)
echo "[LOG] 기존 프로세스 정리 중..."
pkill -f mtg >/dev/null 2>&1 || true
pkill -f ck-client >/dev/null 2>&1 || true
rm -f mtg-user*.toml mtg-user*.log cloak-client.log >/dev/null 2>&1 || true
echo "[LOG] ✅ 기존 프로세스 정리 완료"

# 현재 디렉토리 확인
echo "[LOG] 현재 작업 디렉토리: $(pwd)"

# MTG 바이너리 준비
echo "[LOG] MTG 바이너리 확인 중..."
if [ ! -f "./mtg-2.1.7-linux-amd64/mtg" ]; then
    echo "[LOG] MTG 다운로드 중..."
    if wget -q https://github.com/9seconds/mtg/releases/download/v2.1.7/mtg-2.1.7-linux-amd64.tar.gz; then
        echo "[LOG] MTG 다운로드 성공"
        if tar -xzf mtg-2.1.7-linux-amd64.tar.gz; then
            echo "[LOG] MTG 압축 해제 성공"
            chmod +x mtg-2.1.7-linux-amd64/mtg
            echo "[LOG] MTG 실행 권한 설정 완료"
        else
            echo "[ERROR] MTG 압축 해제 실패"
            exit 1
        fi
    else
        echo "[ERROR] MTG 다운로드 실패"
        exit 1
    fi
else
    echo "[LOG] ✅ MTG 바이너리 이미 존재"
fi

# 심볼릭 링크 생성
if ln -sf /root/mtg-2.1.7-linux-amd64/mtg /root/mtg; then
    echo "[LOG] ✅ MTG 심볼릭 링크 생성 완료"
else
    echo "[ERROR] MTG 심볼릭 링크 생성 실패"
    exit 1
fi

# MTG 실행 테스트
echo "[LOG] MTG 실행 테스트 중..."
if ./mtg --version >/dev/null 2>&1; then
    echo "[LOG] ✅ MTG 실행 가능"
else
    echo "[ERROR] MTG 실행 불가"
    exit 1
fi

# Cloak Client 바이너리 확인
echo "[LOG] Cloak Client 바이너리 확인 중..."
if [ ! -f "./ck-client-linux-amd64-v2.12.0" ]; then
    echo "[ERROR] Cloak Client 바이너리가 없습니다!"
    echo "        다운로드 명령어:"
    echo "        wget https://github.com/cbeuw/Cloak/releases/download/v2.12.0/ck-client-linux-amd64-v2.12.0"
    echo "        chmod +x ck-client-linux-amd64-v2.12.0"
    exit 1
fi
echo "[LOG] ✅ Cloak Client 바이너리 확인됨"

# internal-client.json 확인
echo "[LOG] Cloak 설정 파일 확인 중..."
if [ ! -f "./internal-client.json" ]; then
    echo "[ERROR] internal-client.json 파일이 없습니다!"
    echo "        먼저 Cloak 서버 설정을 완료하고 클라이언트 설정 파일을 생성하세요."
    exit 1
fi
echo "[LOG] ✅ Cloak 설정 파일 확인됨"

# Secret 생성
echo "[LOG] MTG 시크릿 생성 중..."
if SECRET1=$(./mtg generate-secret cloudflare.com 2>/dev/null); then
    echo "[LOG] ✅ 시크릿 1 생성 성공"
else
    echo "[ERROR] 시크릿 1 생성 실패"
    exit 1
fi

if SECRET2=$(./mtg generate-secret github.com 2>/dev/null); then
    echo "[LOG] ✅ 시크릿 2 생성 성공"
else
    echo "[ERROR] 시크릿 2 생성 실패"
    exit 1
fi

if SECRET3=$(./mtg generate-secret microsoft.com 2>/dev/null); then
    echo "[LOG] ✅ 시크릿 3 생성 성공"
else
    echo "[ERROR] 시크릿 3 생성 실패"
    exit 1
fi

# TOML 설정 파일 생성
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

echo "[LOG] ✅ TOML 설정 파일 3개 생성 완료"

# Cloak Client 시작 (핵심!)
echo "[LOG] 🌐 Cloak Client 시작 중..."
./ck-client-linux-amd64-v2.12.0 -c internal-client.json -l 9999 >/dev/null 2>&1 &
CLOAK_PID=$!
sleep 3

# Cloak 프로세스 확인
if kill -0 $CLOAK_PID 2>/dev/null; then
    echo "[LOG] ✅ Cloak Client 정상 시작 (PID: $CLOAK_PID)"
else
    echo "[ERROR] Cloak Client 시작 실패!"
    echo "        internal-client.json 설정을 확인하세요."
    exit 1
fi

# SOCKS5 포트 확인
sleep 2
if netstat -ln | grep ":9999" >/dev/null; then
    echo "[LOG] ✅ SOCKS5 포트 9999 정상 오픈"
else
    echo "[ERROR] SOCKS5 포트 9999가 열리지 않았습니다!"
    echo "        Cloak Client 설정을 확인하세요."
    exit 1
fi

# MTG 인스턴스 시작
echo "[LOG] 🚀 MTG 인스턴스 시작 중..."
./mtg run mtg-user1.toml >/dev/null 2>&1 &
MTG1_PID=$!
sleep 2
./mtg run mtg-user2.toml >/dev/null 2>&1 &
MTG2_PID=$!
sleep 2
./mtg run mtg-user3.toml >/dev/null 2>&1 &
MTG3_PID=$!
sleep 3

# MTG 프로세스 확인
echo "[LOG] MTG 프로세스 상태 확인 중..."
for i in 1 2 3; do
    PID_VAR="MTG${i}_PID"
    PID_VALUE=$(eval echo \$$PID_VAR)
    PORT=$((8442 + i))

    if kill -0 $PID_VALUE 2>/dev/null; then
        echo "[LOG] ✅ MTG User$i 정상 시작 (PID: $PID_VALUE, Port: $PORT)"
    else
        echo "[ERROR] MTG User$i 시작 실패"
        exit 1
    fi
done

# 포트 바인딩 확인
echo "[LOG] 포트 바인딩 확인 중..."
for port in 8443 8444 8445; do
    if netstat -ln | grep ":$port" >/dev/null; then
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
    URL=$(./mtg access mtg-user$i.toml 2>/dev/null | grep tme_url | cut -d'"' -f4)
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
pkill -f mtg >/dev/null 2>&1 || true
pkill -f ck-client >/dev/null 2>&1 || true
sleep 2
./ck-client-linux-amd64-v2.12.0 -c internal-client.json -l 9999 >/dev/null 2>&1 &
sleep 5
./mtg run mtg-user1.toml >/dev/null 2>&1 &
./mtg run mtg-user2.toml >/dev/null 2>&1 &
./mtg run mtg-user3.toml >/dev/null 2>&1 &
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

systemctl daemon-reload >/dev/null 2>&1
systemctl enable mtg-proxy >/dev/null 2>&1
echo "[LOG] ✅ Systemd 서비스 등록 완료"

echo ""
echo "✅ 모든 설치 완료!"
echo "재부팅시 자동 시작됩니다."
echo "관리 명령어: systemctl restart mtg-proxy"
echo ""
echo "[LOG] 최종 프로세스 상태:"
ps aux | grep -E "(mtg|ck-client)" | grep -v grep