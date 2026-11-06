#!/usr/bin/env bash
# test_signs의 안내문을 OCR fixture용 이미지 한 폴더로 모은다.
#
#   tool/render_signs.sh [출력 폴더]        # 기본: build/test_signs
#
# - 슬라이드 묶음(test_signs/<묶음>/index.html, <section class="slide">가 있는 파일)은
#   `?slide=N`으로 한 장씩 열어 찍는다 → <묶음>-01.png, <묶음>-02.png …
#   (test_signs/slides.js가 N번째 장만 보이게 하고 번호·안내 글자를 지운다.)
# - 한 장짜리 HTML(test_signs/*.html)은 그대로 찍는다 → <파일 이름>.png
# - HTML이 없는 PNG(test_signs/sign1.png …)는 그대로 복사한다. HTML이 있는 PNG(sign-sk-band.png)는
#   HTML에서 새로 찍은 것을 쓴다.
# - 세로로 찍은 휴대폰 사진처럼 EXIF 회전이 든 JPEG도 만든다(tool/make_exif_photo.dart) → photo-*.jpg
#
# 찍기는 macOS의 Google Chrome headless로 한다. 창 크기 1600x1200, 배율 1.
# 운영자의 Chrome 프로필을 건드리지 않도록 매번 새 임시 프로필(--user-data-dir)을 쓴다.
# 다음 단계: tool/ocr_dump.sh 가 이 폴더의 이미지를 iOS 시뮬레이터 ML Kit로 읽어 fixture를 만든다.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/build/test_signs}"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
SIZE="${SIGN_WINDOW_SIZE:-1600,1200}"

# EXIF 회전 사진으로 만들 원본: "<이미지 이름> <EXIF Orientation 값>"
# 6 = 휴대폰을 세로로 들고 찍은 사진(센서 기준 가로 픽셀 + "시계 방향 90° 돌려 보기")
EXIF_PHOTOS=(
  "sign1 6"
  "variety-05 6"
  "variety-12 6"
  "variants-21 6"
  "variety-03 8"
  "variety-04 3"
  "sign4 6"
  "sign4 8"
  "variety-06 6"
  "variants-12 6"
)

if [[ ! -x "$CHROME" ]]; then
  echo "Google Chrome을 찾지 못했어요: $CHROME (CHROME=경로 로 지정)" >&2
  exit 1
fi

mkdir -p "$OUT"
PROFILE="$(mktemp -d "${TMPDIR:-/tmp}/render-signs-profile.XXXXXX")"
trap 'rm -rf "$PROFILE"' EXIT

shoot() { # shoot <url> <out.png>
  local url="$1" out="$2"
  rm -f "$out"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --no-first-run --no-default-browser-check --disable-extensions \
    --user-data-dir="$PROFILE" --window-size="$SIZE" --virtual-time-budget=2000 \
    --screenshot="$out" "$url" >/dev/null 2>&1 || true
  if [[ ! -s "$out" ]]; then
    echo "찍지 못했어요: $url" >&2
    exit 1
  fi
}

count=0

# 1) 슬라이드 묶음
for deck in "$ROOT"/test_signs/*/index.html; do
  [[ -f "$deck" ]] || continue
  name="$(basename "$(dirname "$deck")")"
  slides="$(grep -c '<section class="slide"' "$deck" || true)"
  for ((n = 1; n <= slides; n++)); do
    shoot "file://$deck?slide=$n" "$OUT/$(printf '%s-%02d.png' "$name" "$n")"
    count=$((count + 1))
  done
  echo "$name: ${slides}장"
done

# 2) 한 장짜리 HTML
for html in "$ROOT"/test_signs/*.html; do
  [[ -f "$html" ]] || continue
  name="$(basename "$html" .html)"
  shoot "file://$html" "$OUT/$name.png"
  count=$((count + 1))
  echo "$name: 1장"
done

# 3) HTML이 없는 PNG
for png in "$ROOT"/test_signs/*.png; do
  [[ -f "$png" ]] || continue
  name="$(basename "$png" .png)"
  [[ -f "$ROOT/test_signs/$name.html" ]] && continue
  cp "$png" "$OUT/$name.png"
  count=$((count + 1))
  echo "$name: 복사"
done

# 4) EXIF 회전 사진
for spec in "${EXIF_PHOTOS[@]}"; do
  read -r src orientation <<<"$spec"
  if [[ ! -f "$OUT/$src.png" ]]; then
    echo "EXIF 사진 원본이 없어요: $src.png" >&2
    exit 1
  fi
  (cd "$ROOT" && dart run tool/make_exif_photo.dart "$OUT/$src.png" "$OUT/photo-$src-exif$orientation.jpg" "$orientation")
  count=$((count + 1))
done

echo "이미지 ${count}개 → $OUT"
