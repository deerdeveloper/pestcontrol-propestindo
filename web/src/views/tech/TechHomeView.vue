<script setup>
// Jadwal kunjungan teknisi (PWA). Data di-cache supaya tetap tampil tanpa sinyal.
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuth } from '../../stores/auth'
import { myVisits, prefetch } from '../../lib/tech/repo'
import { sync, stateOf, run } from '../../lib/tech/sync'
import { visitTypes, todayISO } from '../../lib/labels'
import Icon from '../../components/Icon.vue'
import StatusBadge from '../../components/StatusBadge.vue'
import SyncBanner from '../../components/SyncBanner.vue'
import EmptyState from '../../components/EmptyState.vue'

const auth = useAuth()
const router = useRouter()
const visits = ref([])
const error = ref('')
const loading = ref(true)
const installEvt = ref(null)

async function load() {
  loading.value = true
  try {
    visits.value = await myVisits()
    error.value = ''
    prefetch(visits.value)
    run()
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}
onMounted(() => {
  load()
  window.addEventListener('beforeinstallprompt', (e) => { e.preventDefault(); installEvt.value = e })
})
async function install() { await installEvt.value.prompt(); installEvt.value = null }

const today = todayISO()
const todays = computed(() => visits.value.filter((v) => v.scheduled_date === today))
const upcoming = computed(() => visits.value.filter((v) => v.scheduled_date > today))
const earlier = computed(() => visits.value.filter((v) => v.scheduled_date < today))
const revisions = computed(() => visits.value.filter((v) => v.status === 'revision').length)
const doneToday = computed(() => todays.value.filter((v) => ['pending_review', 'published'].includes(v.status)).length)
const sections = computed(() => [['Hari ini', todays.value], ['Mendatang', upcoming.value], ['Sebelumnya', earlier.value]].filter(([, l]) => l.length))
const greeting = (() => { const h = new Date().getHours(); return h < 11 ? 'Selamat pagi' : h < 15 ? 'Selamat siang' : h < 18 ? 'Selamat sore' : 'Selamat malam' })()
const dateParts = (d) => {
  const x = new Date(d + 'T00:00:00')
  return { day: x.getDate(), mon: x.toLocaleDateString('id-ID', { month: 'short' }), wd: x.toLocaleDateString('id-ID', { weekday: 'short' }) }
}
</script>

<template>
  <div>
    <header class="t-hero">
      <div class="row">
        <img src="/emblem.svg" alt="" class="logo" />
        <div class="grow"><small class="hello">{{ greeting }},</small><h1>{{ auth.user.name }}</h1></div>
        <button class="btn icon hero-btn" :disabled="loading" aria-label="Muat ulang" @click="load"><Icon name="refresh" :class="{ spin: loading }" /></button>
      </div>
      <p class="today">{{ new Date().toLocaleDateString('id-ID', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }) }}</p>
    </header>

    <div class="t-body">
      <div class="t-card summary">
        <div><b>{{ todays.length }}</b><span>Hari ini</span></div>
        <div><b>{{ doneToday }}</b><span>Terkirim</span></div>
        <div :class="{ warn: revisions }"><b>{{ revisions }}</b><span>Revisi</span></div>
        <div :class="{ warn: sync.pending }"><b>{{ sync.pending }}</b><span>Antrian</span></div>
      </div>

      <div style="margin-top: 12px" class="stack">
        <SyncBanner />
        <p v-if="error" class="notice red"><Icon name="alert" />{{ error }}</p>
        <div v-if="installEvt" class="t-card install">
          <Icon name="smartphone" /><div class="grow"><b>Pasang di layar utama</b><small>Buka lebih cepat & bisa dipakai offline</small></div>
          <button class="btn gold sm" @click="install">Pasang</button>
        </div>
      </div>

      <template v-for="[title, list] in sections" :key="title">
        <div class="t-section">{{ title }}<span class="n">{{ list.length }}</span></div>
        <button v-for="v in list" :key="v.id" class="t-card visit" :class="v.status" @click="router.push('/tech/visits/' + v.id)">
          <div class="date"><small>{{ dateParts(v.scheduled_date).wd }}</small><b>{{ dateParts(v.scheduled_date).day }}</b><small>{{ dateParts(v.scheduled_date).mon }}</small></div>
          <div class="grow">
            <b class="name">{{ v.customer_name }}</b>
            <span class="site"><Icon name="map-pin" :size="13" />{{ v.site_name }}</span>
            <div class="meta">
              <StatusBadge :status="v.status" />
              <span class="type">{{ visitTypes[v.visit_type] }}</span>
            </div>
            <span v-if="stateOf(v.id).pending" class="unsent" :class="{ bad: stateOf(v.id).error && !stateOf(v.id).offline }">
              <Icon :name="stateOf(v.id).error && !stateOf(v.id).offline ? 'alert' : 'cloud-up'" :size="13" />
              {{ stateOf(v.id).error && !stateOf(v.id).offline ? 'Gagal terkirim' : 'Belum terkirim' }}</span>
          </div>
          <Icon name="chevron-right" class="chev" />
        </button>
      </template>

      <div v-if="!loading && !visits.length && !error" class="t-card" style="margin-top: 16px">
        <EmptyState icon="calendar" title="Belum ada kunjungan" text="Jadwal dari admin akan muncul di sini. Tarik ulang dengan tombol muat ulang." />
      </div>
      <div v-if="loading && !visits.length" class="t-card skeleton" style="margin-top: 16px" />
    </div>
  </div>
</template>

<style scoped>
.logo { width: 40px; height: 40px; background: #fff; border-radius: 12px; padding: 4px; }
.hello { color: #b9d2c1; font-weight: 600; font-size: 13px; }
h1 { font-size: 20px; color: #fff; }
.today { color: #b9d2c1; font-size: 13px; margin-top: 12px; }
.hero-btn { background: rgba(255, 255, 255, .1); border-color: transparent; color: #fff; }
.hero-btn:hover { background: rgba(255, 255, 255, .18); color: #fff; border-color: transparent; }
.summary { display: grid; grid-template-columns: repeat(4, 1fr); padding: 14px 6px; box-shadow: var(--shadow); }
.summary div { text-align: center; border-right: 1px solid var(--line-2); }
.summary div:last-child { border: 0; }
.summary b { display: block; font-size: 22px; font-weight: 800; color: var(--green-800); line-height: 1.2; }
.summary span { font-size: 11.5px; color: var(--muted); font-weight: 700; }
.summary .warn b { color: var(--red); }
.install { display: flex; align-items: center; gap: 12px; padding: 12px 14px; color: var(--green-700); }
.install b { display: block; color: var(--ink); font-size: 14px; }
.install small { color: var(--muted); font-size: 12px; }
.visit { width: 100%; display: flex; align-items: center; gap: 14px; padding: 14px; text-align: left; font: inherit; color: inherit; cursor: pointer; border-left: 4px solid var(--line); }
.visit:active { transform: scale(.99); }
.visit.scheduled { border-left-color: var(--blue); }
.visit.in_progress { border-left-color: var(--amber); }
.visit.revision { border-left-color: var(--red); }
.visit.pending_review { border-left-color: var(--gold); }
.visit.published { border-left-color: var(--green-600); }
.date { width: 52px; flex: none; text-align: center; background: var(--green-50); border-radius: 14px; padding: 6px 0; color: var(--green-800); }
.date b { display: block; font-size: 21px; line-height: 1.1; font-weight: 800; }
.date small { display: block; font-size: 10.5px; font-weight: 800; text-transform: uppercase; color: var(--green-600); }
.name { display: block; font-size: 15.5px; line-height: 1.3; }
.site { display: flex; align-items: center; gap: 4px; font-size: 13px; color: var(--muted); margin-top: 2px; }
.meta { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; margin-top: 8px; }
.type { font-size: 12px; color: var(--muted); font-weight: 600; }
.unsent { display: inline-flex; align-items: center; gap: 4px; font-size: 12px; font-weight: 700; color: var(--amber); margin-top: 6px; }
.unsent.bad { color: var(--red); }
.chev { color: #b7c6bd; }
.skeleton { height: 96px; background: linear-gradient(90deg, #fff, var(--line-2), #fff); background-size: 200% 100%; animation: sk 1.2s infinite; }
@keyframes sk { to { background-position: -200% 0; } }
</style>
