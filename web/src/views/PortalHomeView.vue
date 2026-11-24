<script setup>
import { ref, onMounted } from 'vue'
import { api, fileUrl } from '../lib/api'
import { visitTypes, fmtDate } from '../lib/labels'
import { useAuth } from '../stores/auth'
const auth = useAuth()
const sites = ref([])
const visits = ref([])
const reports = ref([])
const siteId = ref('')
async function loadReports() { reports.value = await api('/portal/reports' + (siteId.value ? '?site_id=' + siteId.value : '')) }
onMounted(async () => {
  ;[sites.value, visits.value] = await Promise.all([api('/portal/sites'), api('/portal/visits')])
  await loadReports()
})
</script>

<template>
  <div>
    <h1>{{ auth.user?.customer_name }}</h1>
    <h2>Kunjungan berikutnya</h2>
    <div class="cards">
      <div v-for="v in visits" :key="v.id" class="card">
        <b>{{ fmtDate(v.scheduled_date) }}</b><br />{{ v.site_name }}<br />
        <small class="muted">{{ visitTypes[v.visit_type] }} · {{ v.technician_name || 'Teknisi belum ditentukan' }}</small>
      </div>
      <p v-if="!visits.length" class="muted">Belum ada jadwal kunjungan.</p>
    </div>

    <h2>Laporan kunjungan</h2>
    <div class="toolbar" v-if="sites.length > 1">
      <select v-model="siteId" @change="loadReports"><option value="">Semua lokasi</option>
        <option v-for="s in sites" :key="s.id" :value="s.id">{{ s.name }}</option></select>
    </div>
    <table class="table">
      <thead><tr><th>Tanggal</th><th>No laporan</th><th>Lokasi</th><th>Temuan aktif</th><th>Rekomendasi terbuka</th><th></th></tr></thead>
      <tbody>
        <tr v-for="r in reports" :key="r.visit_id">
          <td>{{ fmtDate(r.scheduled_date) }}</td>
          <td><router-link :to="'/visits/' + r.visit_id">{{ r.report_no }}</router-link></td>
          <td>{{ r.site_name }}</td><td>{{ r.active_findings }}</td><td>{{ r.open_recommendations }}</td>
          <td><a :href="fileUrl(`/visits/${r.visit_id}/pdf`)" target="_blank">PDF</a></td>
        </tr>
        <tr v-if="!reports.length"><td colspan="6" class="muted">Belum ada laporan terbit.</td></tr>
      </tbody>
    </table>
  </div>
</template>
