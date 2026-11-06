#!/usr/bin/env bash
# 안내문 이미지를 iOS 시뮬레이터의 ML Kit(앱과 같은 한국어 인식기)로 읽어 원문 OCR fixture를 만든다.
#
#   tool/render_signs.sh                 # 먼저 이미지를 build/test_signs에 모은다
#   tool/ocr_dump.sh [이미지 폴더] [fixture 폴더]
#                                        # 기본: build/test_signs → test/fixtures/ocr
#   OCR_DUMP_ONLY=variety-01,variants-03 tool/ocr_dump.sh   # 몇 장만 다시 뽑기
#   OCR_SIM_UDID=<udid> tool/ocr_dump.sh                     # 다른 시뮬레이터 (기본: iPhone 16)
#
# 하는 일
# 1. 시뮬레이터가 꺼져 있으면 부팅한다(Simulator 앱 창은 띄우지 않는다). 스크립트가 켰으면 끝나고 끈다.
# 2. integration_test/ocr_dump_test.dart를 시뮬레이터에서 돌린다. 앱의 OcrService가 이미지마다
#    `text`(ML Kit 원문)·`layoutText`(행 재구성)·줄 좌표를 <fixture 폴더>/<이미지 이름>.json으로 쓴다.
# 3. 이미지 수만큼 fixture가 새로 쓰였는지 확인한다.
#
# 앱 코드(lib/)와 릴리스 빌드에는 아무것도 더하지 않는다. 인식한 글자는 fixture 파일에만 남고
# 이 스크립트의 출력에는 이미지 이름과 줄 수만 나온다. 이미지는 지어낸 안내문만 쓴다.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IN="$(cd "${1:-$ROOT/build/test_signs}" && pwd)"
OUT="${2:-$ROOT/test/fixtures/ocr}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
UDID="${OCR_SIM_UDID:-6186BDC9-5BD3-4873-947E-596A9818DD81}"
ONLY="${OCR_DUMP_ONLY:-}"

state="$(xcrun simctl list devices | grep "$UDID" | sed -E 's/.*\((Booted|Shutdown|[A-Za-z ]+)\).*/\1/' || true)"
if [[ -z "$state" ]]; then
  echo "시뮬레이터를 찾지 못했어요: $UDID" >&2
  exit 1
fi
booted_here=0
if [[ "$state" != "Booted" ]]; then
  echo "시뮬레이터 부팅: $UDID"
  xcrun simctl boot "$UDID"
  booted_here=1
fi
cleanup() {
  if [[ $booted_here == 1 ]]; then
    xcrun simctl shutdown "$UDID" || true
  fi
}
trap cleanup EXIT
xcrun simctl bootstatus "$UDID" -b >/dev/null

stamp="$(mktemp "${TMPDIR:-/tmp}/ocr-dump-stamp.XXXXXX")"
trap 'rm -f "$stamp"; cleanup' EXIT

cd "$ROOT"
flutter test integration_test/ocr_dump_test.dart -d "$UDID" \
  --dart-define=OCR_DUMP_IN="$IN" \
  --dart-define=OCR_DUMP_OUT="$OUT" \
  --dart-define=OCR_DUMP_ONLY="$ONLY"

expected=0
written=0
for f in "$IN"/*; do
  [[ "$f" =~ \.(png|jpg|jpeg|PNG|JPG|JPEG)$ ]] || continue
  name="$(basename "$f")"
  name="${name%.*}"
  if [[ -n "$ONLY" && ",$ONLY," != *",$name,"* ]]; then
    continue
  fi
  expected=$((expected + 1))
  if [[ "$OUT/$name.json" -nt "$stamp" ]]; then
    written=$((written + 1))
  else
    echo "fixture가 새로 쓰이지 않았어요: $name" >&2
  fi
done
echo "fixture ${written}/${expected}개 → $OUT"
[[ $written == "$expected" ]]
