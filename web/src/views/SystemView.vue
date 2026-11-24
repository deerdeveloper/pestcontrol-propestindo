<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { api } from '../lib/api'
import { confirmDialog } from '../lib/ui'
import Icon from '../components/Icon.vue'

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
  if (!(await confirmDialog({ title: `Update server ke ${latest.value.tag}?`, message: 'Server akan restart beberapa detik. Pengguna yang sedang membuka aplikasi cukup memuat ulang halaman.', ok: 'Update sekarang' }))) return
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
  <div class="page narrow">
    <div class="page-head"><div class="t"><h1>Sistem & update</h1><p>Versi server dan pembaruan otomatis dari GitHub Releases.</p></div></div>
    <p v-if="error" class="notice red" style="margin-bottom: 16px"><Icon name="alert" />{{ error }}</p>
    <div v-if="data" class="sys">
      <div class="card">
        <div class="card-head"><span class="ic"><Icon name="monitor" /></span><h3>Versi server</h3><span class="badge plain ok">{{ data.build.version }}</span></div>
        <div class="card-body">
          <dl class="kv">
            <dt>Versi berjalan</dt><dd><b>{{ data.build.version }}</b> <small class="muted">{{ data.build.commit }}</small></dd>
            <dt>Waktu build</dt><dd>{{ fmt(data.build.date) }}</dd>
            <dt>Sumber update</dt><dd>{{ up.repo ? 'github.com/' + up.repo : 'belum diatur (UPDATE_REPO)' }}</dd>
            <dt>File binary</dt><dd><code>{{ up.asset }}</code></dd>
            <dt>Cek terakhir</dt><dd>{{ fmt(up.last_check) }}</dd>
          </dl>
          <p v-if="up.last_error && !phase" class="notice" style="margin-top: 14px"><Icon name="alert" />{{ up.last_error }}</p>
        </div>
      </div>

      <div class="card">
        <div class="card-head"><span class="ic"><Icon name="download" /></span><h3>Rilis terbaru</h3>
          <span v-if="latest" class="badge" :class="up.update_available ? 'pending_review' : 'ok'">{{ up.update_available ? 'Versi baru tersedia' : 'Sudah terbaru' }}</span></div>
        <div class="card-body stack">
          <template v-if="latest">
            <p><b>{{ latest.tag }}</b> · {{ fmt(latest.published_at) }} · <a :href="latest.url" target="_blank" rel="noopener">lihat di GitHub</a></p>
            <pre v-if="latest.notes" class="notes">{{ latest.notes }}</pre>
          </template>
          <p v-else class="muted">Belum dicek.</p>

          <div v-if="phase" class="notice blue">
            <Icon :name="phase === 'done' ? 'check-circle' : 'refresh'" :class="{ spin: phase !== 'done' }" />
            <div class="grow">
              <template v-if="phase === 'updating'">
                <p>Mengunduh {{ latest?.tag }}… {{ pct }}% <small v-if="up.total">({{ mb(up.progress) }} / {{ mb(up.total) }})</small></p>
                <div class="bar" style="margin-top: 8px"><i :style="{ width: pct + '%' }" /></div>
              </template>
              <p v-else-if="phase === 'waiting'">Server sedang restart, menunggu hidup kembali…</p>
              <p v-else-if="phase === 'done'"><b>Update berhasil.</b> Halaman dimuat ulang…</p>
            </div>
          </div>

          <div class="row" style="flex-wrap: wrap">
            <button class="btn" :disabled="!!busy || !up.enabled" @click="check"><Icon name="refresh" />{{ busy === 'check' ? 'Mengecek…' : 'Cek update' }}</button>
            <button class="btn primary" :disabled="!!busy || !up.update_available" @click="apply"><Icon name="download" />{{ busy === 'apply' ? 'Memperbarui…' : 'Update sekarang' }}</button>
          </div>
        </div>
      </div>

      <div class="card">
        <div class="card-head"><span class="ic"><Icon name="clock" /></span><h3>Update otomatis</h3></div>
        <div class="card-body stack">
          <label class="check">
            <input type="checkbox" :checked="up.auto" :disabled="!!busy || !up.enabled" @change="setAuto($event.target.checked)" />
            <span>Pasang versi baru secara otomatis</span>
          </label>
          <p class="muted">
            Server mengecek GitHub setiap {{ up.interval }} dan memasang versi baru pada jam {{ up.auto_window }}
            (waktu server). Binary lama disimpan sebagai <code>.bak</code> untuk rollback manual.
          </p>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.sys { display: grid; gap: 16px; }
.sys .card + .card { margin-top: 0; }
.notes { white-space: pre-wrap; background: var(--soft); border: 1px solid var(--line-2); padding: 12px; border-radius: 12px; max-height: 240px; overflow: auto; font-size: 13px; margin: 0; font-family: inherit; }
</style>
