<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuth } from '../../stores/auth'
import { api } from '../../lib/api'
import { sync, run, pendingCount, label } from '../../lib/tech/sync'
import { clearAll } from '../../lib/tech/repo'
import { idb } from '../../lib/idb'
import { initials } from '../../lib/labels'
import { confirmDialog, toast } from '../../lib/ui'
import Icon from '../../components/Icon.vue'
import SyncBanner from '../../components/SyncBanner.vue'

const auth = useAuth()
const router = useRouter()
const apk = ref(null)
const queue = ref([])
async function loadQueue() { queue.value = (await idb.all('outbox')).sort((a, b) => a.id - b.id) }
onMounted(async () => {
  loadQueue()
  try { apk.value = await api('/app/android') } catch {}
})
async function sendNow() { await run(); await loadQueue(); toast(sync.pending ? 'Sebagian data belum terkirim' : 'Semua data terkirim', sync.pending ? 'error' : 'ok') }
async function logout() {
  const n = await pendingCount()
  const ok = await confirmDialog(n
    ? { title: 'Masih ada data belum terkirim', message: `${n} data laporan belum sampai ke server. Jika keluar sekarang, data itu akan hilang dari HP ini.`, ok: 'Tetap keluar', danger: true }
    : { title: 'Keluar dari aplikasi?', message: 'Data offline di HP ini akan dihapus.', ok: 'Keluar' })
  if (!ok) return
  await clearAll()
  auth.logout()
  router.replace('/login')
}
</script>

<template>
  <div>
    <header class="t-hero" style="padding-bottom: 70px">
      <div class="row">
        <div class="avatar big">{{ initials(auth.user.name) }}</div>
        <div class="grow"><h1>{{ auth.user.name }}</h1><small>{{ auth.user.email }}</small></div>
      </div>
    </header>
    <div class="t-body stack">
      <div class="t-card pad-c">
        <div class="row"><Icon :name="sync.pending ? 'cloud-up' : 'cloud-check'" /><b class="grow">Sinkronisasi data</b>
          <button class="btn sm" :disabled="sync.running" @click="sendNow"><Icon name="refresh" :class="{ spin: sync.running }" />Kirim</button></div>
        <p class="muted small" style="margin-top: 6px">{{ sync.pending ? `${sync.pending} data menunggu dikirim ke server.` : 'Semua data sudah terkirim ke server.' }}</p>
        <ul v-if="queue.length" class="queue">
          <li v-for="q in queue" :key="q.id"><Icon :name="q.error ? 'alert' : 'clock'" :size="14" /><span class="grow">{{ label(q) }}<small v-if="q.error">{{ q.error }}</small></span></li>
        </ul>
      </div>
      <SyncBanner />
      <div class="t-card menu">
        <a v-if="apk?.download_url" :href="apk.download_url"><Icon name="download" /><span class="grow">Unduh aplikasi Android<small>Versi {{ apk.version }} · lebih andal untuk kamera & offline</small></span><Icon name="chevron-right" /></a>
        <a href="/" target="_blank"><Icon name="home" /><span class="grow">Situs Propestindo</span><Icon name="chevron-right" /></a>
        <button @click="logout"><Icon name="logout" /><span class="grow danger">Keluar</span></button>
      </div>
      <p class="muted small" style="text-align: center">Propestindo Teknisi · aplikasi web</p>
    </div>
  </div>
</template>

<style scoped>
.avatar.big { width: 52px; height: 52px; font-size: 18px; }
h1 { font-size: 19px; color: #fff; }
small { color: #b9d2c1; }
.pad-c { padding: 16px; box-shadow: var(--shadow); }
.pad-c small, .menu small { color: var(--muted); }
.queue { list-style: none; padding: 0; margin: 10px 0 0; border-top: 1px solid var(--line-2); }
.queue li { display: flex; gap: 8px; align-items: flex-start; padding: 8px 0; font-size: 13px; font-weight: 600; border-bottom: 1px solid var(--line-2); }
.queue li svg { margin-top: 3px; color: var(--muted); }
.queue small { display: block; color: var(--red) !important; font-weight: 500; }
.menu { overflow: hidden; }
.menu a, .menu button { display: flex; align-items: center; gap: 12px; width: 100%; padding: 15px 16px; border: 0; background: none; font: inherit; font-weight: 700; color: var(--ink); text-align: left; cursor: pointer; border-bottom: 1px solid var(--line-2); }
.menu > :last-child { border-bottom: 0; }
.menu svg { color: var(--green-700); }
.menu small { display: block; font-weight: 500; font-size: 12px; }
</style>
