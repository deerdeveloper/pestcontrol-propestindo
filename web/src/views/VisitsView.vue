<script setup>
import { ref, reactive, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { api } from '../lib/api'
import { visitTypes, visitStatus, fmtDate, todayISO } from '../lib/labels'
import { toast } from '../lib/ui'
import Icon from '../components/Icon.vue'
import Modal from '../components/Modal.vue'
import StatusBadge from '../components/StatusBadge.vue'
import EmptyState from '../components/EmptyState.vue'

const route = useRoute()
const router = useRouter()
const visits = ref([])
const sites = ref([])
const customers = ref([])
const technicians = ref([])
const filter = reactive({ from: '', to: '', status: route.query.status || '', technician_id: '' })
const q = ref('')
const form = ref(null)
const error = ref('')
const busy = ref(false)
const loading = ref(true)

async function load() {
  const p = new URLSearchParams(Object.entries(filter).filter(([, v]) => v))
  visits.value = await api('/visits?' + p)
  loading.value = false
}
onMounted(async () => {
  // Status "menunggu review" ditampilkan semua tanggal; selain itu mulai awal bulan ini.
  if (!filter.status) filter.from = todayISO().slice(0, 8) + '01'
  ;[sites.value, customers.value, technicians.value] = await Promise.all([
    api('/master/sites'), api('/master/customers'), api('/users?role=technician'),
  ])
  await load()
  if (route.query.new) { startNew(); router.replace({ query: {} }) }
})
const siteLabel = (s) => `${customers.value.find((c) => c.id === s.customer_id)?.name || ''} — ${s.name}`
const shown = computed(() => {
  const s = q.value.trim().toLowerCase()
  if (!s) return visits.value
  return visits.value.filter((v) => [v.customer_name, v.site_name, v.technician_name, v.report_no].some((x) => (x || '').toLowerCase().includes(s)))
})
const counts = computed(() => {
  const c = {}
  for (const v of visits.value) c[v.status] = (c[v.status] || 0) + 1
  return c
})

function startNew() {
  form.value = { site_id: '', technician_id: '', visit_type: 'routine_monthly', scheduled_date: todayISO(), notes: '' }
  error.value = ''
}
async function save() {
  error.value = ''
  busy.value = true
  try {
    const body = { ...form.value, technician_id: form.value.technician_id || null }
    await api('/visits', { method: 'POST', body })
    form.value = null
    toast('Kunjungan dijadwalkan')
    await load()
  } catch (e) { error.value = e.message } finally { busy.value = false }
}
function resetFilter() {
  Object.assign(filter, { from: '', to: '', status: '', technician_id: '' })
  load()
}
</script>

<template>
  <div class="page">
    <div class="page-head">
      <div class="t"><h1>Jadwal kunjungan</h1><p>Atur penugasan teknisi dan pantau status laporan.</p></div>
      <div class="actions"><button class="btn primary" @click="startNew"><Icon name="plus" />Jadwalkan kunjungan</button></div>
    </div>

    <div class="tabs">
      <button :class="{ active: !filter.status }" @click="filter.status = ''; load()">Semua</button>
      <button v-for="(l, k) in visitStatus" :key="k" :class="{ active: filter.status === k }" @click="filter.status = k; load()">
        {{ l }}<span v-if="!filter.status && counts[k]" class="count">{{ counts[k] }}</span>
      </button>
    </div>

    <div class="toolbar">
      <div class="search-box"><Icon name="search" /><input v-model="q" placeholder="Cari pelanggan, lokasi, teknisi, no laporan…" /></div>
      <input type="date" v-model="filter.from" title="Dari tanggal" @change="load" />
      <input type="date" v-model="filter.to" title="Sampai tanggal" @change="load" />
      <select v-model="filter.technician_id" @change="load">
        <option value="">Semua teknisi</option>
        <option v-for="t in technicians" :key="t.id" :value="t.id">{{ t.name }}</option>
      </select>
      <button v-if="filter.from || filter.to || filter.technician_id || filter.status" class="btn ghost sm" @click="resetFilter"><Icon name="x" />Reset</button>
    </div>

    <div class="table-wrap">
      <table class="table cards">
        <thead><tr><th>Tanggal</th><th>Pelanggan / lokasi</th><th>Tipe</th><th>Teknisi</th><th>Status</th><th>No laporan</th><th></th></tr></thead>
        <tbody>
          <tr v-for="v in shown" :key="v.id" class="click" @click="router.push('/visits/' + v.id)">
            <td data-label="Tanggal" class="nowrap"><b>{{ fmtDate(v.scheduled_date) }}</b></td>
            <td class="primary"><span class="cell-main">{{ v.customer_name }}</span><span class="cell-sub">{{ v.site_name }}</span></td>
            <td data-label="Tipe">{{ visitTypes[v.visit_type] }}</td>
            <td data-label="Teknisi">{{ v.technician_name || '—' }}</td>
            <td data-label="Status"><StatusBadge :status="v.status" /></td>
            <td data-label="No laporan">{{ v.report_no || '—' }}</td>
            <td class="actions hide-sm"><Icon name="chevron-right" /></td>
          </tr>
          <tr v-if="!shown.length && !loading" class="empty"><td colspan="7">
            <EmptyState icon="calendar" title="Tidak ada kunjungan" text="Ubah filter atau jadwalkan kunjungan baru." />
          </td></tr>
        </tbody>
      </table>
    </div>

    <Modal v-if="form" title="Jadwalkan kunjungan" @close="form = null">
      <form id="visit-form" class="form-grid" @submit.prevent="save">
        <label class="field full"><span>Lokasi <b>*</b></span>
          <select v-model="form.site_id" required><option value="" disabled>Pilih pelanggan & lokasi</option>
            <option v-for="s in sites" :key="s.id" :value="s.id">{{ siteLabel(s) }}</option></select></label>
        <label class="field"><span>Tanggal <b>*</b></span><input type="date" v-model="form.scheduled_date" required /></label>
        <label class="field"><span>Tipe <b>*</b></span>
          <select v-model="form.visit_type"><option v-for="(l, k) in visitTypes" :key="k" :value="k">{{ l }}</option></select></label>
        <label class="field full"><span>Teknisi</span>
          <select v-model="form.technician_id"><option value="">Belum ditugaskan</option>
            <option v-for="t in technicians" :key="t.id" :value="t.id">{{ t.name }}{{ t.technician_code ? ' (' + t.technician_code + ')' : '' }}</option></select></label>
        <label class="field full"><span>Catatan untuk teknisi</span><textarea v-model="form.notes" rows="2" placeholder="Mis. fokus area gudang, bawa umpan tambahan" /></label>
        <p v-if="error" class="notice red full"><Icon name="alert" />{{ error }}</p>
      </form>
      <template #foot>
        <button type="button" class="btn" @click="form = null">Batal</button>
        <button form="visit-form" class="btn primary" :disabled="busy">Simpan jadwal</button>
      </template>
    </Modal>
  </div>
</template>
