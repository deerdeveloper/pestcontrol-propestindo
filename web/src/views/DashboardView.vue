<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { api } from '../lib/api'
import { visitStatus, visitTypes, fmtDate, fmtDay, todayISO } from '../lib/labels'
import { useAuth } from '../stores/auth'
import Icon from '../components/Icon.vue'
import StatusBadge from '../components/StatusBadge.vue'
import EmptyState from '../components/EmptyState.vue'

const auth = useAuth()
const router = useRouter()
const today = todayISO()
const monthStart = today.slice(0, 8) + '01'
const visits = ref([])
const pending = ref([])
const loading = ref(true)
onMounted(async () => {
  ;[visits.value, pending.value] = await Promise.all([
    api(`/visits?from=${monthStart}&to=${todayISO(14)}`),
    api('/visits?status=pending_review'),
  ])
  loading.value = false
})
const month = computed(() => visits.value.filter((v) => v.scheduled_date <= today.slice(0, 8) + '31'))
const todays = computed(() => visits.value.filter((v) => v.scheduled_date === today && v.status !== 'cancelled'))
const upcoming = computed(() => visits.value.filter((v) => v.scheduled_date > today && v.status === 'scheduled').slice(0, 8))
const overdue = computed(() => visits.value.filter((v) => v.scheduled_date < today && v.status === 'scheduled'))
const unassigned = computed(() => visits.value.filter((v) => !v.technician_id && ['scheduled'].includes(v.status)))
const count = (s) => month.value.filter((v) => v.status === s).length
const dist = computed(() => {
  const keys = ['scheduled', 'in_progress', 'pending_review', 'revision', 'published']
  const total = Math.max(1, keys.reduce((n, k) => n + count(k), 0))
  return keys.map((k) => ({ k, label: visitStatus[k], n: count(k), pct: Math.round((count(k) / total) * 100) }))
})
const greeting = computed(() => {
  const h = new Date().getHours()
  return h < 11 ? 'Selamat pagi' : h < 15 ? 'Selamat siang' : h < 18 ? 'Selamat sore' : 'Selamat malam'
})
const monthName = new Date().toLocaleDateString('id-ID', { month: 'long', year: 'numeric' })
const go = (v) => router.push('/visits/' + v.id)
</script>

<template>
  <div class="page">
    <div class="page-head">
      <div class="t">
        <span class="eyebrow">{{ new Date().toLocaleDateString('id-ID', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }) }}</span>
        <h1>{{ greeting }}, {{ auth.user.name.split(' ')[0] }}</h1>
        <p>Ringkasan operasional pest control bulan {{ monthName }}.</p>
      </div>
      <div class="actions">
        <router-link to="/visits?new=1" class="btn primary"><Icon name="plus" />Jadwalkan kunjungan</router-link>
      </div>
    </div>

    <div class="stats">
      <router-link to="/visits" class="card stat hero"><div class="ic"><Icon name="calendar" /></div><div><b>{{ todays.length }}</b><span>Kunjungan hari ini</span></div></router-link>
      <router-link to="/visits?status=pending_review" class="card stat gold"><div class="ic"><Icon name="clipboard" /></div><div><b>{{ pending.length }}</b><span>Menunggu review</span></div></router-link>
      <div class="card stat blue"><div class="ic"><Icon name="clock" /></div><div><b>{{ count('scheduled') }}</b><span>Terjadwal bulan ini</span></div></div>
      <div class="card stat"><div class="ic"><Icon name="file-check" /></div><div><b>{{ count('published') }}</b><span>Laporan terbit bulan ini</span></div></div>
    </div>

    <div v-if="overdue.length || unassigned.length" class="stack" style="margin-top: 16px">
      <div v-if="overdue.length" class="notice red"><Icon name="alert" /><span><b>{{ overdue.length }} kunjungan terlewat</b> masih berstatus terjadwal padahal tanggalnya sudah lewat.
        <router-link to="/visits?status=scheduled">Lihat jadwal</router-link></span></div>
      <div v-if="unassigned.length" class="notice"><Icon name="user" /><span><b>{{ unassigned.length }} kunjungan</b> belum punya teknisi.</span></div>
    </div>

    <div class="grid side" style="margin-top: 16px">
      <div>
        <div class="card">
          <div class="card-head"><span class="ic"><Icon name="clipboard" /></span><h2>Laporan menunggu review</h2>
            <router-link to="/visits?status=pending_review" class="btn ghost sm">Semua<Icon name="chevron-right" /></router-link></div>
          <div class="table-wrap">
            <table class="table cards">
              <thead><tr><th>Pelanggan</th><th>Tanggal</th><th>Teknisi</th><th></th></tr></thead>
              <tbody>
                <tr v-for="v in pending.slice(0, 6)" :key="v.id" class="click" @click="go(v)">
                  <td class="primary"><span class="cell-main">{{ v.customer_name }}</span><span class="cell-sub">{{ v.site_name }}</span></td>
                  <td data-label="Tanggal">{{ fmtDate(v.scheduled_date) }}</td>
                  <td data-label="Teknisi">{{ v.technician_name || '-' }}</td>
                  <td class="actions"><router-link :to="'/visits/' + v.id" class="btn sm primary" @click.stop>Review</router-link></td>
                </tr>
                <tr v-if="!pending.length && !loading" class="empty"><td colspan="4"><EmptyState icon="check-circle" title="Semua laporan sudah direview" /></td></tr>
              </tbody>
            </table>
          </div>
        </div>

        <div class="card">
          <div class="card-head"><span class="ic"><Icon name="map-pin" /></span><h2>Kunjungan hari ini</h2><span class="badge plain">{{ todays.length }}</span></div>
          <div class="table-wrap">
            <table class="table cards">
              <thead><tr><th>Pelanggan</th><th>Tipe</th><th>Teknisi</th><th>Status</th></tr></thead>
              <tbody>
                <tr v-for="v in todays" :key="v.id" class="click" @click="go(v)">
                  <td class="primary"><span class="cell-main">{{ v.customer_name }}</span><span class="cell-sub">{{ v.site_name }}</span></td>
                  <td data-label="Tipe">{{ visitTypes[v.visit_type] }}</td>
                  <td data-label="Teknisi">{{ v.technician_name || '-' }}</td>
                  <td data-label="Status"><StatusBadge :status="v.status" /></td>
                </tr>
                <tr v-if="!todays.length && !loading" class="empty"><td colspan="4"><EmptyState icon="calendar" title="Tidak ada kunjungan hari ini" /></td></tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <div>
        <div class="card">
          <div class="card-head"><span class="ic"><Icon name="layers" /></span><h3>Status bulan ini</h3></div>
          <div class="card-body stack">
            <div v-for="d in dist" :key="d.k">
              <div class="row" style="margin-bottom: 6px"><span class="badge" :class="d.k">{{ d.label }}</span><span class="spacer" /><b>{{ d.n }}</b></div>
              <div class="bar"><i :style="{ width: d.pct + '%' }" /></div>
            </div>
          </div>
        </div>
        <div class="card">
          <div class="card-head"><span class="ic"><Icon name="clock" /></span><h3>Akan datang (14 hari)</h3></div>
          <div class="card-body">
            <div v-for="v in upcoming" :key="v.id" class="up-item" @click="go(v)">
              <div class="date"><b>{{ v.scheduled_date.slice(8) }}</b><small>{{ fmtDay(v.scheduled_date).split(',')[0] }}</small></div>
              <div class="grow"><b>{{ v.customer_name }}</b><small>{{ v.site_name }} · {{ v.technician_name || 'Belum ditugaskan' }}</small></div>
              <Icon name="chevron-right" />
            </div>
            <p v-if="!upcoming.length" class="muted small">Belum ada jadwal dalam 14 hari ke depan.</p>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.up-item { display: flex; align-items: center; gap: 12px; padding: 10px 0; border-bottom: 1px solid var(--line-2); cursor: pointer; color: var(--muted); }
.up-item:last-child { border-bottom: 0; }
.up-item .date { width: 46px; height: 46px; border-radius: 12px; background: var(--green-50); color: var(--green-800); display: grid; place-items: center; align-content: center; flex: none; }
.up-item .date b { font-size: 16px; line-height: 1; }
.up-item .date small { font-size: 10.5px; font-weight: 700; text-transform: uppercase; }
.up-item .grow b { display: block; color: var(--ink); font-size: 14px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.up-item .grow small { display: block; font-size: 12.5px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
</style>
