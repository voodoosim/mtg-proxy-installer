#!/bin/bash

echo "🚀 MTG + Cloak 3명용 프록시 안전 설치"
echo "====================================="

cd /root

# 기존 정리 (에러 무시)
echo "[LOG] 기존 프로세스 정리 중..."
pkill -f mtg 2>/dev/null || echo "[LOG] MTG 프로세스 없음"
pkill -f ck-client 2>/dev/null || echo "[LOG] Cloak 프로세스 없음"
rm -f mtg-user*.toml mtg-user*.log cloak-client.log 2>/dev/null || echo "[LOG] 기존 파일 없음"

# 현재 디렉토리 확인
echo "[LOG] 현재 작업 디렉토리: $(pwd)"
echo "[LOG] 디렉토리 내용:"
ls -la

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
    echo "[LOG] MTG 바이너리 이미 존재"
fi

# 심볼릭 링크 생성
if ln -sf /root/mtg-2.1.7-linux-amd64/mtg /root/mtg; then
    echo "[LOG] MTG 심볼릭 링크 생성 완료"
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
    echo "        파일: ./ck-client-linux-amd64-v2.12.0"
    echo "        먼저 Cloak 바이너리를 다운로드하세요:"
    echo "        wget https://github.com/cbeuw/Cloak/releases/download/v2.12.0/ck-client-linux-amd64-v2.12.0"
    echo "        chmod +x ck-client-linux-amd64-v2.12.0"
    exit 1
fi
echo "[LOG] ✅ Cloak Client 바이너리 확인됨"

# internal-client.json 확인
echo "[LOG] Cloak 설정 파일 확인 중..."
if [ ! -f "./internal-client.json" ]; then
    echo "[ERROR] internal-client.json 파일이 없습니다!"
    echo "        먼저 Cloak 서버 설정을 완료하고 클라이언트 설정 파일을 다운로드하세요."
    exit 1
fi
echo "[LOG] ✅ Cloak 설정 파일 확인됨"

# Secret 생성
echo "[LOG] MTG 시크릿 생성 중..."
if SECRET1=$(./mtg generate-secret cloudflare.com 2>/dev/null); then
    echo "[LOG] 시크릿 1 생성 성공"
else
    echo "[ERROR] 시크릿 1 생성 실패"
    exit 1
fi

if SECRET2=$(./mtg generate-secret github.com 2>/dev/null); then
    echo "[LOG] 시크릿 2 생성 성공"
else
    echo "[ERROR] 시크릿 2 생성 실패"
    exit 1
fi

if SECRET3=$(./mtg generate-secret microsoft.com 2>/dev/null); then
    echo "[LOG] 시크릿 3 생성 성공"
else
    echo "[ERROR] 시크릿 3 생성 실패"
    exit 1
fi
echo "[LOG] ✅ 모든 시크릿 생성 완료"

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

# 설정 파일 검증
echo "[LOG] TOML 설정 파일 검증 중..."
for i in 1 2 3; do
    if [ -f "mtg-user$i.toml" ]; then
        echo "[LOG] ✅ mtg-user$i.toml 생성됨"
    else
        echo "[ERROR] mtg-user$i.toml 생성 실패"
        exit 1
    fi
done

echo ""
echo "✅ 사전 준비 완료!"
echo "이제 Cloak Client를 시작하고 MTG를 실행할 준비가 되었습니다."
echo ""
echo "다음 단계:"
echo "1. Cloak Client 시작: ./ck-client-linux-amd64-v2.12.0 -c internal-client.json -l 9999 &"
echo "2. MTG 시작: ./mtg run mtg-user1.toml &"
echo "3. URL 생성: ./mtg access mtg-user1.toml"