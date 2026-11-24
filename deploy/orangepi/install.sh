#!/usr/bin/env bash
# Pasang atau perbarui Propestindo di Orange Pi 4 Pro (atau server Linux ARM64/AMD64 lain).
# Semua file diunduh dari GitHub Release.
#
#   sudo REPO=owner/nama ./install.sh                 # rilis terbaru
#   sudo REPO=owner/nama VERSION=v0.2.0 ./install.sh  # versi tertentu
#   sudo REPO=owner/nama WITH_DEPS=1 ./install.sh     # sekalian pasang PostgreSQL + Chromium
#
# Repo private: tambahkan GITHUB_TOKEN=ghp_xxx (token baca isi repo).
set -euo pipefail

REPO="${REPO:?isi REPO=owner/nama}"
VERSION="${VERSION:-latest}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
PREFIX=/opt/propestindo
DATA=/var/lib/propestindo
ETC=/etc/propestindo
SVC_USER=propestindo

[ "$(id -u)" = 0 ] || { echo "Jalankan dengan sudo"; exit 1; }
case "$(uname -m)" in
  aarch64|arm64) ARCH=arm64 ;;
  x86_64|amd64)  ARCH=amd64 ;;
  *) echo "Arsitektur $(uname -m) belum didukung"; exit 1 ;;
esac

if [ "${WITH_DEPS:-0}" = 1 ]; then
  apt-get update
  apt-get install -y --no-install-recommends postgresql chromium fonts-dejavu-core ca-certificates curl tzdata \
    || apt-get install -y --no-install-recommends postgresql chromium-browser fonts-dejavu-core ca-certificates curl tzdata
fi

auth=()
[ -n "$GITHUB_TOKEN" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
api="https://api.github.com/repos/$REPO/releases/$([ "$VERSION" = latest ] && echo latest || echo "tags/$VERSION")"
release_json="$(curl -fsSL "${auth[@]}" -H 'Accept: application/vnd.github+json' "$api")"

# Ambil URL API sebuah asset dari JSON rilis tanpa jq.
asset_url() {
  python3 -c '
import json, sys
rel = json.load(sys.stdin)
for a in rel["assets"]:
    if a["name"] == sys.argv[1]:
        print(a["url"]); break
else:
    sys.exit("asset %s tidak ada di rilis %s" % (sys.argv[1], rel["tag_name"]))
' "$1" <<<"$release_json"
}
download() { curl -fL --progress-bar "${auth[@]}" -H 'Accept: application/octet-stream' -o "$2" "$(asset_url "$1")"; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
tag="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])' <<<"$release_json")"
echo ">> Memasang $tag untuk linux/$ARCH dari $REPO"
pkg="pestcontrol-api_${tag}_linux_${ARCH}.tar.gz"
for f in "$pkg" SHA256SUMS; do download "$f" "$tmp/$f"; done
(cd "$tmp" && grep -E " \*?${pkg//./\\.}\$" SHA256SUMS | sha256sum -c -)
tar -C "$tmp" -xzf "$tmp/$pkg" pestcontrol-api pestcontrol-seed

id "$SVC_USER" >/dev/null 2>&1 || useradd --system --home "$DATA" --shell /usr/sbin/nologin "$SVC_USER"
install -d -o "$SVC_USER" -g "$SVC_USER" "$PREFIX" "$PREFIX/bin" "$DATA" "$DATA/storage"
install -d -m 750 "$ETC"
install -m 755 -o "$SVC_USER" -g "$SVC_USER" "$tmp/pestcontrol-api" "$PREFIX/bin/pestcontrol-api"
install -m 755 "$tmp/pestcontrol-seed" /usr/local/bin/pestcontrol-seed

if [ ! -f "$ETC/propestindo.env" ]; then
  chrome="$(command -v chromium || command -v chromium-browser || echo /usr/bin/chromium)"
  cat > "$ETC/propestindo.env" <<ENV
APP_ADDR=:8080
DATABASE_URL=postgres://pest:GANTI_PASSWORD@localhost:5432/pestcontrol?sslmode=disable
JWT_SECRET=$(head -c 32 /dev/urandom | base64 | tr -d '/+=')
STORAGE_DIR=$DATA/storage
CHROME_PATH=$chrome
CORS_ORIGINS=*
TZ=Asia/Jakarta

# Update dari GitHub Release
UPDATE_REPO=$REPO
UPDATE_GITHUB_TOKEN=$GITHUB_TOKEN
# Nilai awal update otomatis (bisa diubah super admin di menu Sistem)
UPDATE_AUTO=true
# Jam update otomatis boleh dipasang (waktu server)
UPDATE_HOURS=01-05
UPDATE_INTERVAL=1h
ENV
  chmod 640 "$ETC/propestindo.env"
  chgrp "$SVC_USER" "$ETC/propestindo.env"
  echo ">> Buat $ETC/propestindo.env, periksa DATABASE_URL sebelum menjalankan service."
fi

install -m 644 "$(dirname "$0")/propestindo.service" /etc/systemd/system/propestindo.service 2>/dev/null \
  || curl -fsSL "${auth[@]}" -H 'Accept: application/vnd.github.raw' \
       "https://api.github.com/repos/$REPO/contents/deploy/orangepi/propestindo.service?ref=$tag" \
       -o /etc/systemd/system/propestindo.service
systemctl daemon-reload
systemctl enable propestindo >/dev/null
systemctl restart propestindo
echo ">> Selesai. Cek status: systemctl status propestindo   log: journalctl -u propestindo -f"
