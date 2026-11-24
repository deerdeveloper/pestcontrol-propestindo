<script setup>
import { ref, computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuth } from './stores/auth'
import { roles } from './lib/labels'
const auth = useAuth()
const route = useRoute()
const router = useRouter()
const open = ref(false)
const menu = computed(() => {
  if (!auth.user) return []
  if (auth.isCustomer) return [
    { to: '/portal', label: 'Laporan & jadwal' },
    { to: '/portal/recommendations', label: 'Rekomendasi' },
  ]
  const m = [
    { to: '/dashboard', label: 'Dashboard' },
    { to: '/visits', label: 'Jadwal kunjungan' },
    { to: '/customers', label: 'Pelanggan & lokasi' },
    { to: '/master', label: 'Data master' },
  ]
  if (auth.isAdmin) m.push({ to: '/users', label: 'Pengguna' })
  if (auth.user.role === 'super_admin') m.push({ to: '/system', label: 'Sistem & update' })
  return m
})
function logout() { auth.logout(); router.push('/login') }
</script>

<template>
  <router-view v-if="route.meta.public" />
  <div v-else-if="auth.user" class="shell">
    <aside :class="{ open }">
      <img src="/logo.png" alt="Propestindo" class="brand" />
      <nav @click="open = false">
        <router-link v-for="m in menu" :key="m.to" :to="m.to">{{ m.label }}</router-link>
      </nav>
      <div class="me">
        <b>{{ auth.user.name }}</b><small>{{ roles[auth.user.role] }}</small>
        <button @click="logout">Keluar</button>
      </div>
    </aside>
    <main>
      <button class="menu-btn" @click="open = !open">☰ Menu</button>
      <router-view :key="route.fullPath" />
    </main>
  </div>
</template>
