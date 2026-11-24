<script setup>
import { ref, computed, onMounted } from 'vue'
import { api } from '../lib/api'
import { roles, initials } from '../lib/labels'
import { toast } from '../lib/ui'
import { useAuth } from '../stores/auth'
import Icon from '../components/Icon.vue'
import Modal from '../components/Modal.vue'
const auth = useAuth()
const users = ref([])
const form = ref(null)
const error = ref('')
const busy = ref(false)
const roleFilter = ref('')
const staffRoles = ['admin', 'supervisor', 'technician']
async function load() { users.value = (await api('/users')).filter((u) => u.role !== 'customer') }
onMounted(load)
const shown = computed(() => users.value.filter((u) => !roleFilter.value || u.role === roleFilter.value))
function startNew() { form.value = { name: '', email: '', phone: '', role: 'technician', technician_code: '', password: '' }; error.value = '' }
function startEdit(u) { form.value = { ...u, password: '' }; error.value = '' }
async function save() {
  error.value = ''
  const body = { ...form.value }
  if (!body.password) delete body.password
  if (!body.technician_code) delete body.technician_code
  busy.value = true
  try {
    await api('/users' + (body.id ? '/' + body.id : ''), { method: body.id ? 'PATCH' : 'POST', body })
    form.value = null
    toast('Pengguna disimpan')
    await load()
  } catch (e) { error.value = e.message } finally { busy.value = false }
}
</script>

<template>
  <div class="page">
    <div class="page-head">
      <div class="t"><h1>Pengguna internal</h1><p>Akun admin, supervisor, dan teknisi. Akun pelanggan dibuat dari halaman pelanggan.</p></div>
      <div class="actions"><button class="btn primary" @click="startNew"><Icon name="plus" />Tambah pengguna</button></div>
    </div>
    <div class="tabs">
      <button :class="{ active: !roleFilter }" @click="roleFilter = ''">Semua<span class="count">{{ users.length }}</span></button>
      <button v-for="r in ['super_admin', ...staffRoles]" :key="r" :class="{ active: roleFilter === r }" @click="roleFilter = r">
        {{ roles[r] }}<span class="count">{{ users.filter((u) => u.role === r).length }}</span></button>
    </div>
    <div class="table-wrap">
      <table class="table cards">
        <thead><tr><th>Nama</th><th>Peran</th><th>Kode</th><th>No HP</th><th>Status</th><th></th></tr></thead>
        <tbody>
          <tr v-for="u in shown" :key="u.id" class="click" @click="startEdit(u)">
            <td class="primary"><div class="row"><span class="avatar">{{ initials(u.name) }}</span><div class="grow"><span class="cell-main">{{ u.name }}</span><span class="cell-sub">{{ u.email }}</span></div></div></td>
            <td data-label="Peran"><span class="badge plain" :class="u.role === 'technician' ? 'ok' : 'scheduled'">{{ roles[u.role] }}</span></td>
            <td data-label="Kode">{{ u.technician_code || '—' }}</td>
            <td data-label="No HP">{{ u.phone || '—' }}</td>
            <td data-label="Status"><span class="badge" :class="u.active ? 'ok' : 'cancelled'">{{ u.active ? 'Aktif' : 'Nonaktif' }}</span></td>
            <td class="actions"><button class="btn ghost icon sm" title="Ubah" @click.stop="startEdit(u)"><Icon name="edit" /></button></td>
          </tr>
        </tbody>
      </table>
    </div>
    <Modal v-if="form" :title="form.id ? 'Ubah pengguna' : 'Tambah pengguna'" @close="form = null">
      <form id="user-form" class="form-grid" @submit.prevent="save">
        <label class="field"><span>Nama <b>*</b></span><input v-model="form.name" required /></label>
        <label class="field"><span>Email <b>*</b></span><input v-model="form.email" type="email" required /></label>
        <label class="field"><span>No HP</span><input v-model="form.phone" inputmode="tel" /></label>
        <label class="field"><span>Peran <b>*</b></span><select v-model="form.role">
          <option v-for="r in (auth.user.role === 'super_admin' ? ['super_admin', ...staffRoles] : staffRoles)" :key="r" :value="r">{{ roles[r] }}</option></select></label>
        <label v-if="form.role === 'technician'" class="field"><span>Kode teknisi</span><input v-model="form.technician_code" placeholder="P015" /></label>
        <label class="field"><span>{{ form.id ? 'Password baru' : 'Password' }}<b v-if="!form.id"> *</b></span><input v-model="form.password" :required="!form.id" minlength="8" :placeholder="form.id ? 'Kosongkan jika tidak diubah' : 'Minimal 8 karakter'" /></label>
        <label v-if="form.id" class="field check full"><input type="checkbox" v-model="form.active" /><span>Akun aktif</span></label>
        <p v-if="error" class="notice red full"><Icon name="alert" />{{ error }}</p>
      </form>
      <template #foot><button type="button" class="btn" @click="form = null">Batal</button><button form="user-form" class="btn primary" :disabled="busy">Simpan</button></template>
    </Modal>
  </div>
</template>
