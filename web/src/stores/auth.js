import { defineStore } from 'pinia'
import { api, setToken, getToken } from '../lib/api'

export const useAuth = defineStore('auth', {
  state: () => ({ user: null }),
  getters: {
    isStaff: (s) => ['super_admin', 'admin', 'supervisor'].includes(s.user?.role),
    isAdmin: (s) => ['super_admin', 'admin'].includes(s.user?.role),
    isCustomer: (s) => s.user?.role === 'customer',
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
      try { this.user = await api('/auth/me') } catch { this.user = null }
      return this.user
    },
    logout() {
      setToken(null)
      this.user = null
    },
  },
})
