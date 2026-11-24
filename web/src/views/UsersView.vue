<script setup>
import { ref, onMounted } from 'vue'
import { api } from '../lib/api'
import { roles } from '../lib/labels'
import { useAuth } from '../stores/auth'
const auth = useAuth()
const users = ref([])
const form = ref(null)
const error = ref('')
const staffRoles = ['admin', 'supervisor', 'technician']
async function load() { users.value = (await api('/users')).filter((u) => u.role !== 'customer') }
onMounted(load)
function startNew() { form.value = { name: '', email: '', phone: '', role: 'technician', technician_code: '', password: '' }; error.value = '' }
function startEdit(u) { form.value = { ...u, password: '' }; error.value = '' }
async function save() {
  error.value = ''
  const body = { ...form.value }
  if (!body.password) delete body.password
  if (!body.technician_code) delete body.technician_code
  try {
    await api('/users' + (body.id ? '/' + body.id : ''), { method: body.id ? 'PATCH' : 'POST', body })
    form.value = null
    await load()
  } catch (e) { error.value = e.message }
}
</script>

<template>
  <div>
    <h1>Pengguna internal</h1>
    <div class="toolbar"><button class="primary" @click="startNew">+ Tambah pengguna</button></div>
    <form v-if="form" class="card form" @submit.prevent="save">
      <div class="grid3">
        <label><span>Nama *</span><input v-model="form.name" required /></label>
        <label><span>Email *</span><input v-model="form.email" type="email" required /></label>
        <label><span>No HP</span><input v-model="form.phone" /></label>
        <label><span>Peran *</span><select v-model="form.role">
          <option v-for="r in (auth.user.role === 'super_admin' ? ['super_admin', ...staffRoles] : staffRoles)" :key="r" :value="r">{{ roles[r] }}</option></select></label>
        <label v-if="form.role === 'technician'"><span>Kode teknisi</span><input v-model="form.technician_code" placeholder="P015" /></label>
        <label><span>{{ form.id ? 'Password baru' : 'Password *' }}</span><input v-model="form.password" :required="!form.id" minlength="8" /></label>
        <label v-if="form.id"><span>Aktif</span><input type="checkbox" class="check" v-model="form.active" /></label>
      </div>
      <p v-if="error" class="error">{{ error }}</p>
      <div class="actions"><button type="button" @click="form = null">Batal</button><button class="primary">Simpan</button></div>
    </form>
    <table class="table">
      <thead><tr><th>Nama</th><th>Email</th><th>Peran</th><th>Kode</th><th>Aktif</th><th></th></tr></thead>
      <tbody>
        <tr v-for="u in users" :key="u.id">
          <td>{{ u.name }}</td><td>{{ u.email }}</td><td>{{ roles[u.role] }}</td><td>{{ u.technician_code || '-' }}</td>
          <td>{{ u.active ? 'Ya' : 'Tidak' }}</td><td><a href="#" @click.prevent="startEdit(u)">Ubah</a></td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
