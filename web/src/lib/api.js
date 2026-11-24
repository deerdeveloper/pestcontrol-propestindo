// Klien API sederhana. Token disimpan di localStorage setelah login.
const BASE = import.meta.env.VITE_API_URL || ''

/** Error dari API. `status` kosong berarti gagal jaringan (offline), bukan ditolak server. */
export class ApiError extends Error {
  constructor(message, { status = null, code = null } = {}) {
    super(message)
    this.status = status
    this.code = code
  }
  get isNetwork() { return this.status === null }
}

export function getToken() {
  try { return localStorage.getItem('token') } catch { return null }
}

export function setToken(t) {
  try { t ? localStorage.setItem('token', t) : localStorage.removeItem('token') } catch {}
}

export async function api(path, { method = 'GET', body, form } = {}) {
  const headers = {}
  const token = getToken()
  if (token) headers.Authorization = `Bearer ${token}`
  if (body !== undefined) headers['Content-Type'] = 'application/json'
  let res
  try {
    res = await fetch(BASE + '/api' + path, {
      method,
      headers,
      body: form ?? (body !== undefined ? JSON.stringify(body) : undefined),
    })
  } catch {
    throw new ApiError('Tidak ada koneksi ke server')
  }
  if (res.status === 401 && path !== '/auth/login') {
    setToken(null)
    try { localStorage.removeItem('user') } catch {}
    location.href = import.meta.env.BASE_URL + 'login'
    throw new ApiError('Sesi berakhir, silakan masuk lagi', { status: 401 })
  }
  if (res.status === 204) return null
  const data = await res.json().catch(() => null)
  if (!res.ok) {
    const msg = data?.error || ({ 413: 'File terlalu besar untuk server (413)', 502: 'Server sedang tidak bisa dihubungi (502)', 503: 'Server sedang tidak bisa dihubungi (503)', 504: 'Server terlalu lama membalas (504)' })[res.status] || `Gagal (${res.status})`
    throw new ApiError(msg, { status: res.status, code: data?.code || null })
  }
  return data
}

// URL file yang butuh token (PDF, foto) untuk dibuka di tab baru atau <img>.
export function fileUrl(path) {
  return `${BASE}/api${path}${path.includes('?') ? '&' : '?'}token=${encodeURIComponent(getToken() || '')}`
}
