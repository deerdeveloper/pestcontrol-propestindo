<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuth } from '../stores/auth'
const auth = useAuth()
const router = useRouter()
const email = ref('')
const password = ref('')
const error = ref('')
const busy = ref(false)
async function submit() {
  error.value = ''
  busy.value = true
  try {
    await auth.login(email.value, password.value)
    router.replace('/')
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <div class="login">
    <form class="card" @submit.prevent="submit">
      <img src="/logo.png" alt="Propestindo" />
      <h2>Masuk</h2>
      <label><span>Email</span><input v-model="email" type="email" autocomplete="username" required /></label>
      <label><span>Password</span><input v-model="password" type="password" autocomplete="current-password" required /></label>
      <p v-if="error" class="error">{{ error }}</p>
      <button class="primary" :disabled="busy">Masuk</button>
      <small class="muted">Teknisi memakai aplikasi HP Propestindo.</small>
      <a class="muted back-home" href="/">&larr; Kembali ke beranda</a>
    </form>
  </div>
</template>
