<script setup>
import { ref, onMounted } from 'vue'
import { api } from '../lib/api'
import { categories, fmtDate } from '../lib/labels'
const status = ref('open')
const items = ref([])
async function load() { items.value = await api('/portal/recommendations' + (status.value ? '?status=' + status.value : '')) }
onMounted(load)
async function mark(r, s) {
  const note = s === 'done' ? prompt('Catatan tindak lanjut (opsional):', r.customer_note || '') : null
  if (note === null && s === 'done') return
  await api('/portal/recommendations/' + r.id, { method: 'PATCH', body: { customer_status: s, customer_note: note } })
  await load()
}
</script>

<template>
  <div>
    <h1>Rekomendasi untuk ditindaklanjuti</h1>
    <p class="muted">Rekomendasi dari teknisi untuk mencegah hama datang lagi. Tandai yang sudah dikerjakan.</p>
    <div class="toolbar">
      <select v-model="status" @change="load"><option value="open">Belum dikerjakan</option><option value="done">Sudah dikerjakan</option><option value="">Semua</option></select>
    </div>
    <table class="table">
      <thead><tr><th>Tanggal</th><th>Lokasi</th><th>Kategori</th><th>Temuan risiko</th><th>Rekomendasi</th><th></th></tr></thead>
      <tbody>
        <tr v-for="r in items" :key="r.id">
          <td>{{ fmtDate(r.visit_date) }}<br /><small class="muted">{{ r.report_no }}</small></td><td>{{ r.site_name }}</td>
          <td>{{ categories[r.category] }}</td><td>{{ r.risk_finding }}</td><td>{{ r.recommendation }}
            <small v-if="r.customer_note" class="muted"><br />Catatan: {{ r.customer_note }}</small></td>
          <td>
            <button v-if="r.customer_status === 'open'" class="primary" @click="mark(r, 'done')">Sudah dikerjakan</button>
            <button v-else @click="mark(r, 'open')">Buka lagi</button>
          </td>
        </tr>
        <tr v-if="!items.length"><td colspan="6" class="muted">Tidak ada rekomendasi.</td></tr>
      </tbody>
    </table>
  </div>
</template>
