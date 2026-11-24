<script setup>
import { ref, computed, onMounted } from 'vue'
import { api } from '../lib/api'
import { visitStatus, fmtDate } from '../lib/labels'
const today = new Date().toISOString().slice(0, 10)
const visits = ref([])
const pending = ref([])
onMounted(async () => {
  const monthStart = today.slice(0, 8) + '01'
  visits.value = await api(`/visits?from=${monthStart}`)
  pending.value = await api('/visits?status=pending_review')
})
const todays = computed(() => visits.value.filter((v) => v.scheduled_date === today))
const count = (s) => visits.value.filter((v) => v.status === s).length
</script>

<template>
  <div>
    <h1>Dashboard</h1>
    <div class="stats">
      <div class="card stat"><b>{{ todays.length }}</b><span>Kunjungan hari ini</span></div>
      <div class="card stat"><b>{{ pending.length }}</b><span>Menunggu review</span></div>
      <div class="card stat"><b>{{ count('scheduled') }}</b><span>Terjadwal bulan ini</span></div>
      <div class="card stat"><b>{{ count('published') }}</b><span>Terbit bulan ini</span></div>
    </div>
    <h2>Laporan menunggu review</h2>
    <table class="table">
      <thead><tr><th>Tanggal</th><th>Pelanggan</th><th>Lokasi</th><th>Teknisi</th><th></th></tr></thead>
      <tbody>
        <tr v-for="v in pending" :key="v.id">
          <td>{{ fmtDate(v.scheduled_date) }}</td><td>{{ v.customer_name }}</td><td>{{ v.site_name }}</td><td>{{ v.technician_name }}</td>
          <td><router-link :to="'/visits/' + v.id">Review</router-link></td>
        </tr>
        <tr v-if="!pending.length"><td colspan="5" class="muted">Tidak ada laporan yang menunggu.</td></tr>
      </tbody>
    </table>
    <h2>Kunjungan hari ini</h2>
    <table class="table">
      <thead><tr><th>Pelanggan</th><th>Lokasi</th><th>Teknisi</th><th>Status</th></tr></thead>
      <tbody>
        <tr v-for="v in todays" :key="v.id">
          <td><router-link :to="'/visits/' + v.id">{{ v.customer_name }}</router-link></td><td>{{ v.site_name }}</td>
          <td>{{ v.technician_name || '-' }}</td><td><span :class="['badge', v.status]">{{ visitStatus[v.status] }}</span></td>
        </tr>
        <tr v-if="!todays.length"><td colspan="4" class="muted">Tidak ada kunjungan hari ini.</td></tr>
      </tbody>
    </table>
  </div>
</template>
