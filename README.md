# Sistem Laporan Kunjungan Pest Control — Propestindo

Sistem digital pengganti form Excel "Laporan Kunjungan General Pest Control".
Teknisi mengisi laporan di aplikasi HP (bisa offline), admin mereview dan menerbitkan,
sistem membuat PDF dua bahasa, dan pelanggan melihat laporannya di portal.

| Folder | Isi | Teknologi |
| --- | --- | --- |
| `backend/` | REST API, migrasi database, generator PDF | Go 1.26, chi, pgx, PostgreSQL 16, Chromium headless |
| `web/` | Web admin + portal pelanggan (satu aplikasi, menu per peran) | Vue 3, Vite, Pinia, vite-plugin-pwa |
| `mobile/` | Aplikasi teknisi | Flutter, sqflite (offline), mobile_scanner, signature |

Dokumen desain: lihat dokumen "Desain Sistem Laporan Kunjungan Pest Control (Propestindo)".

## Status: MVP fase 1

Sudah ada:

- Login dan 5 peran: super admin, admin, supervisor, teknisi, pelanggan.
- Data master: pelanggan, lokasi (area bawaan otomatis per jenis bangunan), area, kontak PIC,
  stasiun monitoring + kode QR, jenis hama, metode, bahan kimia, dosis standar, jenis alat.
  Isi awal diambil dari template Excel dengan ejaan yang sudah dirapikan.
- Jadwal kunjungan dan penugasan teknisi.
- Aplikasi teknisi: jadwal, check-in dengan GPS, temuan + foto, tindakan (dosis terisi otomatis),
  rekomendasi, cek stasiun lewat scan QR, tanda tangan teknisi dan PIC, kirim laporan.
  Semua tersimpan di HP dulu dan terkirim otomatis saat ada sinyal.
- Review oleh admin: kembalikan untuk revisi, atau terbitkan. Saat terbit, sistem memberi nomor
  `PPI/LKP/YYYY/MM/NNNN` dan membuat PDF dua bahasa bergaya contoh laporan PPC.
- Portal pelanggan: jadwal berikutnya, daftar laporan + unduh PDF, rekomendasi yang bisa
  ditandai "sudah dikerjakan".

Belum (fase 2): kontrak dengan jadwal otomatis, kirim email, notifikasi push, dashboard tren,
permintaan kunjungan darurat dari portal, ekspor Excel, penyimpanan file di S3.

## Menjalankan dengan Docker

```bash
docker compose up -d --build
docker compose exec api seed -demo     # akun dan data contoh
```

- Web: http://localhost:8081
- API: http://localhost:8080

Akun dari `seed -demo`:

| Peran | Email | Password |
| --- | --- | --- |
| Super admin | admin@propestindo.local | admin12345 |
| Admin | admin.ops@propestindo.local | admin12345 |
| Teknisi | teknisi@propestindo.local | teknisi123 |
| Pelanggan | pic@gunasejahtera.local | pelanggan123 |

Ganti semua password dan `JWT_SECRET` sebelum dipakai sungguhan.

## Menjalankan untuk development

**Backend** (butuh PostgreSQL dan Chromium):

```bash
cd backend
export DATABASE_URL=postgres://pest:pest@localhost:5432/pestcontrol?sslmode=disable
export CHROME_PATH=/usr/bin/chromium     # untuk PDF
go run ./cmd/seed -demo                  # migrasi + data contoh
go run ./cmd/api                         # http://localhost:8080
./scripts/smoke.sh                       # uji alur lengkap lewat API
```

Migrasi di `backend/migrations/*.sql` berjalan otomatis saat API start.

Environment variable: `APP_ADDR`, `DATABASE_URL`, `JWT_SECRET`, `JWT_TTL`, `STORAGE_DIR`,
`CHROME_PATH`, `CORS_ORIGINS`, `COMPANY_NAME`, dan `UPDATE_*` (lihat panduan rilis).

**Web**:

```bash
cd web
npm install
npm run dev        # http://localhost:5173, request /api diteruskan ke :8080
```

**Mobile**:

```bash
cd mobile
flutter pub get
flutter run --dart-define=API_URL=http://10.0.2.2:8080   # emulator Android ke backend lokal
```

Alamat server juga bisa diubah di layar login (tombol "Pengaturan server").

## Rilis, deploy Orange Pi, dan update

```bash
make backend                     # server Linux ARM64 (Orange Pi 4 Pro) + AMD64, web tertanam, di dist/
make build                       # backend + APK
make publish TAG=v0.2.0          # build lokal + terbitkan GitHub Release (tool/publish.sh)
```

Server bisa update sendiri dari GitHub Releases (otomatis, atau tombol di menu **Sistem & update** untuk
super admin), dan aplikasi teknisi bisa mengunduh serta memasang APK barunya sendiri.
Panduan lengkap: [docs/RILIS-DAN-UPDATE.md](docs/RILIS-DAN-UPDATE.md).

## Ringkasan API

Semua endpoint di bawah `/api` memakai header `Authorization: Bearer <token>`.

| Endpoint | Siapa | Fungsi |
| --- | --- | --- |
| `POST /auth/login`, `GET /auth/me` | semua | Login, profil |
| `GET /catalog` | semua | Data master umum untuk cache aplikasi HP |
| `GET/POST/PATCH/DELETE /master/{resource}` | staf (ubah: admin) | CRUD data master |
| `GET/POST /users`, `PATCH /users/{id}` | admin | Kelola pengguna |
| `GET/POST /visits`, `PATCH /visits/{id}` | staf | Jadwal kunjungan |
| `GET /visits/{id}` | sesuai akses | Dokumen laporan lengkap |
| `GET /me/visits`, `GET /visits/{id}/bundle` | teknisi | Jadwal dan data lokasi untuk offline |
| `POST /visits/{id}/start` | teknisi | Check-in |
| `PUT /visits/{id}/report` | teknisi / staf | Simpan isi laporan |
| `POST /visits/{id}/attachments`, `/signatures` | teknisi / staf | Upload foto, tanda tangan |
| `POST /visits/{id}/submit` | teknisi | Kirim untuk review |
| `POST /visits/{id}/return`, `/publish` | staf | Revisi atau terbitkan |
| `GET /visits/{id}/pdf` | staf / pelanggan | Unduh PDF (`?preview=1` untuk staf) |
| `GET /portal/sites`, `/visits`, `/reports`, `/recommendations` | pelanggan | Portal |
| `PATCH /portal/recommendations/{id}` | pelanggan | Tandai rekomendasi sudah dikerjakan |
| `GET /version` | publik | Versi server |
| `GET /app/android`, `/app/android/apk` | publik | Info dan unduhan APK terbaru |
| `GET /system/update`, `POST /system/update/check`, `/apply`, `PUT /system/update/settings` | super admin | Update server |
