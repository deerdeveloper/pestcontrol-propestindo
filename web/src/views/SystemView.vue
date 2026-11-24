<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { api } from '../lib/api'

const data = ref(null)
const error = ref('')
const busy = ref('')
const phase = ref('') // '' | updating | waiting | done
let timer = null

const up = computed(() => data.value?.updater)
const latest = computed(() => up.value?.latest)
const pct = computed(() => (up.value?.total ? Math.round((up.value.progress / up.value.total) * 100) : 0))

async function load() {
  try { data.value = await api('/system/update'); error.value = '' } catch (e) { error.value = e.message }
}
onMounted(load)
onUnmounted(() => clearTimeout(timer))

async function check() {
  busy.value = 'check'; error.value = ''
  try { data.value = await api('/system/update/check', { method: 'POST' }) } catch (e) { error.value = e.message }
  busy.value = ''
}

async function setAuto(v) {
  busy.value = 'auto'; error.value = ''
  try { data.value = await api('/system/update/settings', { method: 'PUT', body: { auto: v } }) } catch (e) { error.value = e.message; await load() }
  busy.value = ''
}

async function apply() {
  if (!confirm(`Update server ke ${latest.value.tag}? Server akan restart beberapa detik.`)) return
  busy.value = 'apply'; error.value = ''
  const from = data.value.build.version
  try {
    await api('/system/update/apply', { method: 'POST' })
    phase.value = 'updating'
    poll(from)
  } catch (e) { error.value = e.message; busy.value = '' }
}

// Pantau proses: unduh → restart → server hidup lagi dengan versi baru.
function poll(from) {
  timer = setTimeout(async () => {
    try {
      const v = await fetch('/api/version', { cache: 'no-store' }).then((r) => (r.ok ? r.json() : null))
      if (v && v.version !== from) {
        phase.value = 'done'
        setTimeout(() => location.reload(), 2500)
        return
      }
      if (phase.value === 'updating') {
        const s = await api('/system/update')
        data.value = s
        if (s.updater.state === 'idle' && s.updater.last_error) {
          error.value = 'Update gagal: ' + s.updater.last_error
          phase.value = ''; busy.value = ''
          return
        }
        if (s.updater.state === 'restarting') phase.value = 'waiting'
      }
    } catch {
      phase.value = 'waiting' // server sedang restart
    }
    poll(from)
  }, 1500)
}

function fmt(d) { return d ? new Date(d).toLocaleString('id-ID', { dateStyle: 'medium', timeStyle: 'short' }) : '-' }
function mb(n) { return (n / 1048576).toFixed(1) + ' MB' }
</script>

<template>
  <div>
    <h1>Sistem & update</h1>
    <p v-if="error" class="error">{{ error }}</p>
    <div v-if="data" class="sys">
      <div class="card">
        <h3>Versi server</h3>
        <dl class="kv">
          <dt>Versi berjalan</dt><dd><b>{{ data.build.version }}</b> <small class="muted">{{ data.build.commit }}</small></dd>
          <dt>Waktu build</dt><dd>{{ fmt(data.build.date) }}</dd>
          <dt>Sumber update</dt><dd>{{ up.repo ? 'github.com/' + up.repo : 'belum diatur (UPDATE_REPO)' }}</dd>
          <dt>File binary</dt><dd><code>{{ up.asset }}</code></dd>
          <dt>Cek terakhir</dt><dd>{{ fmt(up.last_check) }}</dd>
        </dl>
        <p v-if="up.last_error && !phase" class="warn">{{ up.last_error }}</p>
      </div>

      <div class="card">
        <h3>Rilis terbaru</h3>
        <template v-if="latest">
          <p>
            <b>{{ latest.tag }}</b> · {{ fmt(latest.published_at) }} ·
            <a :href="latest.url" target="_blank" rel="noopener">lihat di GitHub</a>
          </p>
          <p v-if="up.update_available" class="badge scheduled">Versi baru tersedia</p>
          <p v-else class="badge published">Server sudah versi terbaru</p>
          <pre v-if="latest.notes" class="notes">{{ latest.notes }}</pre>
        </template>
        <p v-else class="muted">Belum dicek.</p>

        <div v-if="phase" class="progress-box">
          <template v-if="phase === 'updating'">
            <p>Mengunduh {{ latest?.tag }}… {{ pct }}% <small class="muted" v-if="up.total">({{ mb(up.progress) }} / {{ mb(up.total) }})</small></p>
            <div class="bar"><i :style="{ width: pct + '%' }" /></div>
          </template>
          <p v-else-if="phase === 'waiting'">Server sedang restart, menunggu hidup kembali…</p>
          <p v-else-if="phase === 'done'"><b>Update berhasil.</b> Halaman dimuat ulang…</p>
        </div>

        <div class="toolbar">
          <button :disabled="!!busy || !up.enabled" @click="check">{{ busy === 'check' ? 'Mengecek…' : 'Cek update' }}</button>
          <button class="primary" :disabled="!!busy || !up.update_available" @click="apply">
            {{ busy === 'apply' ? 'Memperbarui…' : 'Update sekarang' }}
          </button>
        </div>
      </div>

      <div class="card">
        <h3>Update otomatis</h3>
        <label class="row">
          <input type="checkbox" class="check" :checked="up.auto" :disabled="!!busy || !up.enabled" @change="setAuto($event.target.checked)" />
          <span>Pasang versi baru secara otomatis</span>
        </label>
        <p class="muted">
          Server mengecek GitHub setiap {{ up.interval }} dan memasang versi baru pada jam {{ up.auto_window }}
          (waktu server). Binary lama disimpan sebagai <code>.bak</code> untuk rollback manual.
        </p>
      </div>
    </div>
  </div>
</template>

<style scoped>
.sys { display: grid; gap: 14px; max-width: 760px; }
.kv { display: grid; grid-template-columns: 140px 1fr; gap: 6px 12px; margin: 0; }
.kv dt { color: var(--muted); }
.kv dd { margin: 0; }
.notes { white-space: pre-wrap; background: var(--bg); padding: 10px; border-radius: 6px; max-height: 240px; overflow: auto; font-size: 13px; }
.row { flex-direction: row; align-items: center; gap: 8px; }
.bar { height: 8px; background: var(--line); border-radius: 4px; overflow: hidden; }
.bar i { display: block; height: 100%; background: var(--green-2); transition: width .3s; }
.progress-box { margin: 10px 0; }
h3 { margin-top: 0; }
@media (max-width: 600px) { .kv { grid-template-columns: 1fr; } .kv dd { margin-bottom: 6px; } }
</style>
