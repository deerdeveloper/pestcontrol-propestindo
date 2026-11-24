<script setup>
import { ref, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { api } from '../lib/api'
import MasterTable from '../components/MasterTable.vue'
import Icon from '../components/Icon.vue'
import Modal from '../components/Modal.vue'
import { initials } from '../lib/labels'
import { toast } from '../lib/ui'
import { useAuth } from '../stores/auth'

const route = useRoute()
const auth = useAuth()
const customer = ref(null)
const users = ref([])
const form = ref(null)
const error = ref('')
const busy = ref(false)
async function loadUsers() { users.value = await api(`/users?role=customer&customer_id=${route.params.id}`) }
onMounted(async () => {
  customer.value = await api('/master/customers/' + route.params.id)
  if (auth.isAdmin) await loadUsers()
})
async function addUser() {
  error.value = ''
  busy.value = true
  try {
    await api('/users', { method: 'POST', body: { ...form.value, role: 'customer', customer_id: route.params.id } })
    form.value = null
    toast('Akun portal dibuat')
    await loadUsers()
  } catch (e) { error.value = e.message } finally { busy.value = false }
}
</script>

<template>
  <div v-if="customer" class="page">
    <div class="page-head">
      <div class="t">
        <router-link to="/customers" class="back"><Icon name="arrow-left" />Pelanggan</router-link>
        <div class="row"><h1>{{ customer.name }}</h1><span class="badge" :class="customer.active ? 'ok' : 'cancelled'">{{ customer.active ? 'Aktif' : 'Nonaktif' }}</span></div>
        <p>{{ customer.billing_address || 'Alamat penagihan belum diisi' }}{{ customer.tax_id ? ' · NPWP ' + customer.tax_id : '' }}</p>
      </div>
    </div>

    <div class="section-title"><h2>Lokasi layanan</h2></div>
    <MasterTable resource="sites" :fixed="{ customer_id: customer.id }" :link-to="(s) => '/sites/' + s.id" />

    <template v-if="auth.isAdmin">
      <div class="section-title"><h2>Akun portal pelanggan</h2>
        <button class="btn primary sm" @click="form = { name: '', email: '', password: '' }; error = ''"><Icon name="plus" />Buat akun</button></div>
      <div class="table-wrap">
        <table class="table cards">
          <thead><tr><th>Nama</th><th>Email</th><th>Status</th></tr></thead>
          <tbody>
            <tr v-for="u in users" :key="u.id">
              <td class="primary"><div class="row"><span class="avatar">{{ initials(u.name) }}</span><b>{{ u.name }}</b></div></td>
              <td data-label="Email">{{ u.email }}</td>
              <td data-label="Status"><span class="badge" :class="u.active ? 'ok' : 'cancelled'">{{ u.active ? 'Aktif' : 'Nonaktif' }}</span></td>
            </tr>
            <tr v-if="!users.length" class="empty"><td colspan="3">Belum ada akun portal. Buat akun supaya pelanggan bisa melihat laporan sendiri.</td></tr>
          </tbody>
        </table>
      </div>
      <Modal v-if="form" title="Buat akun portal pelanggan" @close="form = null">
        <form id="cust-user" class="stack" @submit.prevent="addUser">
          <label class="field"><span>Nama <b>*</b></span><input v-model="form.name" required /></label>
          <label class="field"><span>Email <b>*</b></span><input v-model="form.email" type="email" required /></label>
          <label class="field"><span>Password awal <b>*</b></span><input v-model="form.password" minlength="8" required /><small>Minimal 8 karakter. Berikan ke PIC pelanggan.</small></label>
          <p v-if="error" class="notice red"><Icon name="alert" />{{ error }}</p>
        </form>
        <template #foot><button type="button" class="btn" @click="form = null">Batal</button><button form="cust-user" class="btn primary" :disabled="busy">Simpan</button></template>
      </Modal>
    </template>
  </div>
</template>
