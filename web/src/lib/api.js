// Klien API sederhana. Token disimpan di localStorage setelah login.
const BASE = import.meta.env.VITE_API_URL || ''

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
  const res = await fetch(BASE + '/api' + path, {
    method,
    headers,
    body: form ?? (body !== undefined ? JSON.stringify(body) : undefined),
  })
  if (res.status === 401 && path !== '/auth/login') {
    setToken(null)
    location.href = '/login'
    return
  }
  if (res.status === 204) return null
  const data = await res.json().catch(() => null)
  if (!res.ok) throw new Error(data?.error || `Gagal (${res.status})`)
  return data
}

// URL file yang butuh token (PDF, foto) untuk dibuka di tab baru atau <img>.
export function fileUrl(path) {
  return `${BASE}/api${path}${path.includes('?') ? '&' : '?'}token=${encodeURIComponent(getToken() || '')}`
}
