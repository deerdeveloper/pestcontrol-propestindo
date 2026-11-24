<script setup>
// Kerangka halaman admin/supervisor/pelanggan: sidebar di desktop, top bar + bottom nav di HP.
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuth } from '../stores/auth'
import { api } from '../lib/api'
import { roles, initials } from '../lib/labels'
import { confirmDialog } from '../lib/ui'
import Icon from '../components/Icon.vue'

const auth = useAuth()
const route = useRoute()
const router = useRouter()
const open = ref(false)
const pendingReview = ref(0)

const groups = computed(() => {
  if (!auth.user) return []
  if (auth.isCustomer) return [{ items: [
    { to: '/portal', label: 'Laporan & jadwal', icon: 'file-check' },
    { to: '/portal/recommendations', label: 'Rekomendasi', icon: 'lightbulb' },
  ] }]
  const g = [
    { label: 'Operasional', items: [
      { to: '/dashboard', label: 'Dashboard', icon: 'dashboard' },
      { to: '/visits', label: 'Jadwal kunjungan', icon: 'calendar', count: pendingReview.value },
    ] },
    { label: 'Data', items: [
      { to: '/customers', label: 'Pelanggan & lokasi', icon: 'building' },
      { to: '/master', label: 'Data master', icon: 'database' },
    ] },
  ]
  const adm = []
  if (auth.isAdmin) adm.push({ to: '/users', label: 'Pengguna', icon: 'users' })
  if (auth.user.role === 'super_admin') adm.push({ to: '/system', label: 'Sistem & update', icon: 'settings' })
  if (adm.length) g.push({ label: 'Administrasi', items: adm })
  return g
})
const bottom = computed(() => auth.isCustomer
  ? [{ to: '/portal', label: 'Laporan', icon: 'file-check' }, { to: '/portal/recommendations', label: 'Rekomendasi', icon: 'lightbulb' }]
  : [{ to: '/dashboard', label: 'Dashboard', icon: 'dashboard' }, { to: '/visits', label: 'Jadwal', icon: 'calendar' },
     { to: '/customers', label: 'Pelanggan', icon: 'building' }, { to: '/master', label: 'Master', icon: 'database' }])

onMounted(async () => {
  if (auth.isStaff) {
    try { pendingReview.value = (await api('/visits?status=pending_review')).length } catch {}
  }
})

// Penanda menu aktif juga untuk halaman turunan (mis. /visits/123, /master/chemicals).
function active(to) {
  const p = route.path
  return to === '/portal' ? p === to : p === to || p.startsWith(to + '/')
}

async function logout() {
  if (!(await confirmDialog({ title: 'Keluar dari aplikasi?', ok: 'Keluar' }))) return
  auth.logout()
  router.push('/login')
}
</script>

<template>
  <div class="shell">
    <aside class="sidebar" :class="{ open }">
      <router-link :to="auth.home" class="brand" @click="open = false">
        <img src="/emblem.svg" alt="" />
        <span><b>PROPESTINDO</b><small>{{ auth.isCustomer ? 'Portal Pelanggan' : 'Sistem Laporan Kunjungan' }}</small></span>
      </router-link>
      <template v-for="(g, i) in groups" :key="i">
        <div v-if="g.label" class="nav-group">{{ g.label }}</div>
        <nav @click="open = false">
          <router-link v-for="m in g.items" :key="m.to" :to="m.to" active-class="" exact-active-class="" :class="{ 'router-link-active': active(m.to) }">
            <Icon :name="m.icon" />{{ m.label }}<span v-if="m.count" class="count">{{ m.count }}</span>
          </router-link>
        </nav>
      </template>
      <div class="me">
        <div class="avatar">{{ initials(auth.user.name) }}</div>
        <div class="grow"><b>{{ auth.user.name }}</b><small>{{ auth.isCustomer ? auth.user.customer_name : roles[auth.user.role] }}</small></div>
        <button class="btn ghost icon sm" title="Keluar" @click="logout"><Icon name="logout" /></button>
      </div>
    </aside>
    <div v-if="open" class="scrim" @click="open = false" />
    <div class="main">
      <header class="topbar only-sm">
        <router-link :to="auth.home" class="brand dark"><img src="/emblem.svg" alt="" /><span><b>PROPESTINDO</b></span></router-link>
        <span class="spacer" />
        <button class="btn ghost icon" aria-label="Menu" @click="open = true"><Icon name="menu" /></button>
      </header>
      <main class="content"><slot /></main>
    </div>
    <nav class="bottom-nav">
      <router-link v-for="m in bottom" :key="m.to" :to="m.to" active-class="" exact-active-class="" :class="{ 'router-link-active': active(m.to) }"><Icon :name="m.icon" />{{ m.label }}</router-link>
      <button type="button" :class="{ on: open }" @click="open = true"><Icon name="menu" />Lainnya</button>
    </nav>
  </div>
</template>
