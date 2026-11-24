// Antrian sinkronisasi aplikasi teknisi (web). Perilakunya sama dengan SyncService di aplikasi Flutter:
// - urutan dijaga per kunjungan; jika satu kunjungan ditolak server, kunjungan lain tetap dikirim;
// - jika tidak ada koneksi, semua berhenti dan dicoba lagi saat online / tiap 2 menit;
// - setiap kegagalan disimpan per item supaya bisa ditampilkan ke teknisi.
import { reactive } from 'vue'
import { api, ApiError, getToken } from '../api'
import { idb } from '../idb'

export const sync = reactive({ running: false, pending: 0, lastError: null, offline: false, visits: {} })

const EMPTY = Object.freeze({ pending: 0, error: null, offline: false })
export const stateOf = (visitId) => sync.visits[visitId] || EMPTY

export function label(item) {
  return ({ start: 'Check-in', report: 'Isi laporan', attachment: 'Foto', submit: 'Kirim laporan',
    signature: item.payload.role === 'pic' ? 'Tanda tangan PIC' : 'Tanda tangan teknisi' })[item.kind] || item.kind
}

export async function enqueue(visitId, kind, payload) {
  await idb.add('outbox', { visit_id: visitId, kind, payload, created_at: new Date().toISOString(), error: null })
  await refresh()
}

export async function pendingCount(visitId) {
  return (await idb.all('outbox')).filter((x) => !visitId || x.visit_id === visitId).length
}

async function outbox() {
  return (await idb.all('outbox')).sort((a, b) => a.id - b.id)
}

/** Pengirim: memanggil REST API yang sama dengan aplikasi Android. */
async function send(item) {
  const id = item.visit_id
  const p = item.payload
  const form = (fields, blob, name) => {
    const f = new FormData()
    for (const [k, v] of Object.entries(fields)) if (v !== null && v !== undefined) f.append(k, v)
    f.append('file', blob, name)
    return f
  }
  switch (item.kind) {
    case 'start': return api(`/visits/${id}/start`, { method: 'POST', body: p })
    case 'report': return api(`/visits/${id}/report`, { method: 'PUT', body: p })
    case 'attachment':
      return api(`/visits/${id}/attachments`, { method: 'POST', form: form({ id: p.id, owner_type: p.owner_type, owner_id: p.owner_id, caption: p.caption }, p.blob, `${p.id}.jpg`) })
    case 'signature':
      return api(`/visits/${id}/signatures`, { method: 'POST', form: form({ signer_role: p.role, signer_name: p.name || '', signed_at: p.signed_at || '' }, p.blob, `${p.role}.png`) })
    case 'submit': return api(`/visits/${id}/submit`, { method: 'POST' })
    default: throw new ApiError('Jenis antrian tidak dikenal: ' + item.kind, { status: 0 })
  }
}

/** Isi laporan ditolak dengan `report_locked` karena tanda tangan PIC sudah sampai: isi di server sudah versi terakhir. */
const alreadyOnServer = (item, e) => item.kind === 'report' && e.code === 'report_locked'

async function sendOne(item) {
  try {
    await send(item)
    await idb.del('outbox', item.id)
    return null
  } catch (e) {
    if (e instanceof ApiError) {
      if (alreadyOnServer(item, e)) { await idb.del('outbox', item.id); return null }
      return { message: `${label(item)}: ${e.message}`, offline: e.isNetwork }
    }
    if (item.kind === 'attachment' && !item.payload.blob) {
      await idb.del('outbox', item.id) // foto hilang dari penyimpanan: lewati supaya laporan tetap terkirim
      return null
    }
    return { message: `${label(item)}: ${e?.message || e}`, offline: false }
  }
}

let current = null
let again = false

/** Menjalankan pengiriman. Jika sedang berjalan, satu putaran lagi dijadwalkan. */
export function run() {
  if (!getToken()) return Promise.resolve()
  if (current) { again = true; return current }
  current = loop().finally(() => { current = null })
  return current
}

/** Mengirim sekarang dan mengembalikan status kunjungan ini setelahnya. */
export async function flushVisit(visitId) {
  await run()
  return stateOf(visitId)
}

async function loop() {
  sync.running = true
  try {
    do {
      again = false
      sync.lastError = null
      sync.offline = false
      const blocked = new Set()
      for (const item of await outbox()) {
        if (blocked.has(item.visit_id)) continue
        const failure = await sendOne(item)
        if (!failure) continue
        sync.lastError = failure.message
        await idb.put('outbox', { ...item, error: failure.message })
        if (failure.offline) { sync.offline = true; again = false; break }
        blocked.add(item.visit_id)
      }
    } while (again)
  } finally {
    await refresh()
    sync.running = false
  }
}

export async function refresh() {
  const items = await outbox()
  const by = {}
  for (const x of items) (by[x.visit_id] ||= []).push(x)
  sync.pending = items.length
  sync.lastError ??= items.map((x) => x.error).find(Boolean) || null
  sync.visits = Object.fromEntries(Object.entries(by).map(([k, v]) => [k, {
    pending: v.length, error: v.map((x) => x.error).find(Boolean) || null, offline: sync.offline,
  }]))
}

let started = false
export function startSync() {
  if (started) return
  started = true
  refresh().then(run)
  window.addEventListener('online', () => run())
  setInterval(() => { if (sync.pending > 0) run() }, 2 * 60 * 1000)
}
