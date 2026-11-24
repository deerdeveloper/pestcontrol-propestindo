# Rilis, deploy Orange Pi, dan update otomatis

Semua file update disimpan di **GitHub Releases** repo ini. Server dan aplikasi HP mengunduh dari sana.

Polanya: `tool/build.sh` membangun semua file ke `dist/`, `tool/publish.sh` (lewat `make publish`) membangun
di komputer lalu menerbitkan GitHub Release tanpa memakai menit GitHub Actions, dan workflow **Release**
di GitHub Actions adalah cerminnya yang dijalankan manual.

Isi setiap rilis (contoh tag `v0.2.0`):

| File | Untuk |
| --- | --- |
| `pestcontrol-api_v0.2.0_linux_arm64.tar.gz` | Server Orange Pi 4 Pro: `pestcontrol-api` (API + web tertanam) dan `pestcontrol-seed` |
| `pestcontrol-api_v0.2.0_linux_amd64.tar.gz` | Sama, untuk server Linux x86 |
| `propestindo-teknisi_v0.2.0_android.apk` | Aplikasi teknisi (APK universal, dipakai update dari dalam aplikasi) |
| `propestindo-teknisi_v0.2.0_android.aab` | Untuk Play Store jika nanti diperlukan |
| `SHA256SUMS` | SHA-256 semua file. Server menolak update tanpa file ini |

Nama file dipakai oleh fitur update server dan aplikasi HP, jadi jangan diganti.

## 1. Persiapan sekali saja

**Di komputer build:** Go (versi di `backend/go.mod`), Node 22, Flutter stable + Android SDK, JDK 17,
`rsync`, dan GitHub CLI yang sudah login (`gh auth login`).

**Keystore Android.** Android hanya mau memasang update jika APK baru ditandatangani dengan key yang
sama dengan APK lama. Buat sekali, simpan baik-baik (hilang = teknisi harus uninstall dan pasang ulang):

```bash
keytool -genkey -v -keystore ~/.propestindo/release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias propestindo
```

**Konfigurasi build** di `~/.propestindo/build.env` (disarankan, di luar proyek) atau `tool/build.env`
(menimpa, tidak ikut git):

```
API_URL=https://laporan.propestindo.co.id    # wajib untuk android: alamat server bawaan di aplikasi
BUILD=10001                                  # nomor build APK, NAIKKAN setiap rilis
ANDROID_KEYSTORE_FILE=/home/kamu/.propestindo/release.jks
ANDROID_KEYSTORE_PASSWORD=...
ANDROID_KEY_ALIAS=propestindo
ANDROID_KEY_PASSWORD=...
# GITHUB_REPO=owner/repo                     # default diambil dari git remote origin
```

**Untuk rilis dari GitHub Actions**, isi di *Settings → Secrets and variables → Actions*:

- Secret `ANDROID_KEYSTORE_BASE64` (`base64 -w0 release.jks`), `ANDROID_KEYSTORE_PASSWORD`,
  `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`
- Variable `API_URL` (wajib). Variable `ALLOW_UNSIGNED_ANDROID=true` hanya jika sengaja rilis dengan debug key.

## 2. Membuat rilis

**Dari komputer lokal** (cara harian, tidak memakai kuota Actions):

```bash
git commit -am "..." && git push
make publish TAG=v0.2.0             # sama dengan: tool/publish.sh v0.2.0
tool/publish.sh v0.2.1 backend      # server saja
tool/publish.sh -y v0.2.2           # tanpa pertanyaan konfirmasi
```

`publish` mengecek `gh` sudah login, `BUILD` terisi, tag belum pernah dirilis, dan commit terakhir sudah
di-push (ada peringatan jika masih ada perubahan yang belum di-commit). Lalu `tool/build.sh` membangun
semuanya ke `dist/`, membuat `SHA256SUMS`, menampilkan daftar file, meminta konfirmasi, dan menjalankan
`gh release create` yang menunjuk ke commit terakhir (tag dibuat otomatis oleh GitHub).

Build tanpa menerbitkan: `make build` (semua), `make backend`, `make android`. Uji: `make test`,
`make web-test`, `make app-test`. Hapus hasil build: `make clean`.

Proyek Flutter disalin ke `.build/` sebelum dibangun, jadi keystore tidak pernah masuk folder `mobile/`.

**Dari GitHub Actions:** tab *Actions → Release → Run workflow*, isi tag (misalnya `v0.2.0`). Workflow
membuat draft release, membangun server dan APK secara paralel lalu mengunggahnya, membuat `SHA256SUMS`,
dan baru menerbitkan rilis setelah semua selesai. Nomor build APK = nomor run + 10000.

Format tag wajib `vMAJOR.MINOR.PATCH`.

## 3. Pasang di Orange Pi 4 Pro

Di Orange Pi (Ubuntu/Debian ARM64):

```bash
git clone https://github.com/OWNER/REPO.git && cd REPO/deploy/orangepi
sudo REPO=OWNER/REPO WITH_DEPS=1 ./install.sh          # tambah GITHUB_TOKEN=... jika repo private
```

Script ini memasang PostgreSQL + Chromium (untuk PDF), user `propestindo`, binary ke
`/opt/propestindo/bin/`, konfigurasi `/etc/propestindo/propestindo.env`, dan service systemd.
Setelah itu:

```bash
sudo -u postgres psql -c "CREATE USER pest PASSWORD 'rahasia'" -c "CREATE DATABASE pestcontrol OWNER pest"
sudo nano /etc/propestindo/propestindo.env        # sesuaikan DATABASE_URL
sudo systemctl restart propestindo
sudo -u propestindo env $(grep -v '^#' /etc/propestindo/propestindo.env | xargs) \
  pestcontrol-seed -email admin@propestindo.co.id -password 'GantiPassword'
```

Web dan API langsung jalan di port 8080 (web sudah tertanam di binary). Pasang reverse proxy
(Caddy/nginx) untuk HTTPS jika diakses dari internet.

## 4. Update server

- **Manual:** login sebagai super admin → menu **Sistem & update** → *Cek update* → *Update sekarang*.
  Halaman menampilkan progres unduhan, menunggu server restart, lalu memuat ulang.
- **Otomatis:** centang *Pasang versi baru secara otomatis* di halaman yang sama. Server mengecek GitHub
  setiap `UPDATE_INTERVAL` (default 1 jam) dan hanya memasang di jam `UPDATE_HOURS` (default 01-05 waktu server)
  supaya tidak mengganggu jam kerja.

Langkah update di server: unduh binary sesuai arsitektur → cocokkan SHA-256 dengan `SHA256SUMS` →
ambil binary dari tar.gz → jalankan `binary -version` untuk memastikan bisa jalan dan tagnya benar → binary lama disimpan sebagai
`pestcontrol-api.bak` → ganti → server berhenti dengan rapi dan menjalankan binary baru (PID sama).
Migrasi database baru berjalan otomatis saat start.

**Rollback manual:**

```bash
cd /opt/propestindo/bin && sudo -u propestindo mv pestcontrol-api.bak pestcontrol-api && sudo systemctl restart propestindo
```

Rollback tidak membatalkan migrasi database, jadi pastikan migrasi selalu kompatibel ke belakang.

Environment variable update:

| Variable | Default | Arti |
| --- | --- | --- |
| `UPDATE_REPO` | repo saat build | `owner/nama` sumber rilis. Kosong = fitur update mati |
| `UPDATE_GITHUB_TOKEN` | - | Token baca repo, wajib jika repo private |
| `UPDATE_AUTO` | `true` | Nilai awal update otomatis (setelah diubah di web, nilai dari web yang dipakai) |
| `UPDATE_INTERVAL` | `1h` | Jeda cek rilis |
| `UPDATE_HOURS` | `01-05` | Jam update otomatis boleh dipasang. `00-00` = kapan saja |

Server yang dijalankan lewat Docker tidak memakai fitur ini (binary di dalam container); update dengan
`docker compose up -d --build`.

## 5. Update aplikasi HP

Aplikasi teknisi bertanya ke server (`GET /api/app/android`) saat layar jadwal dibuka, dan lewat tombol
update di pojok kanan atas atau "Cek update" di layar login. Jika ada versi baru, muncul dialog dengan
catatan rilis; *Update sekarang* mengunduh APK, mengecek SHA-256, lalu membuka layar pemasangan Android.

- Repo public: HP mengunduh APK langsung dari GitHub.
- Repo private: server meneruskan APK dari GitHub (`/api/app/android/apk`) memakai `UPDATE_GITHUB_TOKEN`,
  jadi token tidak pernah ada di HP.
- Pertama kali, Android meminta izin *Pasang aplikasi tidak dikenal* untuk aplikasi ini.
- versionName APK diambil dari tag (`v1.2.3` → `1.2.3`), versionCode dari `BUILD` (lokal) atau nomor run + 10000 (Actions).
- Data laporan yang belum terkirim tetap tersimpan setelah update.

## CI

`.github/workflows/ci.yml` berjalan di setiap push ke `main` dan pull request yang mengubah kode
(`backend/`, `web/`, `mobile/`): `go vet`, `go test -race`, build ARM64, build web, `flutter analyze`,
dan `flutter test`. Perubahan dokumen saja tidak memicu CI. Dependabot mengecek update dependensi tiap minggu.
