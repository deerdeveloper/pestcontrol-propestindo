// Data aplikasi teknisi: ambil dari server bila online, pakai cache bila offline.
// Alurnya sama dengan Repository di aplikasi Flutter.
import { api } from '../api'
import { idb } from '../idb'
import { enqueue, run } from './sync'
import { todayISO } from '../labels'

export const uuid = () => (crypto.randomUUID ? crypto.randomUUID()
  : '10000000-1000-4000-8000-100000000000'.replace(/[018]/g, (c) => (c ^ (crypto.getRandomValues(new Uint8Array(1))[0] & (15 >> (c / 4)))).toString(16)))

async function cached(key, fetcher) {
  try {
    const data = await fetcher()
    await idb.put('cache', { key, data, at: new Date().toISOString() })
    return data
  } catch (e) {
    if (!e.isNetwork) throw e
    const c = await idb.get('cache', key)
    if (!c) throw e
    return c.data
  }
}

export const catalog = () => cached('catalog', () => api('/catalog'))
/** Kunjungan 7 hari ke belakang sampai 30 hari ke depan. */
export const myVisits = () => cached('my_visits', () => api(`/me/visits?from=${todayISO(-7)}&to=${todayISO(30)}`))
export const bundle = (visitId) => cached('bundle:' + visitId, () => api(`/visits/${visitId}/bundle`))

/** Mengunduh katalog dan bundle kunjungan aktif supaya siap dipakai offline. */
export async function prefetch(visits) {
  await catalog().catch(() => {})
  for (const v of visits) {
    if (['scheduled', 'in_progress', 'revision'].includes(v.status)) await bundle(v.id).catch(() => {})
  }
}

/** Draf laporan lokal. Jika belum ada, dibuat dari laporan di server (misal saat revisi). */
export async function draft(visitId, doc) {
  const existing = await idb.get('drafts', visitId)
  if (existing) return existing.d
  const r = doc.report
  const rows = (k, keep) => (r?.[k] || []).map((x) => Object.fromEntries(keep.map((f) => [f, x[f] ?? null])))
  return {
    checked_in: !!r,
    submitted: false,
    started_at: r?.started_at || null,
    pic_name: r?.pic_name || doc.pic?.name || null,
    general_notes: r?.general_notes || null,
    findings: rows('findings', ['id', 'pest_type_id', 'area_id', 'area_text', 'level', 'is_active', 'remarks']),
    treatments: rows('treatments', ['id', 'method_id', 'area_id', 'area_text', 'chemical_id', 'dose_text', 'quantity_used', 'equipment']),
    recommendations: rows('recommendations', ['id', 'category', 'risk_finding', 'recommendation']),
    station_checks: rows('station_checks', ['id', 'station_id', 'status', 'bait_consumption', 'finding']),
    photos: [],
    signatures: {},
  }
}

export const saveDraft = (visitId, d) => idb.put('drafts', { visit_id: visitId, d, at: new Date().toISOString() })

export async function checkIn(visitId, d, { lat = null, lng = null } = {}) {
  d.checked_in = true
  d.started_at ??= new Date().toISOString()
  await saveDraft(visitId, d)
  await enqueue(visitId, 'start', { started_at: d.started_at, lat, lng })
  run()
}

/**
 * Mengantrikan seluruh laporan: isi, foto, tanda tangan, lalu kirim untuk review.
 * `resend`: laporan pernah dikirim tetapi server belum menerimanya dan antrian sudah kosong,
 * jadi semua foto dan tanda tangan diantrikan lagi (aman karena server mengabaikan duplikat).
 */
export async function submit(visitId, d, { resend = false } = {}) {
  d.finished_at ??= new Date().toISOString()
  await enqueue(visitId, 'report', {
    pic_name: d.pic_name, general_notes: d.general_notes, started_at: d.started_at, finished_at: d.finished_at,
    findings: d.findings, treatments: d.treatments, recommendations: d.recommendations, station_checks: d.station_checks,
  })
  for (const ph of d.photos) {
    if (ph.queued && !resend) continue
    const { queued, ...p } = ph
    await enqueue(visitId, 'attachment', p)
    ph.queued = true
  }
  for (const role of ['technician', 'pic']) {
    const s = d.signatures[role]
    if (!s || (s.queued && !resend)) continue
    await enqueue(visitId, 'signature', { role, name: s.name, blob: s.blob, signed_at: s.signed_at })
    s.queued = true
  }
  await enqueue(visitId, 'submit', {})
  d.submitted = true
  await saveDraft(visitId, d)
}

export async function clearAll() {
  await Promise.all(['cache', 'drafts', 'outbox'].map((s) => idb.clear(s)))
}

/** Memperkecil foto kamera (maks 1600 px, JPEG 70%) supaya ringan dikirim lewat sinyal lemah. */
export async function compressImage(file, maxSide = 1600, quality = 0.7) {
  try {
    const bmp = await createImageBitmap(file, { imageOrientation: 'from-image' })
    const scale = Math.min(1, maxSide / Math.max(bmp.width, bmp.height))
    const c = document.createElement('canvas')
    c.width = Math.round(bmp.width * scale)
    c.height = Math.round(bmp.height * scale)
    c.getContext('2d').drawImage(bmp, 0, 0, c.width, c.height)
    bmp.close?.()
    return await new Promise((res) => c.toBlob((b) => res(b || file), 'image/jpeg', quality))
  } catch {
    return file
  }
}

/** Lokasi GPS untuk check-in. Tidak wajib: null jika ditolak atau habis waktu. */
export function currentPosition() {
  return new Promise((resolve) => {
    if (!navigator.geolocation) return resolve(null)
    navigator.geolocation.getCurrentPosition((p) => resolve({ lat: p.coords.latitude, lng: p.coords.longitude }),
      () => resolve(null), { enableHighAccuracy: true, timeout: 15000, maximumAge: 60000 })
  })
}
