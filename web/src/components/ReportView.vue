<script setup>
// Menampilkan isi laporan kunjungan dari dokumen API (report_document).
import { fileUrl } from '../lib/api'
import { levels, categories, stationStatus, consumption, fmtDate, fmtTime } from '../lib/labels'
import Icon from './Icon.vue'
import EmptyState from './EmptyState.vue'
defineProps({ doc: { type: Object, required: true } })
const stClass = { ok: 'ok', check: 'warn', replace: 'bad' }
</script>

<template>
  <div class="report">
    <p v-if="!doc.report" class="card"><EmptyState icon="clock" title="Kunjungan belum dimulai" text="Laporan muncul setelah teknisi check-in di lokasi." /></p>
    <template v-else>
      <section class="card">
        <div class="card-head"><span class="ic"><Icon name="bug" /></span><h3>Temuan hama</h3><span class="badge plain">{{ doc.report.findings.length }}</span></div>
        <div v-if="doc.report.findings.length" class="table-wrap">
          <table class="table cards">
            <thead><tr><th>Hama</th><th>Lokasi</th><th>Tingkat</th><th>Status</th><th>Keterangan</th></tr></thead>
            <tbody>
              <tr v-for="f in doc.report.findings" :key="f.id">
                <td class="primary"><span class="cell-main">{{ f.pest_name_id }}</span><span class="cell-sub">{{ f.pest_name_en }}</span></td>
                <td data-label="Lokasi">{{ f.area_name || '-' }}</td>
                <td data-label="Tingkat"><span class="lvl" :class="'lvl-' + f.level">{{ levels[f.level] }}</span></td>
                <td data-label="Status"><span class="badge" :class="f.is_active ? 'bad' : 'ok'">{{ f.is_active ? 'Aktif' : 'Tidak aktif' }}</span></td>
                <td data-label="Keterangan">{{ f.remarks || '-' }}
                  <div v-if="f.attachments?.length" class="thumbs"><a v-for="a in f.attachments" :key="a.id" :href="fileUrl('/files/attachments/' + a.id)" target="_blank">
                    <img :src="fileUrl('/files/attachments/' + a.id)" :alt="a.caption || 'foto'" /></a></div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <p v-else class="card-body muted">Tidak ada temuan hama.</p>
      </section>

      <section class="card">
        <div class="card-head"><span class="ic"><Icon name="spray" /></span><h3>Tindakan pengendalian</h3><span class="badge plain">{{ doc.report.treatments.length }}</span></div>
        <div v-if="doc.report.treatments.length" class="table-wrap">
          <table class="table cards">
            <thead><tr><th>Metode</th><th>Area</th><th>Bahan</th><th>Dosis</th><th>Jumlah</th><th>Alat</th></tr></thead>
            <tbody>
              <tr v-for="t in doc.report.treatments" :key="t.id">
                <td class="primary"><span class="cell-main">{{ t.method_name_id }}</span></td>
                <td data-label="Area">{{ t.area_name || '-' }}</td><td data-label="Bahan">{{ t.chemical_name || '-' }}</td>
                <td data-label="Dosis">{{ t.dose_text || '-' }}</td><td data-label="Jumlah">{{ t.quantity_used || '-' }}</td><td data-label="Alat">{{ t.equipment || '-' }}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p v-else class="card-body muted">Tidak ada tindakan.</p>
      </section>

      <section class="card">
        <div class="card-head"><span class="ic"><Icon name="lightbulb" /></span><h3>Rekomendasi</h3><span class="badge plain">{{ doc.report.recommendations.length }}</span></div>
        <div v-if="doc.report.recommendations.length" class="table-wrap">
          <table class="table cards">
            <thead><tr><th>Kategori</th><th>Temuan risiko</th><th>Rekomendasi</th><th>Tindak lanjut</th></tr></thead>
            <tbody>
              <tr v-for="r in doc.report.recommendations" :key="r.id">
                <td class="primary"><span class="cell-main">{{ categories[r.category] }}</span></td>
                <td data-label="Temuan risiko">{{ r.risk_finding }}</td><td data-label="Rekomendasi">{{ r.recommendation }}</td>
                <td data-label="Tindak lanjut"><span class="badge" :class="r.customer_status === 'done' ? 'ok' : 'warn'">{{ r.customer_status === 'done' ? 'Sudah dikerjakan' : 'Belum' }}</span>
                  <small v-if="r.customer_note" class="cell-sub">{{ r.customer_note }}</small></td>
              </tr>
            </tbody>
          </table>
        </div>
        <p v-else class="card-body muted">Tidak ada rekomendasi.</p>
      </section>

      <section class="card">
        <div class="card-head"><span class="ic"><Icon name="radar" /></span><h3>Alat monitoring</h3><span class="badge plain">{{ doc.report.station_checks.length }}</span></div>
        <div v-if="doc.report.station_checks.length" class="table-wrap">
          <table class="table cards">
            <thead><tr><th>Kode</th><th>Jenis</th><th>Lokasi</th><th>Kondisi</th><th>Konsumsi umpan</th><th>Temuan</th></tr></thead>
            <tbody>
              <tr v-for="s in doc.report.station_checks" :key="s.id">
                <td class="primary"><span class="cell-main">{{ s.station_code }}</span></td>
                <td data-label="Jenis">{{ s.equipment_type }}</td><td data-label="Lokasi">{{ s.area_name || '-' }}</td>
                <td data-label="Kondisi"><span class="badge" :class="stClass[s.status]">{{ stationStatus[s.status] }}</span></td>
                <td data-label="Konsumsi umpan">{{ consumption[s.bait_consumption] }}</td><td data-label="Temuan">{{ s.finding || '-' }}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p v-else class="card-body muted">Tidak ada alat yang diperiksa.</p>
      </section>

      <section v-if="doc.report.general_notes || doc.report.attachments.length" class="card">
        <div class="card-head"><span class="ic"><Icon name="image" /></span><h3>Catatan & dokumentasi</h3></div>
        <div class="card-body stack">
          <p v-if="doc.report.general_notes" style="white-space: pre-wrap">{{ doc.report.general_notes }}</p>
          <div v-if="doc.report.attachments.length" class="photos"><a v-for="a in doc.report.attachments" :key="a.id" :href="fileUrl('/files/attachments/' + a.id)" target="_blank">
            <img :src="fileUrl('/files/attachments/' + a.id)" :alt="a.caption || 'foto'" /></a></div>
        </div>
      </section>

      <section class="card">
        <div class="card-head"><span class="ic"><Icon name="signature" /></span><h3>Tanda tangan</h3></div>
        <div class="card-body">
          <div class="signs">
            <div v-for="s in doc.report.signatures" :key="s.id" class="sign">
              <img :src="fileUrl('/files/signatures/' + s.id)" alt="tanda tangan" />
              <b>{{ s.signer_name }}</b><small>{{ s.signer_role === 'pic' ? 'PIC pelanggan' : 'Teknisi' }} · {{ fmtDate(s.signed_at) }} {{ fmtTime(s.signed_at) }}</small>
            </div>
          </div>
          <p v-if="!doc.report.signatures.length" class="muted">Belum ada tanda tangan.</p>
        </div>
      </section>
    </template>
  </div>
</template>
