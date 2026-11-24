<script setup>
// Detail kunjungan: staf bisa review, kembalikan untuk revisi, atau terbitkan.
// Pelanggan melihat laporan yang sudah terbit.
import { ref, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { api, fileUrl } from '../lib/api'
import { useAuth } from '../stores/auth'
import { visitTypes } from '../lib/labels'
import ReportView from '../components/ReportView.vue'

const route = useRoute()
const auth = useAuth()
const doc = ref(null)
const technicians = ref([])
const busy = ref(false)
const error = ref('')
const assign = ref({})

async function load() {
  doc.value = await api('/visits/' + route.params.id)
  assign.value = { technician_id: doc.value.visit.technician_id || '', scheduled_date: doc.value.visit.scheduled_date, visit_type: doc.value.visit.visit_type }
}
onMounted(async () => {
  await load()
  if (auth.isStaff) technicians.value = await api('/users?role=technician')
})

async function act(fn) {
  busy.value = true
  error.value = ''
  try { doc.value = await fn() } catch (e) { error.value = e.message } finally { busy.value = false }
}
const publish = () => act(() => api(`/visits/${route.params.id}/publish`, { method: 'POST' }))
function returnForRevision() {
  const notes = prompt('Catatan revisi untuk teknisi:')
  if (notes) act(() => api(`/visits/${route.params.id}/return`, { method: 'POST', body: { notes } }))
}
const saveAssign = () => act(() => api('/visits/' + route.params.id, { method: 'PATCH', body: { ...assign.value, technician_id: assign.value.technician_id || null } }))
function cancelVisit() {
  if (confirm('Batalkan kunjungan ini?')) act(() => api('/visits/' + route.params.id, { method: 'PATCH', body: { status: 'cancelled' } }))
}
</script>

<template>
  <div v-if="doc">
    <div class="page-head">
      <div>
        <router-link :to="auth.isCustomer ? '/portal' : '/visits'" class="muted">← Kembali</router-link>
        <h1>{{ doc.report?.report_no || 'Kunjungan' }} · {{ doc.customer.name }}</h1>
      </div>
      <div class="actions">
        <a v-if="doc.visit.status === 'published'" class="button primary" :href="fileUrl(`/visits/${doc.visit.id}/pdf`)" target="_blank">Unduh PDF</a>
        <template v-if="auth.isStaff">
          <a v-if="doc.report && doc.visit.status !== 'published'" class="button" :href="fileUrl(`/visits/${doc.visit.id}/pdf?preview=1`)" target="_blank">Pratinjau PDF</a>
          <button v-if="doc.visit.status === 'pending_review'" :disabled="busy" @click="returnForRevision">Kembalikan untuk revisi</button>
          <button v-if="doc.visit.status === 'pending_review'" class="primary" :disabled="busy" @click="publish">Terbitkan laporan</button>
        </template>
      </div>
    </div>
    <p v-if="error" class="error">{{ error }}</p>

    <form v-if="auth.isStaff && ['scheduled', 'in_progress'].includes(doc.visit.status)" class="card form" @submit.prevent="saveAssign">
      <h3>Penugasan</h3>
      <div class="grid3">
        <label><span>Teknisi</span><select v-model="assign.technician_id"><option value="">Belum ditugaskan</option>
          <option v-for="t in technicians" :key="t.id" :value="t.id">{{ t.name }}</option></select></label>
        <label><span>Tanggal</span><input type="date" v-model="assign.scheduled_date" /></label>
        <label><span>Tipe</span><select v-model="assign.visit_type"><option v-for="(l, k) in visitTypes" :key="k" :value="k">{{ l }}</option></select></label>
      </div>
      <div class="actions"><button type="button" class="danger" @click="cancelVisit">Batalkan kunjungan</button><button class="primary" :disabled="busy">Simpan</button></div>
    </form>

    <ReportView :doc="doc" />
  </div>
</template>
