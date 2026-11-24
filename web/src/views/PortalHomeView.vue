<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { api, fileUrl } from '../lib/api'
import { visitTypes, fmtDate } from '../lib/labels'
import { useAuth } from '../stores/auth'
import Icon from '../components/Icon.vue'
import EmptyState from '../components/EmptyState.vue'
const auth = useAuth()
const router = useRouter()
const sites = ref([])
const visits = ref([])
const reports = ref([])
const siteId = ref('')
const loading = ref(true)
async function loadReports() { reports.value = await api('/portal/reports' + (siteId.value ? '?site_id=' + siteId.value : '')) }
onMounted(async () => {
  ;[sites.value, visits.value] = await Promise.all([api('/portal/sites'), api('/portal/visits')])
  await loadReports()
  loading.value = false
})
const openRecs = computed(() => reports.value.reduce((n, r) => n + (r.open_recommendations || 0), 0))
const activeFindings = computed(() => reports.value[0]?.active_findings ?? 0)
</script>

<template>
  <div class="page">
    <div class="page-head">
      <div class="t"><span class="eyebrow">Portal pelanggan</span><h1>{{ auth.user?.customer_name }}</h1><p>Jadwal kunjungan, laporan resmi, dan rekomendasi dari tim Propestindo.</p></div>
    </div>

    <div class="stats">
      <div class="card stat hero"><div class="ic"><Icon name="calendar" /></div><div><b>{{ visits[0] ? fmtDate(visits[0].scheduled_date) : '—' }}</b><span>Kunjungan berikutnya</span></div></div>
      <div class="card stat"><div class="ic"><Icon name="file-check" /></div><div><b>{{ reports.length }}</b><span>Laporan terbit</span></div></div>
      <div class="card stat red"><div class="ic"><Icon name="bug" /></div><div><b>{{ activeFindings }}</b><span>Temuan aktif (laporan terakhir)</span></div></div>
      <router-link to="/portal/recommendations" class="card stat gold"><div class="ic"><Icon name="lightbulb" /></div><div><b>{{ openRecs }}</b><span>Rekomendasi belum dikerjakan</span></div></router-link>
    </div>

    <div class="section-title"><h2>Jadwal kunjungan berikutnya</h2></div>
    <div class="visit-cards">
      <div v-for="v in visits" :key="v.id" class="card vc">
        <div class="date"><b>{{ v.scheduled_date.slice(8) }}</b><small>{{ new Date(v.scheduled_date + 'T00:00:00').toLocaleDateString('id-ID', { month: 'short' }) }}</small></div>
        <div class="grow"><b>{{ v.site_name }}</b><small>{{ visitTypes[v.visit_type] }}</small><small><Icon name="user" :size="13" /> {{ v.technician_name || 'Teknisi belum ditentukan' }}</small></div>
      </div>
      <div v-if="!visits.length && !loading" class="card"><EmptyState icon="calendar" title="Belum ada jadwal kunjungan" /></div>
    </div>

    <div class="section-title"><h2>Laporan kunjungan</h2>
      <select v-if="sites.length > 1" v-model="siteId" style="width: auto" @change="loadReports"><option value="">Semua lokasi</option>
        <option v-for="s in sites" :key="s.id" :value="s.id">{{ s.name }}</option></select>
    </div>
    <div class="table-wrap">
      <table class="table cards">
        <thead><tr><th>No laporan</th><th>Tanggal</th><th>Lokasi</th><th>Temuan aktif</th><th>Rekomendasi terbuka</th><th></th></tr></thead>
        <tbody>
          <tr v-for="r in reports" :key="r.visit_id" class="click" @click="router.push('/visits/' + r.visit_id)">
            <td class="primary"><span class="cell-main">{{ r.report_no }}</span></td>
            <td data-label="Tanggal">{{ fmtDate(r.scheduled_date) }}</td>
            <td data-label="Lokasi">{{ r.site_name }}</td>
            <td data-label="Temuan aktif"><span class="badge" :class="r.active_findings ? 'bad' : 'ok'">{{ r.active_findings }}</span></td>
            <td data-label="Rekomendasi terbuka"><span class="badge" :class="r.open_recommendations ? 'warn' : 'ok'">{{ r.open_recommendations }}</span></td>
            <td class="actions" @click.stop>
              <router-link :to="'/visits/' + r.visit_id" class="btn sm"><Icon name="eye" />Lihat</router-link>
              <a :href="fileUrl(`/visits/${r.visit_id}/pdf`)" target="_blank" class="btn sm primary"><Icon name="download" />PDF</a>
            </td>
          </tr>
          <tr v-if="!reports.length && !loading" class="empty"><td colspan="6"><EmptyState icon="file" title="Belum ada laporan terbit" text="Laporan muncul di sini setelah diperiksa dan diterbitkan admin." /></td></tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<style scoped>
.visit-cards { display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: 12px; }
.visit-cards .card + .card { margin-top: 0; }
.vc { display: flex; gap: 14px; padding: 16px; align-items: center; }
.vc .date { width: 54px; height: 58px; border-radius: 14px; background: var(--green-800); color: #fff; display: grid; place-items: center; align-content: center; flex: none; }
.vc .date b { font-size: 20px; line-height: 1; }
.vc .date small { font-size: 11px; color: var(--gold); font-weight: 700; text-transform: uppercase; }
.vc .grow b { display: block; }
.vc .grow small { display: flex; align-items: center; gap: 4px; color: var(--muted); font-size: 12.5px; }
</style>
