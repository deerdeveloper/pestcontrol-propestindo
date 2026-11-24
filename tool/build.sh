#!/usr/bin/env bash
# Build lokal satu perintah (cermin dari .github/workflows/release.yml). Jalan di Linux dan macOS.
#
#   tool/build.sh                  # backend + android
#   tool/build.sh backend          # pilih sebagian: backend | android | all
#
# Konfigurasi lewat variabel lingkungan atau berkas ~/.propestindo/build.env (disarankan: di luar proyek)
# lalu tool/build.env (menimpa, tidak ikut git):
#   API_URL=https://laporan.domain.com     (wajib untuk android: alamat server bawaan di aplikasi)
#   VERSION=0.2.0                          (default: tag git terdekat, tanpa awalan v)
#   BUILD=10123                            (nomor build APK; HARUS lebih besar dari rilis yang sudah terpasang)
#   ANDROID_KEYSTORE_FILE=/path/release.jks ANDROID_KEYSTORE_PASSWORD=.. ANDROID_KEY_ALIAS=.. ANDROID_KEY_PASSWORD=..
#
# Hasil di dist/:
#   pestcontrol-api_vX.Y.Z_linux_arm64.tar.gz   server Orange Pi 4 Pro (pestcontrol-api + pestcontrol-seed, web tertanam)
#   pestcontrol-api_vX.Y.Z_linux_amd64.tar.gz   server Linux x86
#   propestindo-teknisi_vX.Y.Z_android.apk/.aab aplikasi teknisi
#   SHA256SUMS
# Proyek Flutter disalin ke .build/ sebelum diproses, jadi keystore dan hasil build tidak mengotori folder mobile/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# Konfigurasi: ~/.propestindo/build.env lalu tool/build.env (menimpa).
set -a
[ -f "$HOME/.propestindo/build.env" ] && . "$HOME/.propestindo/build.env"
[ -f tool/build.env ] && . tool/build.env
set +a

TARGETS=("$@")
[ ${#TARGETS[@]} -eq 0 ] && TARGETS=(all)
want() { local t; for t in "${TARGETS[@]}"; do [ "$t" = all ] || [ "$t" = "$1" ] && return 0; done; return 1; }

if [ -z "${VERSION:-}" ]; then
  VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
  [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || VERSION="0.0.0"
fi
if [ -z "${BUILD:-}" ]; then
  BUILD=$((10000 + $(git rev-list --count HEAD 2>/dev/null || echo 0)))
  echo "BUILD tidak diisi, memakai $BUILD (pastikan lebih besar dari versi yang sudah terpasang di HP)"
fi
TAG="v$VERSION"
DIST="$ROOT/dist"
mkdir -p "$DIST" "$ROOT/.build"
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# Repo sumber update yang ditanam di binary (bisa ditimpa UPDATE_REPO di server).
GITHUB_REPO="${GITHUB_REPO:-$(git remote get-url origin 2>/dev/null | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##' || true)}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Perintah '$1' tidak ditemukan: $2" >&2; exit 1; }; }
step() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }
sha256() { if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }

build_backend() {
  step "Web: build (ikut tertanam di binary server)"
  need npm "pasang Node.js 22"
  (cd web && npm ci && npm run build)
  local webui=backend/internal/webui/dist
  find "$webui" -mindepth 1 ! -name .gitkeep -delete
  cp -R web/dist/. "$webui/"

  step "Backend: test + build"
  need go "pasang Go (lihat backend/go.mod)"
  (cd backend && go vet ./... && go test ./...)
  local pkg=github.com/propestindo/pestcontrol/internal/buildinfo
  local ldflags="-s -w -X $pkg.Version=$TAG -X $pkg.Commit=$COMMIT -X $pkg.Date=$DATE -X $pkg.Repo=$GITHUB_REPO"
  local arch tmp
  for arch in arm64 amd64; do
    tmp="$ROOT/.build/server-$arch"
    rm -rf "$tmp" && mkdir -p "$tmp"
    CGO_ENABLED=0 GOOS=linux GOARCH=$arch go build -C backend -trimpath -ldflags "$ldflags" -o "$tmp/pestcontrol-api" ./cmd/api
    CGO_ENABLED=0 GOOS=linux GOARCH=$arch go build -C backend -trimpath -ldflags "$ldflags" -o "$tmp/pestcontrol-seed" ./cmd/seed
    tar -C "$tmp" -czf "$DIST/pestcontrol-api_${TAG}_linux_${arch}.tar.gz" pestcontrol-api pestcontrol-seed
  done
  find "$webui" -mindepth 1 ! -name .gitkeep -delete
  echo "Backend selesai -> $DIST"
}

build_android() {
  step "Android: APK + AAB"
  : "${API_URL:?Isi API_URL (mis. https://laporan.domain.com) di env atau tool/build.env}"
  need flutter "pasang Flutter"
  need java "pasang JDK 17"
  local dir="$ROOT/.build/mobile"
  rm -rf "$dir" && mkdir -p "$dir"
  # Awalan "/" supaya pengecualian hanya berlaku di akar mobile/.
  rsync -a --exclude /build --exclude /.dart_tool --exclude /android/key.properties --exclude '*.jks' mobile/ "$dir/"
  if [ -n "${ANDROID_KEYSTORE_FILE:-}" ]; then
    cp "$ANDROID_KEYSTORE_FILE" "$dir/android/app/release.jks"
    {
      echo "storeFile=release.jks"
      echo "storePassword=${ANDROID_KEYSTORE_PASSWORD:?isi ANDROID_KEYSTORE_PASSWORD}"
      echo "keyAlias=${ANDROID_KEY_ALIAS:?isi ANDROID_KEY_ALIAS}"
      echo "keyPassword=${ANDROID_KEY_PASSWORD:?isi ANDROID_KEY_PASSWORD}"
    } > "$dir/android/key.properties"
  else
    echo "PERINGATAN: ANDROID_KEYSTORE_FILE kosong, APK ditandatangani kunci debug (tidak untuk rilis/pembaruan)." >&2
  fi
  (
    cd "$dir"
    flutter pub get
    flutter build apk --release --build-name "$VERSION" --build-number "$BUILD" --dart-define=API_URL="$API_URL"
    flutter build appbundle --release --build-name "$VERSION" --build-number "$BUILD" --dart-define=API_URL="$API_URL"
  )
  # Hanya APK universal (tanpa --split-per-abi): dipakai fitur update dari dalam aplikasi.
  cp "$dir/build/app/outputs/flutter-apk/app-release.apk" "$DIST/propestindo-teknisi_${TAG}_android.apk"
  cp "$dir/build/app/outputs/bundle/release/app-release.aab" "$DIST/propestindo-teknisi_${TAG}_android.aab"
  echo "Android selesai -> $DIST"
}

want backend && build_backend
want android && build_android

step "Selesai"
ls -lh "$DIST"
(cd "$DIST" && sha256 propestindo-teknisi_* pestcontrol-api_* > SHA256SUMS 2>/dev/null || true)
