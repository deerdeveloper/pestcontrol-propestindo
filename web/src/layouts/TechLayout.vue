<script setup>
// Kerangka aplikasi teknisi (PWA): tampilan HP, bottom nav, sinkronisasi offline jalan di latar belakang.
import { ref, onMounted, onUnmounted } from 'vue'
import { useRoute } from 'vue-router'
import { sync, startSync } from '../lib/tech/sync'
import Icon from '../components/Icon.vue'
const route = useRoute()
const online = ref(navigator.onLine)
const upd = () => { online.value = navigator.onLine }
onMounted(() => { startSync(); addEventListener('online', upd); addEventListener('offline', upd) })
onUnmounted(() => { removeEventListener('online', upd); removeEventListener('offline', upd) })
</script>

<template>
  <div class="tech" :class="{ full: route.meta.full }">
    <div v-if="!online" class="offline-bar"><Icon name="cloud-off" :size="15" />Offline: isian tetap tersimpan di HP dan terkirim otomatis saat ada sinyal</div>
    <slot />
    <nav v-if="!route.meta.full" class="tech-nav">
      <router-link to="/tech" exact-active-class="on" active-class=""><Icon name="calendar" />Jadwal</router-link>
      <router-link to="/tech/account" class="" active-class="on">
        <Icon :name="sync.pending ? 'cloud-up' : 'user'" />Akun<span v-if="sync.pending" class="dot">{{ sync.pending }}</span></router-link>
    </nav>
  </div>
</template>

<style>
/* Gaya bersama layar teknisi */
.tech { min-height: 100vh; min-height: 100dvh; max-width: 640px; margin: 0 auto; background: var(--bg); position: relative; padding-bottom: calc(72px + var(--safe-b)); }
.tech.full { padding-bottom: calc(88px + var(--safe-b)); }
@media (min-width: 680px) { body:has(.tech) { background: #dfe7e2; } .tech { box-shadow: 0 0 0 1px var(--line), var(--shadow-lg); } }
.offline-bar { position: sticky; top: 0; z-index: 25; display: flex; align-items: center; gap: 8px; justify-content: center; padding: 7px 12px; background: var(--green-950); color: #fff; font-size: 12px; font-weight: 600; text-align: center; }
.offline-bar svg { color: var(--gold); flex: none; }
.tech-nav { position: fixed; z-index: 30; bottom: 0; left: 50%; transform: translateX(-50%); width: 100%; max-width: 640px; display: flex;
  height: calc(64px + var(--safe-b)); padding-bottom: var(--safe-b); background: rgba(255, 255, 255, .96); backdrop-filter: blur(12px); -webkit-backdrop-filter: blur(12px); border-top: 1px solid var(--line); }
.tech-nav a { flex: 1; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 3px; font-size: 11.5px; font-weight: 700; color: var(--muted); position: relative; }
.tech-nav a svg { width: 22px; height: 22px; }
.tech-nav a.on { color: var(--green-700); }
.tech-nav a.on::before { content: ''; position: absolute; top: 0; width: 32px; height: 3px; border-radius: 0 0 4px 4px; background: var(--gold); }
.tech-nav .dot { position: absolute; top: 6px; left: calc(50% + 6px); min-width: 18px; height: 18px; padding: 0 5px; border-radius: 99px; background: var(--red); color: #fff; font-size: 10.5px; display: grid; place-items: center; }
.t-hero { background: linear-gradient(160deg, var(--green-900), var(--green-950) 70%); color: #fff; padding: 18px 18px 64px; position: relative; overflow: hidden; }
.t-hero::before { content: ''; position: absolute; inset: 0; background: radial-gradient(420px 240px at 100% 0%, rgba(31, 166, 74, .35), transparent 60%), radial-gradient(300px 200px at 0% 100%, rgba(226, 178, 43, .18), transparent 60%); }
.t-hero > * { position: relative; }
.t-body { padding: 0 14px; margin-top: -46px; position: relative; }
.t-section { font-size: 12px; font-weight: 800; letter-spacing: .1em; text-transform: uppercase; color: var(--muted); margin: 22px 4px 10px; display: flex; align-items: center; gap: 8px; }
.t-section .n { background: var(--line); color: var(--ink-2); border-radius: 99px; padding: 0 8px; letter-spacing: 0; }
.t-card { background: #fff; border: 1px solid var(--line); border-radius: 18px; box-shadow: var(--shadow-sm); }
.t-card + .t-card { margin-top: 10px; }
</style>
