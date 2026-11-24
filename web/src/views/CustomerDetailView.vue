<script setup>
import { ref, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { api } from '../lib/api'
import MasterTable from '../components/MasterTable.vue'
import { roles } from '../lib/labels'
import { useAuth } from '../stores/auth'

const route = useRoute()
const auth = useAuth()
const customer = ref(null)
const users = ref([])
const form = ref(null)
const error = ref('')
async function loadUsers() { users.value = await api(`/users?role=customer&customer_id=${route.params.id}`) }
onMounted(async () => {
  customer.value = await api('/master/customers/' + route.params.id)
  if (auth.isAdmin) await loadUsers()
})
async function addUser() {
  error.value = ''
  try {
    await api('/users', { method: 'POST', body: { ...form.value, role: 'customer', customer_id: route.params.id } })
    form.value = null
    await loadUsers()
  } catch (e) { error.value = e.message }
}
</script>

<template>
  <div v-if="customer">
    <router-link to="/customers" class="muted">← Pelanggan</router-link>
    <h1>{{ customer.name }}</h1>
    <h2>Lokasi</h2>
    <MasterTable resource="sites" :fixed="{ customer_id: customer.id }" :link-to="(s) => '/sites/' + s.id" />

    <template v-if="auth.isAdmin">
      <h2>Akun portal pelanggan</h2>
      <div class="toolbar"><button class="primary" @click="form = { name: '', email: '', password: '' }">+ Buat akun portal</button></div>
      <form v-if="form" class="card form" @submit.prevent="addUser">
        <div class="grid3">
          <label><span>Nama *</span><input v-model="form.name" required /></label>
          <label><span>Email *</span><input v-model="form.email" type="email" required /></label>
          <label><span>Password awal *</span><input v-model="form.password" minlength="8" required /></label>
        </div>
        <p v-if="error" class="error">{{ error }}</p>
        <div class="actions"><button type="button" @click="form = null">Batal</button><button class="primary">Simpan</button></div>
      </form>
      <table class="table">
        <thead><tr><th>Nama</th><th>Email</th><th>Peran</th><th>Aktif</th></tr></thead>
        <tbody>
          <tr v-for="u in users" :key="u.id"><td>{{ u.name }}</td><td>{{ u.email }}</td><td>{{ roles[u.role] }}</td><td>{{ u.active ? 'Ya' : 'Tidak' }}</td></tr>
          <tr v-if="!users.length"><td colspan="4" class="muted">Belum ada akun portal.</td></tr>
        </tbody>
      </table>
    </template>
  </div>
</template>
