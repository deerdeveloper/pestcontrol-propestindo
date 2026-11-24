#!/usr/bin/env bash
# Build lokal lalu terbitkan ke GitHub Release (tanpa GitHub Actions, jadi tidak memakai kuota menit).
#
#   tool/publish.sh v0.2.0               # backend + android
#   tool/publish.sh v0.2.0 backend       # server saja
#   tool/publish.sh -y v0.2.0            # tanpa pertanyaan konfirmasi
#
# Syarat: gh (GitHub CLI) sudah login (gh auth login), BUILD terisi (env/tool/build.env) dan LEBIH BESAR dari rilis
# sebelumnya, commit sudah di-push. Konfigurasi build lain: lihat tool/build.sh.
# Tag harus baru: server dan aplikasi HP hanya memasang versi yang lebih baru dari yang sedang jalan.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
set -a
[ -f "$HOME/.propestindo/build.env" ] && . "$HOME/.propestindo/build.env"
[ -f tool/build.env ] && . tool/build.env
set +a

YES=0
if [ "${1:-}" = "-y" ]; then YES=1; shift; fi
TAG="${1:-}"
shift || true
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Pemakaian: tool/publish.sh [-y] vX.Y.Z [backend|android ...]" >&2; exit 1; }
TARGETS=("$@")
[ ${#TARGETS[@]} -eq 0 ] && TARGETS=(all)
has() { local t; for t in "${TARGETS[@]}"; do [ "$t" = all ] || [ "$t" = "$1" ] && return 0; done; return 1; }

command -v gh >/dev/null || { echo "Pasang GitHub CLI (https://cli.github.com), lalu gh auth login" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Belum login: jalankan gh auth login" >&2; exit 1; }
if has android; then
  : "${BUILD:?Isi BUILD (env atau tool/build.env), harus lebih besar dari nomor build rilis sebelumnya}"
fi

if gh release view "$TAG" >/dev/null 2>&1; then
  echo "Release $TAG sudah ada. Pakai tag baru." >&2
  exit 1
fi

TARGET_ARGS=()
if git rev-parse --git-dir >/dev/null 2>&1; then
  [ -z "$(git status --porcelain)" ] || echo "PERINGATAN: ada perubahan yang belum di-commit; build memakai berkas saat ini, release menunjuk commit terakhir." >&2
  if [ -z "$(git branch -r --contains HEAD 2>/dev/null)" ]; then
    echo "Commit terakhir belum di-push ke GitHub. Jalankan git push dulu." >&2
    exit 1
  fi
  TARGET_ARGS=(--target "$(git rev-parse HEAD)")
fi

export VERSION="${TAG#v}" BUILD
rm -rf dist
tool/build.sh "${TARGETS[@]}"

FILES=()
has android && FILES+=("dist/propestindo-teknisi_${TAG}_android.apk" "dist/propestindo-teknisi_${TAG}_android.aab")
has backend && FILES+=("dist/pestcontrol-api_${TAG}_linux_arm64.tar.gz" "dist/pestcontrol-api_${TAG}_linux_amd64.tar.gz")
for f in "${FILES[@]}"; do [ -s "$f" ] || { echo "Berkas hilang: $f" >&2; exit 1; }; done

# SHA256SUMS hanya untuk berkas yang diunggah (format sama dengan CI: "hash  nama"). Server menolak update tanpa ini.
sha256() { if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }
(cd dist && sha256 "${FILES[@]#dist/}" > SHA256SUMS)
FILES+=("dist/SHA256SUMS")

echo
echo "Akan diterbitkan sebagai $TAG (versi $VERSION, build ${BUILD:-}):"
printf '  %s\n' "${FILES[@]}"
if [ "$YES" != 1 ]; then
  read -r -p "Terbitkan sekarang? [y/N] " a
  [[ "$a" =~ ^[Yy]$ ]] || { echo "Dibatalkan. Berkas tetap ada di dist/."; exit 0; }
fi

gh release create "$TAG" "${FILES[@]}" ${TARGET_ARGS[@]+"${TARGET_ARGS[@]}"} --title "$TAG" --generate-notes --latest
echo "Terbit: $(gh release view "$TAG" --json url -q .url)"
