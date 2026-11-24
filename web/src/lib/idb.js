// IndexedDB kecil tanpa dependensi: penyimpanan offline aplikasi teknisi di browser.
//   cache  : data dari server (katalog, jadwal, bundle kunjungan)
//   drafts : isian laporan per kunjungan (termasuk foto & tanda tangan sebagai Blob)
//   outbox : antrian perubahan yang belum terkirim, diproses berurutan (id naik)
import { toRaw } from 'vue'

const DB = 'propestindo-teknisi'
let dbp = null

function open() {
  if (dbp) return dbp
  dbp = new Promise((resolve, reject) => {
    const req = indexedDB.open(DB, 1)
    req.onupgradeneeded = () => {
      const db = req.result
      db.createObjectStore('cache', { keyPath: 'key' })
      db.createObjectStore('drafts', { keyPath: 'visit_id' })
      db.createObjectStore('outbox', { keyPath: 'id', autoIncrement: true })
    }
    req.onsuccess = () => resolve(req.result)
    req.onerror = () => reject(req.error)
  })
  return dbp
}

function wrap(req) {
  return new Promise((resolve, reject) => { req.onsuccess = () => resolve(req.result); req.onerror = () => reject(req.error) })
}

async function store(name, mode = 'readonly') {
  return (await open()).transaction(name, mode).objectStore(name)
}

export const idb = {
  get: async (s, key) => wrap((await store(s)).get(key)),
  all: async (s) => wrap((await store(s)).getAll()),
  put: async (s, value) => wrap((await store(s, 'readwrite')).put(plain(value))),
  add: async (s, value) => wrap((await store(s, 'readwrite')).add(plain(value))),
  del: async (s, key) => wrap((await store(s, 'readwrite')).delete(key)),
  clear: async (s) => wrap((await store(s, 'readwrite')).clear()),
}

/** Salinan polos (tanpa Proxy Vue) supaya bisa disimpan di IndexedDB. Blob/File dibiarkan apa adanya. */
export function plain(v) {
  v = toRaw(v)
  if (v === null || typeof v !== 'object' || v instanceof Blob || v instanceof Date) return v
  if (Array.isArray(v)) return v.map(plain)
  const o = {}
  for (const [k, x] of Object.entries(v)) if (typeof x !== 'function') o[k] = plain(x)
  return o
}
