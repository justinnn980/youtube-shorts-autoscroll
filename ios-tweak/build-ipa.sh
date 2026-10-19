#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# 아이폰 순정 YouTube.ipa에 '쇼츠 자동 넘김' 모듈(YouTubeAutoShorts.dylib) 주입 스크립트
# 완료된 IPA는 AltStore / SideStore / Sideloadly 등으로 순정 아이폰에 바로 설치 가능합니다.
# ==============================================================================

INPUT_IPA="${1:-YouTube.ipa}"
OUTPUT_IPA="${2:-YouTube-AutoShorts.ipa}"

echo "[1/3] Theos로 YouTubeAutoShorts.dylib 빌드 중..."
make clean && make package FINALPACKAGE=1

DYLIB_PATH=".theos/obj/YouTubeAutoShorts.dylib"
if [ ! -f "$DYLIB_PATH" ]; then
    echo "오류: 빌드된 dylib을 찾을 수 없습니다 ($DYLIB_PATH)"
    exit 1
fi

if [ ! -f "$INPUT_IPA" ]; then
    echo "안내: 빌드된 트윅($DYLIB_PATH)이 준비되었습니다."
    echo "순정 YouTube.ipa 파일 경로를 인자로 전달하면 주입된 IPA가 생성됩니다:"
    echo "  ./build-ipa.sh /path/to/YouTube.ipa YouTube-AutoShorts.ipa"
    exit 0
fi

echo "[2/3] cyan (또는 insert_dylib)으로 순정 YouTube.ipa에 모듈 주입 중..."
if command -v cyan >/dev/null 2>&1; then
    cyan -i "$INPUT_IPA" -o "$OUTPUT_IPA" -f "$DYLIB_PATH"
    echo "[3/3] 완료! 생성된 파일: $OUTPUT_IPA"
else
    echo "cyan 도구가 설치되어 있지 않습니다. 'pip3 install pyzule-rw' 설치 후 다시 실행해 주세요."
    exit 1
fi

