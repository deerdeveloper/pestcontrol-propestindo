#!/usr/bin/env bash
# Uji alur lengkap lewat API: login, check-in, isi laporan, foto, tanda tangan,
# kirim, terbit, PDF, dan portal pelanggan. Butuh data dari `go run ./cmd/seed -demo`.
set -euo pipefail
API=${API:-http://localhost:8080}
IMG=${IMG:-$(dirname "$0")/../internal/pdf/assets/logo.png}
j() { curl -sf -H "Content-Type: application/json" -H "Authorization: Bearer $1" "${@:2}"; }
login() { curl -sf -X POST "$API/api/auth/login" -d "{\"email\":\"$1\",\"password\":\"$2\"}" | jq -r .token; }

ADMIN=$(login admin.ops@propestindo.local admin12345)
TECH=$(login teknisi@propestindo.local teknisi123)
CUST=$(login pic@gunasejahtera.local pelanggan123)

VISIT=$(j "$TECH" "$API/api/me/visits" | jq -r '[.[] | select(.status=="scheduled" or .status=="in_progress")][0].id')
echo "kunjungan: $VISIT"
BUNDLE=$(j "$TECH" "$API/api/visits/$VISIT/bundle")
CAT=$(j "$TECH" "$API/api/catalog")
area() { echo "$BUNDLE" | jq -r --arg n "$1" '.areas[] | select(.name==$n) | .id'; }
pest() { echo "$CAT" | jq -r --arg n "$1" '.pest_types[] | select(.name_id==$n) | .id'; }
method() { echo "$CAT" | jq -r --arg n "$1" '.treatment_methods[] | select(.name_en==$n) | .id'; }
chem() { echo "$CAT" | jq -r --arg n "$1" '.chemicals[] | select(.trade_name==$n) | .id'; }
station() { echo "$BUNDLE" | jq -r --arg n "$1" '.stations[] | select(.code==$n) | .id'; }

j "$TECH" -X POST "$API/api/visits/$VISIT/start" -d '{"lat":-6.28,"lng":107.15}' | jq -r .visit.status
FINDING=$(cat /proc/sys/kernel/random/uuid)
cat > /tmp/report.json <<JSON
{
  "general_notes": "Kunjungan rutin berjalan lancar.",
  "findings": [
    {"id":"$FINDING","pest_type_id":"$(pest Tikus)","area_id":"$(area Gudang)","level":"medium","is_active":true,"remarks":"Kotoran & jejak aktif"},
    {"pest_type_id":"$(pest Kecoa)","area_id":"$(area Pantry)","level":"low","is_active":true,"remarks":"Sarang kecil ditemukan"},
    {"pest_type_id":"$(pest Lalat)","area_text":"Lobi depan","level":"none","is_active":false}
  ],
  "treatments": [
    {"method_id":"$(method 'Residual Spraying')","area_id":"$(area Pantry)","chemical_id":"$(chem Deltamethrin)","dose_text":"5 ml per 1 liter air","equipment":"Backpack Sprayer"},
    {"method_id":"$(method 'Rodent Bait Stations & Traps')","area_id":"$(area 'Perimeter Luar')","chemical_id":"$(chem Brodifacoum)","dose_text":"3 blok per stasiun","quantity_used":"15 blok"}
  ],
  "recommendations": [
    {"category":"sanitation","risk_finding":"Sisa makanan di pantry","recommendation":"Bersihkan sisa makanan setiap hari dan pastikan tempat sampah tertutup rapat."},
    {"category":"exclusion","risk_finding":"Celah di bawah pintu belakang gudang","recommendation":"Pasang door sweep pada pintu belakang."}
  ],
  "station_checks": [
    {"station_id":"$(station BS-01)","status":"ok","bait_consumption":"none","finding":"No pests"},
    {"station_id":"$(station BS-02)","status":"check","bait_consumption":"partial","finding":"Rebaiting"},
    {"station_id":"$(station ILT-01)","status":"ok","finding":"Clean"}
  ]
}
JSON
j "$TECH" -X PUT "$API/api/visits/$VISIT/report" --data @/tmp/report.json | jq -c '.report | {f: (.findings|length), t: (.treatments|length), r: (.recommendations|length), s: (.station_checks|length)}'
curl -sf -H "Authorization: Bearer $TECH" -F file=@"$IMG" -F owner_type=finding -F owner_id="$FINDING" -F caption="Kotoran tikus" "$API/api/visits/$VISIT/attachments"; echo
curl -sf -H "Authorization: Bearer $TECH" -F file=@"$IMG" -F signer_role=technician -F "signer_name=Ahmad Fauzi" "$API/api/visits/$VISIT/signatures"; echo
curl -sf -H "Authorization: Bearer $TECH" -F file=@"$IMG" -F signer_role=pic -F "signer_name=Sari Ramadhani" "$API/api/visits/$VISIT/signatures"; echo
echo -n "edit setelah TTD PIC ditolak: "; curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $TECH" -X PUT "$API/api/visits/$VISIT/report" -d '{}'
j "$TECH" -X POST "$API/api/visits/$VISIT/submit" | jq -r .visit.status
echo -n "pelanggan belum bisa lihat: "; curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $CUST" "$API/api/visits/$VISIT"
j "$ADMIN" -X POST "$API/api/visits/$VISIT/publish" | jq -r '.visit.status + " " + .report.report_no'
curl -sf -H "Authorization: Bearer $CUST" "$API/api/visits/$VISIT/pdf" -o /tmp/laporan.pdf && file /tmp/laporan.pdf
j "$CUST" "$API/api/portal/reports" | jq -c '.[0] | {report_no, active_findings, open_recommendations}'
REC=$(j "$CUST" "$API/api/portal/recommendations?status=open" | jq -r '.[0].id')
j "$CUST" -X PATCH "$API/api/portal/recommendations/$REC" -d '{"customer_status":"done","customer_note":"Sudah dibersihkan"}' | jq -c .
echo -n "teknisi lain/portal tidak bisa akses master: "; curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $CUST" "$API/api/master/customers"
echo "SMOKE OK"
