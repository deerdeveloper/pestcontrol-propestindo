import { defineStore } from 'pinia'
import { api, setToken, getToken } from '../lib/api'

// Data pengguna disimpan juga di localStorage supaya teknisi tetap bisa membuka aplikasi saat offline.
function cachedUser() {
  try { return JSON.parse(localStorage.getItem('user') || 'null') } catch { return null }
}
function cacheUser(u) {
  try { u ? localStorage.setItem('user', JSON.stringify(u)) : localStorage.removeItem('user') } catch {}
}

export const useAuth = defineStore('auth', {
  state: () => ({ user: null }),
  getters: {
    isStaff: (s) => ['super_admin', 'admin', 'supervisor'].includes(s.user?.role),
    isAdmin: (s) => ['super_admin', 'admin'].includes(s.user?.role),
    isCustomer: (s) => s.user?.role === 'customer',
    isTechnician: (s) => s.user?.role === 'technician',
    home: (s) => ({ customer: '/portal', technician: '/tech' })[s.user?.role] || '/dashboard',
  },
  actions: {
    async login(email, password) {
      const res = await api('/auth/login', { method: 'POST', body: { email, password } })
      setToken(res.token)
      this.user = res.user
      await this.load()
    },
    async load() {
      if (!getToken()) return null
      try {
        this.user = await api('/auth/me')
        cacheUser(this.user)
      } catch (e) {
        // Offline: pakai data login terakhir supaya aplikasi tetap terbuka.
        this.user = e.isNetwork ? cachedUser() : null
      }
      return this.user
    },
    logout() {
      setToken(null)
      cacheUser(null)
      this.user = null
    },
  },
})
