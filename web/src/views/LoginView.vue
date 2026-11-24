<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuth } from '../stores/auth'
import Icon from '../components/Icon.vue'
const auth = useAuth()
const router = useRouter()
const email = ref('')
const password = ref('')
const show = ref(false)
const error = ref('')
const busy = ref(false)
async function submit() {
  error.value = ''
  busy.value = true
  try {
    await auth.login(email.value.trim(), password.value)
    router.replace(auth.home)
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <div class="auth">
    <section class="auth-art">
      <a href="/" class="brand"><img src="/emblem.svg" alt="" /><span><b>PROPESTINDO</b><small>Profesional Pest Control Indonesia</small></span></a>
      <div>
        <span class="pill"><i class="dot" />Sistem Laporan Kunjungan Digital</span>
        <h1>Laporan pest control <em>rapi, cepat,</em> dan siap audit.</h1>
        <p>Jadwal, temuan hama, tindakan pengendalian, rekomendasi sanitasi, dan tanda tangan PIC dalam satu sistem.</p>
        <ul class="auth-feats">
          <li><span><Icon name="smartphone" /></span>Teknisi isi laporan dari HP, tetap jalan tanpa sinyal</li>
          <li><span><Icon name="clipboard" /></span>Admin review dan terbitkan laporan PDF bilingual</li>
          <li><span><Icon name="shield" /></span>Pelanggan pantau laporan dan rekomendasi kapan saja</li>
        </ul>
      </div>
      <p class="foot">© Propestindo · Pest Control & Environmental Services</p>
    </section>
    <section class="auth-form">
      <form @submit.prevent="submit">
        <div>
          <span class="eyebrow">Selamat datang</span>
          <h2>Masuk ke akun Anda</h2>
          <p class="muted" style="margin-top: 6px">Untuk admin, supervisor, teknisi, dan pelanggan.</p>
        </div>
        <label class="field"><span>Email</span><input v-model="email" type="email" autocomplete="username" placeholder="nama@perusahaan.com" required /></label>
        <label class="field"><span>Password</span>
          <div class="pw">
            <input v-model="password" :type="show ? 'text' : 'password'" autocomplete="current-password" placeholder="••••••••" required />
            <button type="button" class="btn ghost icon sm" :aria-label="show ? 'Sembunyikan' : 'Tampilkan'" @click="show = !show"><Icon :name="show ? 'eye-off' : 'eye'" /></button>
          </div>
        </label>
        <p v-if="error" class="notice red"><Icon name="alert" />{{ error }}</p>
        <button class="btn primary lg block" :disabled="busy">{{ busy ? 'Memproses…' : 'Masuk' }}<Icon v-if="!busy" name="arrow-right" /></button>
        <div class="role-hint">
          <div><Icon name="dashboard" /><b>Admin</b>Jadwal & review</div>
          <div><Icon name="smartphone" /><b>Teknisi</b>Laporan lapangan</div>
          <div><Icon name="building" /><b>Pelanggan</b>Laporan & PDF</div>
        </div>
        <a class="back" href="/" style="justify-content: center"><Icon name="arrow-left" />Kembali ke beranda</a>
      </form>
    </section>
  </div>
</template>
