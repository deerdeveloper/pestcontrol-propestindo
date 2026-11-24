<script setup>
import { ref, reactive, onMounted } from 'vue'
import { api } from '../lib/api'
import { visitTypes, visitStatus, fmtDate } from '../lib/labels'

const visits = ref([])
const sites = ref([])
const customers = ref([])
const technicians = ref([])
const filter = reactive({ from: '', to: '', status: '', technician_id: '' })
const form = ref(null)
const error = ref('')

async function load() {
  const p = new URLSearchParams(Object.entries(filter).filter(([, v]) => v))
  visits.value = await api('/visits?' + p)
}
onMounted(async () => {
  const d = new Date()
  filter.from = new Date(d.getFullYear(), d.getMonth(), 1).toISOString().slice(0, 10)
  ;[sites.value, customers.value, technicians.value] = await Promise.all([
    api('/master/sites'), api('/master/customers'), api('/users?role=technician'),
  ])
  await load()
})
const siteLabel = (s) => `${customers.value.find((c) => c.id === s.customer_id)?.name || ''} — ${s.name}`

function startNew() {
  form.value = { site_id: '', technician_id: '', visit_type: 'routine_monthly', scheduled_date: new Date().toISOString().slice(0, 10), notes: '' }
  error.value = ''
}
async function save() {
  error.value = ''
  try {
    const body = { ...form.value, technician_id: form.value.technician_id || null }
    await api('/visits', { method: 'POST', body })
    form.value = null
    await load()
  } catch (e) { error.value = e.message }
}
</script>

<template>
  <div>
    <h1>Jadwal kunjungan</h1>
    <div class="toolbar">
      <label>Dari <input type="date" v-model="filter.from" @change="load" /></label>
      <label>Sampai <input type="date" v-model="filter.to" @change="load" /></label>
      <select v-model="filter.status" @change="load">
        <option value="">Semua status</option>
        <option v-for="(l, k) in visitStatus" :key="k" :value="k">{{ l }}</option>
      </select>
      <select v-model="filter.technician_id" @change="load">
        <option value="">Semua teknisi</option>
        <option v-for="t in technicians" :key="t.id" :value="t.id">{{ t.name }}</option>
      </select>
      <button class="primary" @click="startNew">+ Jadwalkan kunjungan</button>
    </div>

    <form v-if="form" class="card form" @submit.prevent="save">
      <h3>Kunjungan baru</h3>
      <div class="grid2">
        <label><span>Lokasi *</span>
          <select v-model="form.site_id" required><option v-for="s in sites" :key="s.id" :value="s.id">{{ siteLabel(s) }}</option></select></label>
        <label><span>Teknisi</span>
          <select v-model="form.technician_id"><option value="">Belum ditugaskan</option>
            <option v-for="t in technicians" :key="t.id" :value="t.id">{{ t.name }}</option></select></label>
        <label><span>Tipe *</span>
          <select v-model="form.visit_type"><option v-for="(l, k) in visitTypes" :key="k" :value="k">{{ l }}</option></select></label>
        <label><span>Tanggal *</span><input type="date" v-model="form.scheduled_date" required /></label>
        <label class="full"><span>Catatan untuk teknisi</span><input v-model="form.notes" /></label>
      </div>
      <p v-if="error" class="error">{{ error }}</p>
      <div class="actions"><button type="button" @click="form = null">Batal</button><button class="primary">Simpan</button></div>
    </form>

    <table class="table">
      <thead><tr><th>Tanggal</th><th>Pelanggan</th><th>Lokasi</th><th>Tipe</th><th>Teknisi</th><th>Status</th><th>No laporan</th></tr></thead>
      <tbody>
        <tr v-for="v in visits" :key="v.id">
          <td>{{ fmtDate(v.scheduled_date) }}</td>
          <td><router-link :to="'/visits/' + v.id">{{ v.customer_name }}</router-link></td>
          <td>{{ v.site_name }}</td><td>{{ visitTypes[v.visit_type] }}</td><td>{{ v.technician_name || '-' }}</td>
          <td><span :class="['badge', v.status]">{{ visitStatus[v.status] }}</span></td><td>{{ v.report_no || '-' }}</td>
        </tr>
        <tr v-if="!visits.length"><td colspan="7" class="muted">Tidak ada kunjungan.</td></tr>
      </tbody>
    </table>
  </div>
</template>
