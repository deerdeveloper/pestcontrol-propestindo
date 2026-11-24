<script setup>
// Menampilkan isi laporan kunjungan dari dokumen API (report_document).
import { fileUrl } from '../lib/api'
import { visitTypes, visitStatus, levels, categories, stationStatus, consumption, fmtDate, fmtTime } from '../lib/labels'
defineProps({ doc: { type: Object, required: true } })
</script>

<template>
  <div class="report">
    <section class="card">
      <h3>1. Informasi kunjungan</h3>
      <dl class="info">
        <dt>Pelanggan</dt><dd>{{ doc.customer.name }} — {{ doc.site.name }}</dd>
        <dt>Alamat</dt><dd>{{ doc.site.address }}</dd>
        <dt>Tanggal</dt><dd>{{ fmtDate(doc.visit.scheduled_date) }}</dd>
        <dt>Tipe</dt><dd>{{ visitTypes[doc.visit.visit_type] }}</dd>
        <dt>Waktu</dt><dd>{{ fmtTime(doc.report?.started_at) }} – {{ fmtTime(doc.report?.finished_at) }} WIB</dd>
        <dt>Teknisi</dt><dd>{{ doc.technician?.name || '-' }}</dd>
        <dt>PIC</dt><dd>{{ doc.report?.pic_name || doc.pic?.name || '-' }}</dd>
        <dt>Status</dt><dd><span :class="['badge', doc.visit.status]">{{ visitStatus[doc.visit.status] }}</span></dd>
      </dl>
      <p v-if="doc.report?.review_notes && doc.visit.status === 'revision'" class="warn">Catatan revisi: {{ doc.report.review_notes }}</p>
    </section>

    <template v-if="doc.report">
      <section class="card">
        <h3>2. Temuan hama</h3>
        <table class="table" v-if="doc.report.findings.length">
          <thead><tr><th>Hama</th><th>Lokasi</th><th>Tingkat</th><th>Status</th><th>Keterangan</th></tr></thead>
          <tbody>
            <tr v-for="f in doc.report.findings" :key="f.id">
              <td><b>{{ f.pest_name_id }}</b></td><td>{{ f.area_name || '-' }}</td>
              <td :class="'lvl-' + f.level">{{ levels[f.level] }}</td>
              <td>{{ f.is_active ? 'Aktif' : 'Tidak aktif' }}</td>
              <td>{{ f.remarks || '-' }}
                <div class="thumbs"><a v-for="a in f.attachments" :key="a.id" :href="fileUrl('/files/attachments/' + a.id)" target="_blank">
                  <img :src="fileUrl('/files/attachments/' + a.id)" :alt="a.caption || 'foto'" /></a></div>
              </td>
            </tr>
          </tbody>
        </table>
        <p v-else class="muted">Tidak ada temuan.</p>
      </section>

      <section class="card">
        <h3>3. Tindakan pengendalian</h3>
        <table class="table" v-if="doc.report.treatments.length">
          <thead><tr><th>Metode</th><th>Area</th><th>Bahan</th><th>Dosis</th><th>Jumlah</th><th>Alat</th></tr></thead>
          <tbody>
            <tr v-for="t in doc.report.treatments" :key="t.id">
              <td><b>{{ t.method_name_id }}</b></td><td>{{ t.area_name || '-' }}</td><td>{{ t.chemical_name || '-' }}</td>
              <td>{{ t.dose_text || '-' }}</td><td>{{ t.quantity_used || '-' }}</td><td>{{ t.equipment || '-' }}</td>
            </tr>
          </tbody>
        </table>
        <p v-else class="muted">Tidak ada tindakan.</p>
      </section>

      <section class="card">
        <h3>4. Rekomendasi</h3>
        <table class="table" v-if="doc.report.recommendations.length">
          <thead><tr><th>Kategori</th><th>Temuan risiko</th><th>Rekomendasi</th><th>Tindak lanjut pelanggan</th></tr></thead>
          <tbody>
            <tr v-for="r in doc.report.recommendations" :key="r.id">
              <td><b>{{ categories[r.category] }}</b></td><td>{{ r.risk_finding }}</td><td>{{ r.recommendation }}</td>
              <td><span :class="['badge', r.customer_status === 'done' ? 'published' : 'scheduled']">
                {{ r.customer_status === 'done' ? 'Sudah dikerjakan' : 'Belum' }}</span>
                <small v-if="r.customer_note"><br>{{ r.customer_note }}</small></td>
            </tr>
          </tbody>
        </table>
        <p v-else class="muted">Tidak ada rekomendasi.</p>
      </section>

      <section class="card">
        <h3>5. Alat monitoring</h3>
        <table class="table" v-if="doc.report.station_checks.length">
          <thead><tr><th>Kode</th><th>Jenis</th><th>Lokasi</th><th>Status</th><th>Konsumsi umpan</th><th>Temuan</th></tr></thead>
          <tbody>
            <tr v-for="s in doc.report.station_checks" :key="s.id">
              <td><b>{{ s.station_code }}</b></td><td>{{ s.equipment_type }}</td><td>{{ s.area_name || '-' }}</td>
              <td :class="'st-' + s.status">{{ stationStatus[s.status] }}</td><td>{{ consumption[s.bait_consumption] }}</td><td>{{ s.finding || '-' }}</td>
            </tr>
          </tbody>
        </table>
        <p v-else class="muted">Tidak ada alat yang diperiksa.</p>
      </section>

      <section class="card" v-if="doc.report.attachments.length">
        <h3>Dokumentasi</h3>
        <div class="photos"><a v-for="a in doc.report.attachments" :key="a.id" :href="fileUrl('/files/attachments/' + a.id)" target="_blank">
          <img :src="fileUrl('/files/attachments/' + a.id)" /></a></div>
      </section>

      <section class="card">
        <h3>6. Tanda tangan</h3>
        <div class="signs">
          <div v-for="s in doc.report.signatures" :key="s.id" class="sign">
            <img :src="fileUrl('/files/signatures/' + s.id)" />
            <b>{{ s.signer_name }}</b><small>{{ s.signer_role === 'pic' ? 'PIC pelanggan' : 'Teknisi' }} · {{ fmtDate(s.signed_at) }} {{ fmtTime(s.signed_at) }}</small>
          </div>
          <p v-if="!doc.report.signatures.length" class="muted">Belum ada tanda tangan.</p>
        </div>
      </section>
    </template>
    <p v-else class="card muted">Kunjungan belum dimulai oleh teknisi.</p>
  </div>
</template>
