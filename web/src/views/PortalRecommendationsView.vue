<script setup>
import { ref, onMounted } from 'vue'
import { api } from '../lib/api'
import { categories, fmtDate } from '../lib/labels'
import { promptDialog, toast } from '../lib/ui'
import Icon from '../components/Icon.vue'
import EmptyState from '../components/EmptyState.vue'
const status = ref('open')
const items = ref([])
const loading = ref(true)
async function load() { items.value = await api('/portal/recommendations' + (status.value ? '?status=' + status.value : '')); loading.value = false }
onMounted(load)
async function mark(r, s) {
  let note = null
  if (s === 'done') {
    note = await promptDialog({ title: 'Tandai sudah dikerjakan', message: r.recommendation, label: 'Catatan tindak lanjut (opsional)', value: r.customer_note || '', ok: 'Tandai selesai' })
    if (note === null) return
  }
  await api('/portal/recommendations/' + r.id, { method: 'PATCH', body: { customer_status: s, customer_note: note } })
  toast(s === 'done' ? 'Rekomendasi ditandai selesai' : 'Rekomendasi dibuka lagi')
  await load()
}
const catIcon = { exclusion: 'lock', sanitation: 'sun', storage: 'layers', habitual: 'users' }
</script>

<template>
  <div class="page narrow">
    <div class="page-head"><div class="t"><h1>Rekomendasi</h1><p>Saran dari teknisi untuk mencegah hama datang lagi. Tandai yang sudah dikerjakan.</p></div></div>
    <div class="tabs">
      <button :class="{ active: status === 'open' }" @click="status = 'open'; load()">Belum dikerjakan</button>
      <button :class="{ active: status === 'done' }" @click="status = 'done'; load()">Sudah dikerjakan</button>
      <button :class="{ active: status === '' }" @click="status = ''; load()">Semua</button>
    </div>
    <div class="stack">
      <div v-for="r in items" :key="r.id" class="card rec">
        <div class="ic"><Icon :name="catIcon[r.category] || 'lightbulb'" /></div>
        <div class="grow">
          <div class="row" style="flex-wrap: wrap; gap: 6px"><span class="badge plain">{{ categories[r.category] }}</span>
            <span class="muted small">{{ r.site_name }} · {{ fmtDate(r.visit_date) }} · {{ r.report_no }}</span></div>
          <p class="risk">{{ r.risk_finding }}</p>
          <p class="reco"><Icon name="arrow-right" :size="15" />{{ r.recommendation }}</p>
          <p v-if="r.customer_note" class="muted small">Catatan Anda: {{ r.customer_note }}</p>
        </div>
        <div class="act">
          <button v-if="r.customer_status === 'open'" class="btn primary sm" @click="mark(r, 'done')"><Icon name="check" />Sudah dikerjakan</button>
          <button v-else class="btn sm" @click="mark(r, 'open')"><Icon name="undo" />Buka lagi</button>
        </div>
      </div>
      <div v-if="!items.length && !loading" class="card"><EmptyState icon="check-circle" title="Tidak ada rekomendasi" :text="status === 'open' ? 'Semua rekomendasi sudah ditindaklanjuti.' : ''" /></div>
    </div>
  </div>
</template>

<style scoped>
.rec { display: flex; gap: 14px; padding: 16px 18px; align-items: flex-start; }
.stack .card + .card { margin-top: 0; }
.rec .ic { width: 40px; height: 40px; border-radius: 12px; display: grid; place-items: center; background: var(--gold-50); color: var(--gold-600); flex: none; }
.rec .risk { margin-top: 8px; color: var(--ink-2); }
.rec .reco { margin-top: 4px; font-weight: 700; display: flex; gap: 6px; align-items: flex-start; }
.rec .reco svg { margin-top: 3px; color: var(--green-600); }
@media (max-width: 720px) { .rec { flex-wrap: wrap; } .rec .act { width: 100%; } .rec .act .btn { width: 100%; } }
</style>
