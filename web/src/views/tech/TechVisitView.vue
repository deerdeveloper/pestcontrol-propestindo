<script setup>
// Pengisian laporan kunjungan di HP (PWA), mengikuti 6 bagian form Excel Propestindo.
// Semua isian langsung disimpan di HP (IndexedDB), lalu dikirim lewat antrian sinkronisasi.
// Alurnya sama dengan VisitScreen di aplikasi Flutter.
import { ref, reactive, computed, watch, onMounted, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import * as repo from '../../lib/tech/repo'
import { uuid } from '../../lib/tech/repo'
import { sync, stateOf, flushVisit, run, pendingCount } from '../../lib/tech/sync'
import { visitTypes, visitStatus, levels, categories, stationStatus, consumption, fmtDate, fmtTime } from '../../lib/labels'
import { confirmDialog, toast } from '../../lib/ui'
import Icon from '../../components/Icon.vue'
import Modal from '../../components/Modal.vue'
import StatusBadge from '../../components/StatusBadge.vue'
import SignaturePad from '../../components/SignaturePad.vue'
import QrScanner from '../../components/QrScanner.vue'
import EmptyState from '../../components/EmptyState.vue'

const route = useRoute()
const router = useRouter()
const visitId = route.params.id
const doc = ref(null)
const bundle = ref({})
const catalog = ref({})
const d = ref(null)
const error = ref('')
const tab = ref('info')

const status = computed(() => doc.value?.visit?.status)
const sigs = computed(() => d.value.signatures)
/** Server sudah menerima laporan (menunggu review atau sudah terbit). */
const delivered = computed(() => ['pending_review', 'published'].includes(status.value))
/** Laporan terkunci setelah dikirim, atau setelah PIC tanda tangan. */
const locked = computed(() => d.value.submitted === true || !!sigs.value.pic || delivered.value || status.value === 'cancelled')
const checkedIn = computed(() => d.value?.checked_in === true)
const canEdit = computed(() => !locked.value && checkedIn.value)
const st = computed(() => stateOf(visitId))

async function load() {
  try {
    const b = await repo.bundle(visitId)
    const c = await repo.catalog()
    const document = b.document
    const draft = await repo.draft(visitId, document)
    // Laporan dikembalikan admin untuk revisi: buka kunci supaya bisa diperbaiki.
    if (document.visit.status === 'revision' && draft.submitted === true && (await pendingCount(visitId)) === 0) {
      draft.submitted = false
      delete draft.signatures.pic
    }
    bundle.value = b
    catalog.value = c
    d.value = reactive(draft)
    doc.value = document
    if (!draft.checked_in && !locked.value) tab.value = 'info'
  } catch (e) {
    error.value = e.message
  }
}
onMounted(load)

// Antrian kunjungan ini habis terkirim di latar belakang: ambil status terbaru dari server.
watch(() => st.value.pending, (p, old) => { if (old > 0 && p === 0) refreshStatus() })

async function refreshStatus() {
  try { doc.value = (await repo.bundle(visitId)).document } catch {}
}
const save = () => repo.saveDraft(visitId, d.value)

// ---------- Pilihan dari katalog & bundle ----------
const opts = (key, lbl) => Object.fromEntries((catalog.value[key] || []).map((x) => [x.id, x[lbl]]))
const pests = computed(() => opts('pest_types', 'name_id'))
const methods = computed(() => opts('treatment_methods', 'name_id'))
const chems = computed(() => opts('chemicals', 'trade_name'))
const areas = computed(() => Object.fromEntries((bundle.value.areas || []).map((a) => [a.id, a.name])))
const stations = computed(() => bundle.value.stations || [])
const nameOf = (m, id, fb) => m[id] || fb || '-'
const checkOf = (s) => d.value.station_checks.find((c) => c.station_id === s.id)

// ---------- Foto ----------
const urls = new Map()
function photoUrl(ph) {
  if (!urls.has(ph.id)) urls.set(ph.id, URL.createObjectURL(ph.blob))
  return urls.get(ph.id)
}
function sigUrl(s) {
  const k = 'sig:' + s.signed_at
  if (!urls.has(k)) urls.set(k, URL.createObjectURL(s.blob))
  return urls.get(k)
}
onUnmounted(() => urls.forEach((u) => URL.revokeObjectURL(u)))
const photosOf = (type, id) => d.value.photos.filter((x) => x.owner_type === type && (x.owner_id || null) === (id || null))
const fileInput = ref(null)
let photoTarget = null
function addPhoto(type, id) { photoTarget = { type, id }; fileInput.value.value = ''; fileInput.value.click() }
async function onPhoto(e) {
  const files = [...(e.target.files || [])]
  for (const f of files) {
    const blob = await repo.compressImage(f)
    d.value.photos.push({ id: uuid(), owner_type: photoTarget.type, owner_id: photoTarget.id || null, blob, caption: null })
  }
  if (files.length) { await save(); toast(files.length > 1 ? `${files.length} foto ditambahkan` : 'Foto ditambahkan') }
}
async function removePhoto(ph) {
  if (!(await confirmDialog({ title: 'Hapus foto ini?', ok: 'Hapus', danger: true }))) return
  d.value.photos = d.value.photos.filter((x) => x.id !== ph.id)
  save()
}

// ---------- Check-in ----------
const checkingIn = ref(false)
async function checkIn() {
  checkingIn.value = true
  const pos = await repo.currentPosition() // lokasi tidak wajib
  await repo.checkIn(visitId, d.value, pos || {})
  checkingIn.value = false
  toast(pos ? 'Check-in tercatat dengan lokasi GPS' : 'Check-in tercatat (tanpa GPS)')
  tab.value = 'findings'
}

// ---------- Form tiap bagian (bottom sheet) ----------
const form = ref(null) // { kind, title, m, error }
const doses = computed(() => catalog.value.chemical_doses || [])
function edit(kind, row) {
  const init = {
    findings: { id: uuid(), level: 'low', is_active: true },
    treatments: { id: uuid() },
    recommendations: { id: uuid(), category: 'sanitation' },
  }[kind]
  const titles = { findings: ['Tambah temuan hama', 'Ubah temuan'], treatments: ['Tambah tindakan', 'Ubah tindakan'], recommendations: ['Tambah rekomendasi', 'Ubah rekomendasi'] }[kind]
  form.value = { kind, title: titles[row ? 1 : 0], m: reactive({ ...(row || init) }), error: '' }
}
function editStation(s) {
  form.value = { kind: 'station', title: `${s.code} · ${s.equipment_type}`, station: s,
    m: reactive({ ...(checkOf(s) || { station_id: s.id, status: 'ok', bait_consumption: 'none' }) }), error: '' }
}
// Isi dosis standar otomatis saat bahan dan metode dipilih.
function suggestDose() {
  const m = form.value.m
  const match = doses.value.find((x) => x.chemical_id === m.chemical_id && (!x.method_id || x.method_id === m.method_id))
  if (match && !m.dose_text) m.dose_text = match.dose_text
}
function validate(f) {
  const m = f.m
  if (f.kind === 'findings') return !m.pest_type_id ? 'Pilih jenis hama' : !m.area_id && !(m.area_text || '').trim() ? 'Pilih area atau isi lokasi lain' : null
  if (f.kind === 'treatments') return !m.method_id ? 'Pilih metode' : null
  if (f.kind === 'recommendations') return !(m.risk_finding || '').trim() || !(m.recommendation || '').trim() ? 'Isi temuan risiko dan rekomendasi' : null
  return null
}
async function saveForm() {
  const f = form.value
  const err = validate(f)
  if (err) { f.error = err; return }
  const row = { ...f.m }
  for (const k of ['area_id', 'chemical_id', 'pest_type_id', 'method_id']) if (row[k] === '') row[k] = null
  if (row.area_id) row.area_text = null
  if (f.kind === 'station') {
    d.value.station_checks = d.value.station_checks.filter((c) => c.station_id !== f.station.id)
    d.value.station_checks.push(row)
  } else {
    const l = d.value[f.kind]
    const i = l.findIndex((x) => x.id === row.id)
    i >= 0 ? (l[i] = row) : l.push(row)
  }
  form.value = null
  await save()
}
async function removeRow(kind, row) {
  if (!(await confirmDialog({ title: 'Hapus baris ini?', message: 'Foto yang terkait ikut terhapus.', ok: 'Hapus', danger: true }))) return
  d.value[kind] = d.value[kind].filter((x) => x.id !== row.id)
  d.value.photos = d.value.photos.filter((x) => x.owner_id !== row.id)
  form.value = null
  save()
}

// ---------- Scan QR stasiun ----------
const scanning = ref(false)
const hasScanner = 'BarcodeDetector' in window
function onScan(value) {
  scanning.value = false
  const s = stations.value.find((x) => x.qr_value === value || x.code === value)
  if (!s) { toast('QR tidak cocok dengan stasiun di lokasi ini', 'error'); return }
  editStation(s)
}

// ---------- Tanda tangan ----------
const signing = ref(null) // { role, name }
const pad = ref(null)
const padEmpty = ref(true)
function sign(role) {
  signing.value = { role, name: role === 'pic' ? d.value.pic_name || '' : doc.value.technician?.name || '' }
  padEmpty.value = true
}
async function saveSign() {
  const s = signing.value
  if (!s.name.trim() || padEmpty.value) return
  const blob = await pad.value.toBlob()
  d.value.signatures[s.role] = { name: s.name.trim(), blob, signed_at: new Date().toISOString() }
  if (s.role === 'pic') d.value.pic_name = s.name.trim()
  signing.value = null
  await save()
  toast('Tanda tangan disimpan')
}
const canSign = (role) => checkedIn.value && d.value.submitted !== true && !delivered.value && (role === 'technician' || !sigs.value[role] || canEdit.value)

// ---------- Kirim ----------
const sending = ref(false)
const result = ref(null) // { title, icon, lines, offline }
async function submit() {
  if (!sigs.value.technician) { toast('Tanda tangan teknisi wajib diisi sebelum laporan dikirim', 'error'); return }
  const resend = d.value.submitted === true
  const ok = await confirmDialog(resend
    ? { title: 'Kirim ulang laporan?', message: 'Server belum menerima laporan ini. Semua isi, foto, dan tanda tangan akan dikirim ulang.', ok: 'Kirim ulang' }
    : { title: 'Kirim laporan?', message: 'Setelah dikirim, laporan tidak bisa diubah kecuali dikembalikan admin untuk revisi.', ok: 'Kirim' })
  if (!ok) return
  await repo.submit(visitId, d.value, { resend })
  await sendNow()
}
/** Mengirim antrian kunjungan ini sekarang dan menunggu hasilnya, lalu memberi tahu teknisi. */
async function sendNow() {
  sending.value = true
  result.value = null
  let s, slow = false
  try {
    s = await Promise.race([flushVisit(visitId), new Promise((r) => setTimeout(() => r(null), 3 * 60 * 1000))])
    if (!s) { slow = true; s = stateOf(visitId) }
  } catch (e) {
    s = { pending: stateOf(visitId).pending, error: String(e?.message || e) }
  }
  sending.value = false
  if (s.pending === 0) {
    await refreshStatus()
    toast('Laporan terkirim. Status: menunggu review admin.')
    router.replace('/tech')
    return
  }
  const off = s.offline || slow
  result.value = {
    off,
    title: off ? 'Laporan belum terkirim' : 'Laporan ditolak server',
    lines: [
      slow ? 'Pengiriman masih berjalan lebih dari 3 menit (sinyal lemah).' : s.offline ? 'Tidak bisa terhubung ke server.' : null,
      s.error,
      `Data laporan aman tersimpan di HP (${s.pending} data menunggu). ${off ? 'Aplikasi akan mencoba lagi otomatis saat ada sinyal.' : 'Perbaiki masalahnya lalu tekan Coba lagi, atau hubungi admin.'}`,
    ].filter(Boolean),
  }
}

const lockText = computed(() => {
  if (status.value === 'published') return 'Laporan sudah terbit.'
  if (status.value === 'cancelled') return 'Kunjungan dibatalkan admin.'
  if (delivered.value) return 'Laporan sudah diterima server, menunggu review admin.'
  if (d.value.submitted === true) return st.value.pending > 0 ? 'Laporan belum terkirim ke server. Buka tab Selesai untuk mengirim.' : 'Laporan belum diterima server. Buka tab Selesai untuk kirim ulang.'
  return 'Laporan terkunci setelah tanda tangan PIC. Buka tab Selesai untuk mengirim.'
})
const tabs = computed(() => [
  { k: 'info', l: 'Info', i: 'info' },
  { k: 'findings', l: 'Temuan', i: 'bug', n: d.value.findings.length },
  { k: 'treatments', l: 'Tindakan', i: 'spray', n: d.value.treatments.length },
  { k: 'recommendations', l: 'Rekomendasi', i: 'lightbulb', n: d.value.recommendations.length },
  { k: 'stations', l: 'Stasiun', i: 'radar', n: stations.value.length ? `${d.value.station_checks.length}/${stations.value.length}` : 0 },
  { k: 'finish', l: 'Selesai', i: 'send' },
])
const progress = computed(() => {
  if (!d.value) return 0
  const steps = [checkedIn.value, d.value.findings.length > 0 || d.value.treatments.length > 0, !stations.value.length || d.value.station_checks.length >= stations.value.length, !!sigs.value.technician, !!sigs.value.pic, delivered.value]
  return Math.round((steps.filter(Boolean).length / steps.length) * 100)
})
const addLabel = { findings: 'Tambah temuan', treatments: 'Tambah tindakan', recommendations: 'Tambah rekomendasi' }
const lvlClass = { none: 'cancelled', low: 'ok', medium: 'warn', high: 'bad' }
const stClass = { ok: 'ok', check: 'warn', replace: 'bad' }
const catIcon = { exclusion: 'lock', sanitation: 'sun', storage: 'layers', habitual: 'users' }
const mapsUrl = computed(() => doc.value ? 'https://www.google.com/maps/search/?api=1&query=' + encodeURIComponent(doc.value.site.address || doc.value.site.name) : '#')
</script>

<template>
  <div class="tv">
    <input ref="fileInput" type="file" accept="image/*" capture="environment" hidden @change="onPhoto" />

    <header class="tv-head">
      <button class="btn icon back-btn" aria-label="Kembali" @click="router.push('/tech')"><Icon name="arrow-left" /></button>
      <div class="grow">
        <b>{{ doc?.customer.name || 'Kunjungan' }}</b>
        <small v-if="doc">{{ doc.site.name }} · {{ fmtDate(doc.visit.scheduled_date) }}</small>
      </div>
      <StatusBadge v-if="doc" :status="status" />
    </header>

    <div v-if="!doc" class="pad">
      <p v-if="error" class="notice red"><Icon name="alert" />{{ error }}</p>
      <div v-else class="t-card" style="padding: 40px; text-align: center"><Icon name="refresh" class="spin" /></div>
    </div>

    <template v-else>
      <div class="progress"><i :style="{ width: progress + '%' }" /></div>
      <nav class="tv-tabs">
        <button v-for="t in tabs" :key="t.k" :class="{ on: tab === t.k }" @click="tab = t.k">
          <Icon :name="t.i" />{{ t.l }}<span v-if="t.n" class="n">{{ t.n }}</span>
        </button>
      </nav>

      <div class="pad stack">
        <div v-if="locked" class="notice" :class="delivered ? 'green' : ''"><Icon :name="delivered ? 'cloud-check' : 'lock'" />{{ lockText }}</div>
        <div v-if="sync.pending && st.pending" class="notice" :class="{ red: st.error && !st.offline }">
          <Icon :name="sync.running ? 'refresh' : 'cloud-up'" :class="{ spin: sync.running }" />
          <span class="grow">{{ st.pending }} data kunjungan ini belum terkirim<small v-if="st.error" class="block">{{ st.error }}</small></span>
        </div>

        <div v-if="!checkedIn && !locked" class="t-card checkin">
          <div class="ic"><Icon name="map-pin" /></div>
          <b>Sudah sampai di lokasi?</b>
          <p class="muted small">Check-in mencatat jam mulai dan lokasi GPS. Setelah itu form laporan bisa diisi.</p>
          <button class="btn gold lg block" :disabled="checkingIn" @click="checkIn"><Icon name="login" />{{ checkingIn ? 'Mengambil lokasi…' : 'Check-in di lokasi' }}</button>
        </div>

        <!-- INFO -->
        <template v-if="tab === 'info'">
          <div class="t-card sec">
            <dl class="kv">
              <dt>Lokasi</dt><dd>{{ doc.site.name }}<small class="block muted">{{ doc.site.address }}</small>
                <a :href="mapsUrl" target="_blank" rel="noopener" class="link-btn small"><Icon name="map-pin" :size="14" />Buka peta</a></dd>
              <dt>Tanggal</dt><dd>{{ fmtDate(doc.visit.scheduled_date) }} · {{ visitTypes[doc.visit.visit_type] }}</dd>
              <dt>Status</dt><dd>{{ visitStatus[status] }}</dd>
              <dt v-if="d.started_at">Mulai</dt><dd v-if="d.started_at">{{ fmtTime(d.started_at) }} WIB</dd>
            </dl>
          </div>
          <div v-if="doc.visit.notes" class="notice blue"><Icon name="note" /><span><b>Catatan admin:</b> {{ doc.visit.notes }}</span></div>
          <div v-if="status === 'revision' && doc.report?.review_notes" class="notice red"><Icon name="edit" /><span><b>Catatan revisi:</b> {{ doc.report.review_notes }}</span></div>
          <div v-if="bundle.contacts?.length" class="t-card sec">
            <h3 class="h">Kontak PIC</h3>
            <div v-for="c in bundle.contacts" :key="c.id" class="contact">
              <div class="avatar">{{ c.name.slice(0, 1) }}</div>
              <div class="grow"><b>{{ c.name }}</b><small class="block muted">{{ c.position || '-' }}{{ c.is_primary ? ' · PIC utama' : '' }}</small></div>
              <a v-if="c.phone" :href="'tel:' + c.phone" class="btn icon sm" aria-label="Telepon"><Icon name="phone" /></a>
            </div>
          </div>
          <div v-if="bundle.previous_findings?.length" class="t-card sec">
            <h3 class="h">Temuan kunjungan sebelumnya <small class="muted">({{ fmtDate(bundle.previous_visit_date) }})</small></h3>
            <div v-for="(f, i) in bundle.previous_findings" :key="i" class="li"><Icon name="bug" :size="15" /><span class="grow">{{ f.pest_name_id }} di {{ f.area_name || '-' }}</span><span class="badge" :class="lvlClass[f.level]">{{ levels[f.level] }}</span></div>
          </div>
          <div v-if="bundle.open_recommendations?.length" class="t-card sec">
            <h3 class="h">Rekomendasi belum dikerjakan pelanggan</h3>
            <div v-for="r in bundle.open_recommendations" :key="r.id" class="li"><Icon :name="catIcon[r.category] || 'lightbulb'" :size="15" /><span class="grow"><b>{{ categories[r.category] }}:</b> {{ r.recommendation }}</span></div>
          </div>
        </template>

        <!-- TEMUAN / TINDAKAN / REKOMENDASI -->
        <template v-if="['findings', 'treatments', 'recommendations'].includes(tab)">
          <div v-for="r in d[tab]" :key="r.id" class="t-card item" @click="canEdit && edit(tab, r)">
            <template v-if="tab === 'findings'">
              <div class="row"><b class="grow">{{ nameOf(pests, r.pest_type_id) }}</b><span class="badge" :class="lvlClass[r.level]">{{ levels[r.level] }}</span></div>
              <small class="muted">{{ nameOf(areas, r.area_id, r.area_text) }} · {{ r.is_active ? 'Aktif' : 'Tidak aktif' }}</small>
              <p v-if="r.remarks" class="small">{{ r.remarks }}</p>
              <div class="strip" @click.stop>
                <div v-for="ph in photosOf('finding', r.id)" :key="ph.id" class="ph"><img :src="photoUrl(ph)" alt="" /><button v-if="!locked" @click="removePhoto(ph)"><Icon name="x" :size="12" /></button></div>
                <button v-if="!locked && checkedIn" class="ph add" @click="addPhoto('finding', r.id)"><Icon name="camera" /></button>
              </div>
            </template>
            <template v-else-if="tab === 'treatments'">
              <b>{{ nameOf(methods, r.method_id) }}</b>
              <small class="muted">{{ nameOf(areas, r.area_id, r.area_text) }} · {{ nameOf(chems, r.chemical_id) }}</small>
              <small class="muted">Dosis {{ r.dose_text || '-' }} · Jumlah {{ r.quantity_used || '-' }}{{ r.equipment ? ' · ' + r.equipment : '' }}</small>
            </template>
            <template v-else>
              <span class="badge plain">{{ categories[r.category] }}</span>
              <p class="small" style="margin-top: 6px">{{ r.risk_finding }}</p>
              <p class="reco"><Icon name="arrow-right" :size="14" />{{ r.recommendation }}</p>
            </template>
          </div>
          <div v-if="!d[tab].length" class="t-card"><EmptyState :icon="tabs.find((t) => t.k === tab).i" title="Belum ada data" :text="canEdit ? 'Tekan tombol di bawah untuk menambah.' : ''" /></div>
          <p v-if="canEdit && d[tab].length" class="muted small" style="text-align: center">Ketuk kartu untuk mengubah atau menghapus.</p>
        </template>

        <!-- STASIUN -->
        <template v-if="tab === 'stations'">
          <div class="t-card sec">
            <div class="row"><b class="grow">{{ d.station_checks.length }} dari {{ stations.length }} stasiun diperiksa</b></div>
            <div class="bar" style="margin-top: 8px"><i :style="{ width: (stations.length ? (d.station_checks.length / stations.length) * 100 : 0) + '%' }" /></div>
          </div>
          <button v-for="s in stations" :key="s.id" class="t-card station" :disabled="!canEdit" @click="editStation(s)">
            <Icon :name="checkOf(s) ? 'check-circle' : 'circle'" :class="checkOf(s) ? (checkOf(s).status === 'ok' ? 'ok' : 'warn') : 'todo'" />
            <span class="grow"><b>{{ s.code }} · {{ s.equipment_type }}</b>
              <small class="block muted">{{ checkOf(s) ? `${stationStatus[checkOf(s).status]} · ${consumption[checkOf(s).bait_consumption]}` : s.area_name || '-' }}</small></span>
            <span v-if="checkOf(s)" class="badge" :class="stClass[checkOf(s).status]">{{ stationStatus[checkOf(s).status] }}</span>
          </button>
          <div v-if="!stations.length" class="t-card"><EmptyState icon="radar" title="Lokasi ini belum punya stasiun monitoring" /></div>
        </template>

        <!-- SELESAI -->
        <template v-if="tab === 'finish'">
          <div class="summary-grid">
            <button v-for="t in tabs.slice(1, 5)" :key="t.k" class="t-card" @click="tab = t.k"><Icon :name="t.i" /><b>{{ t.n || 0 }}</b><small>{{ t.l }}</small></button>
          </div>
          <div class="t-card sec">
            <label class="field"><span>Catatan umum</span>
              <textarea v-model="d.general_notes" :disabled="!canEdit" rows="3" placeholder="Kondisi umum lokasi, kendala, dll." @input="save" /></label>
          </div>
          <div class="t-card sec">
            <h3 class="h">Foto dokumentasi umum</h3>
            <div class="strip">
              <div v-for="ph in photosOf('report', null)" :key="ph.id" class="ph lg"><img :src="photoUrl(ph)" alt="" /><button v-if="!locked" @click="removePhoto(ph)"><Icon name="x" :size="12" /></button></div>
              <button v-if="!locked && checkedIn" class="ph lg add" @click="addPhoto('report', null)"><Icon name="camera" /><small>Ambil foto</small></button>
            </div>
          </div>
          <div class="t-card sec">
            <h3 class="h">Tanda tangan</h3>
            <div v-for="[role, lbl] in [['technician', 'Teknisi'], ['pic', 'PIC pelanggan']]" :key="role" class="sigrow">
              <div class="sigbox"><img v-if="sigs[role]?.blob" :src="sigUrl(sigs[role])" alt="" /><Icon v-else name="signature" /></div>
              <div class="grow"><b>{{ lbl }}</b><small class="block muted">{{ sigs[role] ? sigs[role].name : 'Belum tanda tangan' }}</small></div>
              <button v-if="canSign(role)" class="btn sm" :class="{ primary: !sigs[role] }" @click="sign(role)">{{ sigs[role] ? 'Ulangi' : 'Tanda tangan' }}</button>
              <Icon v-else-if="sigs[role]" name="check-circle" class="ok" />
            </div>
            <p class="muted small" style="margin-top: 8px">Setelah PIC tanda tangan, isi laporan terkunci.</p>
          </div>

          <div v-if="delivered" class="notice green"><Icon name="cloud-check" /><span><b>{{ status === 'published' ? 'Laporan sudah terbit' : 'Laporan sudah diterima server' }}</b><small v-if="status !== 'published'" class="block">Menunggu review admin</small></span></div>
          <template v-else-if="checkedIn">
            <div v-if="d.submitted && st.pending" class="notice" :class="{ red: st.error && !st.offline }">
              <Icon :name="st.offline ? 'cloud-off' : 'cloud-up'" />
              <span class="grow"><b>Laporan belum terkirim ke server ({{ st.pending }} data menunggu)</b><small v-if="st.error" class="block">{{ st.error }}</small></span>
            </div>
          </template>
        </template>
      </div>

      <!-- Tombol aksi bawah -->
      <div class="actionbar">
        <template v-if="['findings', 'treatments', 'recommendations'].includes(tab) && canEdit">
          <button class="btn primary lg block" @click="edit(tab)"><Icon name="plus" />{{ addLabel[tab] }}</button>
        </template>
        <template v-else-if="tab === 'stations' && canEdit && stations.length">
          <button v-if="hasScanner" class="btn primary lg block" @click="scanning = true"><Icon name="qr" />Scan QR stasiun</button>
          <p v-else class="muted small" style="text-align: center; width: 100%">Ketuk stasiun untuk mengisi hasil pemeriksaan.</p>
        </template>
        <template v-else-if="tab === 'finish' && checkedIn && !delivered">
          <button v-if="!d.submitted" class="btn gold lg block" @click="submit"><Icon name="send" />Kirim laporan</button>
          <button v-else-if="st.pending" class="btn primary lg block" :disabled="sync.running" @click="sendNow"><Icon name="refresh" :class="{ spin: sync.running }" />{{ sync.running ? 'Sedang mengirim…' : 'Coba kirim lagi' }}</button>
          <button v-else class="btn gold lg block" @click="submit"><Icon name="send" />Kirim ulang laporan</button>
        </template>
        <template v-else-if="tab !== 'finish' && checkedIn && !delivered">
          <button class="btn lg block" @click="tab = 'finish'">Lanjut ke Selesai<Icon name="arrow-right" /></button>
        </template>
      </div>
    </template>

    <!-- Form baris -->
    <Modal v-if="form" :title="form.title" @close="form = null">
      <form id="row-form" class="stack" @submit.prevent="saveForm">
        <template v-if="form.kind === 'findings'">
          <label class="field"><span>Hama <b>*</b></span><select v-model="form.m.pest_type_id"><option :value="undefined" disabled>Pilih jenis hama</option><option v-for="(l, k) in pests" :key="k" :value="k">{{ l }}</option></select></label>
          <label class="field"><span>Area</span><select v-model="form.m.area_id"><option :value="null">Lokasi lain…</option><option v-for="(l, k) in areas" :key="k" :value="k">{{ l }}</option></select></label>
          <label v-if="!form.m.area_id" class="field"><span>Lokasi lain (jika tidak ada di daftar)</span><input v-model="form.m.area_text" /></label>
          <div class="field"><span>Tingkat infestasi</span>
            <div class="chips"><button v-for="(l, k) in levels" :key="k" type="button" :class="['chip', lvlClass[k], { on: form.m.level === k }]" @click="form.m.level = k">{{ l }}</button></div></div>
          <label class="check"><input type="checkbox" v-model="form.m.is_active" /><span>Hama masih aktif</span></label>
          <label class="field"><span>Keterangan</span><textarea v-model="form.m.remarks" rows="2" /></label>
        </template>
        <template v-else-if="form.kind === 'treatments'">
          <label class="field"><span>Metode <b>*</b></span><select v-model="form.m.method_id" @change="suggestDose"><option :value="undefined" disabled>Pilih metode</option><option v-for="(l, k) in methods" :key="k" :value="k">{{ l }}</option></select></label>
          <label class="field"><span>Area</span><select v-model="form.m.area_id"><option :value="null">Area lain…</option><option v-for="(l, k) in areas" :key="k" :value="k">{{ l }}</option></select></label>
          <label v-if="!form.m.area_id" class="field"><span>Area lain</span><input v-model="form.m.area_text" /></label>
          <label class="field"><span>Bahan kimia</span><select v-model="form.m.chemical_id" @change="suggestDose"><option :value="null">-</option><option v-for="(l, k) in chems" :key="k" :value="k">{{ l }}</option></select></label>
          <div class="form-grid">
            <label class="field"><span>Dosis</span><input v-model="form.m.dose_text" /></label>
            <label class="field"><span>Jumlah dipakai</span><input v-model="form.m.quantity_used" /></label>
          </div>
          <label class="field"><span>Alat</span><input v-model="form.m.equipment" placeholder="Mis. Backpack Sprayer" /></label>
        </template>
        <template v-else-if="form.kind === 'recommendations'">
          <div class="field"><span>Kategori</span>
            <div class="chips"><button v-for="(l, k) in categories" :key="k" type="button" :class="['chip', { on: form.m.category === k }]" @click="form.m.category = k">{{ l }}</button></div></div>
          <label class="field"><span>Temuan risiko / kondisi lapangan <b>*</b></span><textarea v-model="form.m.risk_finding" rows="2" /></label>
          <label class="field"><span>Rekomendasi untuk klien <b>*</b></span><textarea v-model="form.m.recommendation" rows="3" /></label>
        </template>
        <template v-else-if="form.kind === 'station'">
          <p class="muted"><Icon name="map-pin" :size="14" /> Area: {{ form.station.area_name || '-' }}</p>
          <div class="field"><span>Kondisi alat</span>
            <div class="chips"><button v-for="(l, k) in stationStatus" :key="k" type="button" :class="['chip', stClass[k], { on: form.m.status === k }]" @click="form.m.status = k">{{ l }}</button></div></div>
          <div class="field"><span>Konsumsi umpan</span>
            <div class="chips"><button v-for="(l, k) in consumption" :key="k" type="button" :class="['chip', { on: form.m.bait_consumption === k }]" @click="form.m.bait_consumption = k">{{ l }}</button></div></div>
          <label class="field"><span>Temuan</span><input v-model="form.m.finding" /></label>
        </template>
        <p v-if="form.error" class="notice red"><Icon name="alert" />{{ form.error }}</p>
      </form>
      <template #foot>
        <button v-if="form.kind !== 'station' && d[form.kind]?.some((x) => x.id === form.m.id)" type="button" class="btn danger" @click="removeRow(form.kind, form.m)"><Icon name="trash" /></button>
        <button form="row-form" class="btn primary">Simpan</button>
      </template>
    </Modal>

    <!-- Tanda tangan -->
    <Modal v-if="signing" :title="signing.role === 'pic' ? 'Tanda tangan PIC pelanggan' : 'Tanda tangan teknisi'" @close="signing = null">
      <div class="stack">
        <label class="field"><span>{{ signing.role === 'pic' ? 'Nama PIC pelanggan' : 'Nama teknisi' }}</span><input v-model="signing.name" /></label>
        <SignaturePad ref="pad" @change="padEmpty = $event" />
      </div>
      <template #foot>
        <button type="button" class="btn" @click="pad.clear()">Hapus</button>
        <button class="btn primary" :disabled="padEmpty || !signing.name.trim()" @click="saveSign">Simpan tanda tangan</button>
      </template>
    </Modal>

    <!-- Scan QR -->
    <Modal v-if="scanning" title="Scan QR stasiun" @close="scanning = false">
      <QrScanner @detect="onScan" />
      <p class="muted small" style="margin-top: 10px; text-align: center">Arahkan kamera ke stiker QR pada alat monitoring.</p>
    </Modal>

    <!-- Proses kirim -->
    <Modal v-if="sending" title="Mengirim laporan" :closable="false">
      <div class="row" style="padding: 8px 0 12px"><Icon name="refresh" class="spin" :size="26" /><span>Mengirim laporan ke server… Jangan tutup halaman ini.</span></div>
    </Modal>
    <Modal v-if="result" :title="result.title" @close="result = null">
      <div class="stack">
        <div class="notice" :class="result.off ? '' : 'red'"><Icon :name="result.off ? 'cloud-off' : 'alert'" /><span>{{ result.lines[0] }}</span></div>
        <p v-for="(l, i) in result.lines.slice(1)" :key="i">{{ l }}</p>
      </div>
      <template #foot>
        <button class="btn" @click="result = null">Tutup</button>
        <button class="btn primary" @click="sendNow"><Icon name="refresh" />Coba lagi</button>
      </template>
    </Modal>
  </div>
</template>

<style scoped>
.tv-head { position: sticky; top: 0; z-index: 22; display: flex; align-items: center; gap: 10px; padding: 10px 12px; background: var(--green-950); color: #fff; }
.tv-head b { display: block; font-size: 15.5px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.tv-head small { display: block; color: #b9d2c1; font-size: 12px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.back-btn { background: rgba(255, 255, 255, .1); border-color: transparent; color: #fff; }
.back-btn:hover { background: rgba(255, 255, 255, .18); color: #fff; border-color: transparent; }
.progress { height: 4px; background: var(--green-900); }
.progress i { display: block; height: 100%; background: var(--gold); transition: width .3s; }
.tv-tabs { position: sticky; top: 60px; z-index: 21; display: flex; gap: 6px; overflow-x: auto; scrollbar-width: none; padding: 10px 12px; background: rgba(244, 247, 245, .96); backdrop-filter: blur(10px); border-bottom: 1px solid var(--line); }
.tv-tabs::-webkit-scrollbar { display: none; }
.tv-tabs button { flex: none; display: inline-flex; align-items: center; gap: 6px; padding: 7px 12px; border-radius: 999px; border: 1.5px solid var(--line); background: #fff; font: inherit; font-weight: 700; font-size: 13px; color: var(--ink-2); cursor: pointer; }
.tv-tabs button svg { width: 16px; height: 16px; }
.tv-tabs button.on { background: var(--green-800); border-color: var(--green-800); color: #fff; }
.tv-tabs .n { background: rgba(0, 0, 0, .07); border-radius: 99px; padding: 0 7px; font-size: 11.5px; }
.tv-tabs .on .n { background: rgba(255, 255, 255, .2); }
.pad { padding: 14px; }
.block { display: block; }
.sec { padding: 14px 16px; }
.h { font-size: 14px; margin-bottom: 10px; }
.kv { grid-template-columns: 86px minmax(0, 1fr); }
.checkin { padding: 20px; text-align: center; border: 1.5px solid var(--gold-100); background: linear-gradient(180deg, var(--gold-50), #fff); }
.checkin .ic { width: 52px; height: 52px; border-radius: 16px; display: grid; place-items: center; margin: 0 auto 10px; background: var(--gold); color: var(--green-950); }
.checkin b { font-size: 16px; display: block; }
.checkin p { margin: 4px 0 14px; }
.contact, .li { display: flex; align-items: center; gap: 10px; padding: 8px 0; border-bottom: 1px solid var(--line-2); font-size: 13.5px; }
.contact:last-child, .li:last-child { border: 0; }
.li svg { color: var(--green-600); }
.item { padding: 14px 16px; display: flex; flex-direction: column; gap: 3px; cursor: pointer; }
.item:active { transform: scale(.99); }
.item p { margin-top: 4px; }
.reco { font-weight: 700; display: flex; gap: 6px; align-items: flex-start; font-size: 13.5px; }
.reco svg { margin-top: 3px; color: var(--green-600); }
.strip { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 8px; }
.ph { position: relative; width: 64px; height: 64px; border-radius: 12px; overflow: hidden; flex: none; }
.ph.lg { width: 92px; height: 92px; }
.ph img { width: 100%; height: 100%; object-fit: cover; display: block; }
.ph button { position: absolute; top: 3px; right: 3px; width: 22px; height: 22px; border-radius: 50%; border: 0; background: rgba(0, 0, 0, .55); color: #fff; display: grid; place-items: center; cursor: pointer; padding: 0; }
.ph.add { border: 1.5px dashed #b7c6bd; background: var(--soft); color: var(--green-700); display: grid; place-items: center; align-content: center; gap: 2px; cursor: pointer; font: inherit; }
.ph.add small { font-size: 10.5px; font-weight: 700; }
.station { width: 100%; display: flex; align-items: center; gap: 12px; padding: 13px 14px; text-align: left; font: inherit; color: inherit; cursor: pointer; }
.station:disabled { cursor: default; }
.station svg.ok, .ok { color: var(--green-600); }
.station svg.warn { color: var(--amber); }
.station svg.todo { color: #b7c6bd; }
.summary-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px; }
.summary-grid .t-card { margin: 0; padding: 12px 4px; display: flex; flex-direction: column; align-items: center; gap: 2px; font: inherit; cursor: pointer; color: var(--green-700); }
.summary-grid b { font-size: 18px; color: var(--ink); }
.summary-grid small { font-size: 11px; color: var(--muted); font-weight: 700; }
.sigrow { display: flex; align-items: center; gap: 12px; padding: 10px 0; border-bottom: 1px solid var(--line-2); }
.sigrow:last-of-type { border: 0; }
.sigbox { width: 84px; height: 52px; border-radius: 10px; border: 1.5px dashed var(--line); display: grid; place-items: center; color: #b7c6bd; overflow: hidden; flex: none; background: #fff; }
.sigbox img { width: 100%; height: 100%; object-fit: contain; }
.actionbar { position: fixed; z-index: 24; bottom: 0; left: 50%; transform: translateX(-50%); width: 100%; max-width: 640px; display: flex; gap: 10px; padding: 12px 14px calc(12px + var(--safe-b)); background: linear-gradient(180deg, rgba(244, 247, 245, 0), var(--bg) 30%); }
.actionbar:empty { display: none; }
.chips { display: flex; flex-wrap: wrap; gap: 8px; }
.chip { padding: 9px 14px; border-radius: 12px; border: 1.5px solid var(--line); background: #fff; font: inherit; font-weight: 700; font-size: 13.5px; color: var(--ink-2); cursor: pointer; }
.chip.on { border-color: var(--green-700); background: var(--green-50); color: var(--green-800); box-shadow: inset 0 0 0 1px var(--green-700); }
.chip.warn.on { border-color: var(--amber); background: var(--amber-50); color: var(--amber); box-shadow: inset 0 0 0 1px var(--amber); }
.chip.bad.on { border-color: var(--red); background: var(--red-50); color: var(--red); box-shadow: inset 0 0 0 1px var(--red); }
.chip.cancelled.on { border-color: var(--muted); background: var(--line-2); color: var(--ink-2); box-shadow: inset 0 0 0 1px var(--muted); }
</style>
