<script setup>
// Detail kunjungan: staf bisa review, kembalikan untuk revisi, atau terbitkan.
// Pelanggan melihat laporan yang sudah terbit.
import { ref, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { api, fileUrl } from '../lib/api'
import { useAuth } from '../stores/auth'
import { visitTypes, fmtDate, fmtTime } from '../lib/labels'
import { confirmDialog, promptDialog, toast } from '../lib/ui'
import ReportView from '../components/ReportView.vue'
import StatusBadge from '../components/StatusBadge.vue'
import Icon from '../components/Icon.vue'

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

async function act(fn, ok) {
  busy.value = true
  error.value = ''
  try { doc.value = await fn(); if (ok) toast(ok) } catch (e) { error.value = e.message } finally { busy.value = false }
}
async function publish() {
  if (!(await confirmDialog({ title: 'Terbitkan laporan?', message: 'PDF laporan dibuat dan pelanggan bisa melihatnya di portal.', ok: 'Terbitkan' }))) return
  act(() => api(`/visits/${route.params.id}/publish`, { method: 'POST' }), 'Laporan diterbitkan')
}
async function returnForRevision() {
  const notes = await promptDialog({ title: 'Kembalikan untuk revisi', message: 'Teknisi akan melihat catatan ini di aplikasinya.', label: 'Catatan revisi', required: true, ok: 'Kembalikan', placeholder: 'Mis. foto temuan di gudang kurang jelas' })
  if (notes) act(() => api(`/visits/${route.params.id}/return`, { method: 'POST', body: { notes } }), 'Laporan dikembalikan ke teknisi')
}
const saveAssign = () => act(() => api('/visits/' + route.params.id, { method: 'PATCH', body: { ...assign.value, technician_id: assign.value.technician_id || null } }), 'Penugasan disimpan')
async function cancelVisit() {
  if (await confirmDialog({ title: 'Batalkan kunjungan ini?', message: 'Kunjungan tidak akan muncul lagi di aplikasi teknisi.', ok: 'Batalkan kunjungan', cancel: 'Kembali', danger: true }))
    act(() => api('/visits/' + route.params.id, { method: 'PATCH', body: { status: 'cancelled' } }), 'Kunjungan dibatalkan')
}
</script>

<template>
  <div v-if="doc" class="page">
    <div class="page-head">
      <div class="t">
        <router-link :to="auth.isCustomer ? '/portal' : '/visits'" class="back"><Icon name="arrow-left" />{{ auth.isCustomer ? 'Portal' : 'Jadwal kunjungan' }}</router-link>
        <div class="row" style="flex-wrap: wrap"><h1>{{ doc.customer.name }}</h1><StatusBadge :status="doc.visit.status" /></div>
        <p>{{ doc.report?.report_no ? doc.report.report_no + ' · ' : '' }}{{ doc.site.name }} · {{ fmtDate(doc.visit.scheduled_date) }}</p>
      </div>
      <div class="actions">
        <a v-if="doc.visit.status === 'published'" class="btn primary" :href="fileUrl(`/visits/${doc.visit.id}/pdf`)" target="_blank"><Icon name="download" />Unduh PDF</a>
        <template v-if="auth.isStaff">
          <a v-if="doc.report && doc.visit.status !== 'published'" class="btn" :href="fileUrl(`/visits/${doc.visit.id}/pdf?preview=1`)" target="_blank"><Icon name="eye" />Pratinjau PDF</a>
          <button v-if="doc.visit.status === 'pending_review'" class="btn" :disabled="busy" @click="returnForRevision"><Icon name="undo" />Minta revisi</button>
          <button v-if="doc.visit.status === 'pending_review'" class="btn gold" :disabled="busy" @click="publish"><Icon name="check" />Terbitkan laporan</button>
        </template>
      </div>
    </div>
    <p v-if="error" class="notice red" style="margin-bottom: 16px"><Icon name="alert" />{{ error }}</p>
    <p v-if="doc.report?.review_notes && doc.visit.status === 'revision'" class="notice" style="margin-bottom: 16px"><Icon name="note" /><span><b>Catatan revisi:</b> {{ doc.report.review_notes }}</span></p>

    <div class="grid side">
      <ReportView :doc="doc" />
      <aside>
        <div class="card">
          <div class="card-head"><span class="ic"><Icon name="info" /></span><h3>Informasi kunjungan</h3></div>
          <div class="card-body">
            <dl class="kv">
              <dt>Lokasi</dt><dd>{{ doc.site.name }}<span class="cell-sub">{{ doc.site.address }}</span></dd>
              <dt>Tipe</dt><dd>{{ visitTypes[doc.visit.visit_type] }}</dd>
              <dt>Tanggal</dt><dd>{{ fmtDate(doc.visit.scheduled_date) }}</dd>
              <dt>Waktu kerja</dt><dd>{{ fmtTime(doc.report?.started_at) }} – {{ fmtTime(doc.report?.finished_at) }} WIB</dd>
              <dt>Teknisi</dt><dd>{{ doc.technician?.name || '-' }}</dd>
              <dt>PIC</dt><dd>{{ doc.report?.pic_name || doc.pic?.name || '-' }}</dd>
              <template v-if="doc.visit.notes"><dt>Catatan</dt><dd>{{ doc.visit.notes }}</dd></template>
            </dl>
          </div>
        </div>
        <form v-if="auth.isStaff && ['scheduled', 'in_progress'].includes(doc.visit.status)" class="card" @submit.prevent="saveAssign">
          <div class="card-head"><span class="ic"><Icon name="user" /></span><h3>Penugasan</h3></div>
          <div class="card-body stack">
            <label class="field"><span>Teknisi</span><select v-model="assign.technician_id"><option value="">Belum ditugaskan</option>
              <option v-for="t in technicians" :key="t.id" :value="t.id">{{ t.name }}</option></select></label>
            <label class="field"><span>Tanggal</span><input type="date" v-model="assign.scheduled_date" /></label>
            <label class="field"><span>Tipe</span><select v-model="assign.visit_type"><option v-for="(l, k) in visitTypes" :key="k" :value="k">{{ l }}</option></select></label>
            <button class="btn primary block" :disabled="busy">Simpan penugasan</button>
            <button type="button" class="btn danger block" :disabled="busy" @click="cancelVisit"><Icon name="x" />Batalkan kunjungan</button>
          </div>
        </form>
      </aside>
    </div>
  </div>
</template>
