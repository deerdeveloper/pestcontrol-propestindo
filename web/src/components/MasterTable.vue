<script setup>
// Tabel CRUD generik untuk data master. `fixed` mengunci filter, misalnya { site_id }.
import { ref, computed, onMounted, watch } from 'vue'
import { useRouter } from 'vue-router'
import { api } from '../lib/api'
import { masters } from '../lib/masters'
import { useAuth } from '../stores/auth'
import { confirmDialog, toast } from '../lib/ui'
import Icon from './Icon.vue'
import Modal from './Modal.vue'
import EmptyState from './EmptyState.vue'

const props = defineProps({
  resource: { type: String, required: true },
  fixed: { type: Object, default: () => ({}) },
  linkTo: { type: Function, default: null },
})
const auth = useAuth()
const router = useRouter()
const conf = computed(() => masters[props.resource])
const fields = computed(() => conf.value.fields.filter((f) => !(f.key in props.fixed)))
const cols = computed(() => fields.value.filter((f) => !f.hideInTable))
const rows = ref([])
const refs = ref({})
const q = ref('')
const editing = ref(null)
const error = ref('')
const busy = ref(false)
const loading = ref(true)

async function load() {
  const params = new URLSearchParams({ ...props.fixed })
  if (q.value) params.set('q', q.value)
  rows.value = await api(`/master/${props.resource}?${params}`)
  for (const f of fields.value.filter((f) => f.type === 'ref')) {
    const p = f.refFilter ? `?${f.refFilter}=${props.fixed[f.refFilter] || ''}` : ''
    refs.value[f.key] = await api(`/master/${f.ref}${p}`)
  }
  loading.value = false
}
onMounted(load)
watch(() => [props.resource, JSON.stringify(props.fixed)], load)
let t = null
watch(q, () => { clearTimeout(t); t = setTimeout(load, 300) })

function refName(f, id) {
  const r = refs.value[f.key]?.find((x) => x.id === id)
  return r ? r[f.refLabel] : '-'
}
function show(f, row) {
  const v = row[f.key]
  if (f.type === 'ref') return refName(f, v)
  if (f.type === 'select') return f.options[v] ?? v
  if (f.type === 'tags') return (v || []).join(', ') || '-'
  return v ?? '-'
}

function startNew() {
  const o = {}
  for (const f of fields.value) o[f.key] = f.default ?? (f.type === 'tags' ? '' : null)
  editing.value = o
  error.value = ''
}
function startEdit(row) {
  const o = { ...row }
  for (const f of fields.value) if (f.type === 'tags') o[f.key] = (row[f.key] || []).join(', ')
  editing.value = o
  error.value = ''
}

async function save() {
  error.value = ''
  const body = { ...props.fixed }
  for (const f of fields.value) {
    if (f.readonly) continue
    let v = editing.value[f.key]
    if (f.type === 'tags') v = String(v || '').split(',').map((s) => s.trim()).filter(Boolean)
    if (f.type === 'number') v = v === '' || v === null ? null : Number(v)
    if (v === '') v = null
    if (f.required && (v === null || v === undefined)) { error.value = `${f.label} wajib diisi`; return }
    body[f.key] = v
  }
  busy.value = true
  try {
    const id = editing.value.id
    await api(`/master/${props.resource}${id ? '/' + id : ''}`, { method: id ? 'PATCH' : 'POST', body })
    editing.value = null
    toast(id ? 'Perubahan disimpan' : `${conf.value.title} ditambahkan`)
    await load()
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}

async function remove(row) {
  if (!(await confirmDialog({ title: 'Hapus data ini?', message: 'Data yang dihapus tidak bisa dikembalikan.', ok: 'Hapus', danger: true }))) return
  try { await api(`/master/${props.resource}/${row.id}`, { method: 'DELETE' }); toast('Data dihapus'); await load() } catch (e) { toast(e.message, 'error', 5000) }
}
function open(row) { if (props.linkTo) router.push(props.linkTo(row)) }
</script>

<template>
  <div>
    <div class="toolbar">
      <div class="search-box"><Icon name="search" /><input v-model="q" :placeholder="'Cari ' + conf.title.toLowerCase() + '…'" /></div>
      <span class="spacer hide-sm" />
      <button v-if="auth.isAdmin" class="btn primary" @click="startNew"><Icon name="plus" />Tambah {{ conf.title.toLowerCase() }}</button>
    </div>

    <div class="table-wrap">
      <table class="table cards">
        <thead><tr><th v-for="f in cols" :key="f.key">{{ f.label }}</th><th></th></tr></thead>
        <tbody>
          <tr v-for="row in rows" :key="row.id" :class="{ click: linkTo }" @click="open(row)">
            <td v-for="(f, i) in cols" :key="f.key" :class="{ primary: i === 0 }" :data-label="i === 0 ? null : f.label">
              <span v-if="f.type === 'bool'" class="badge" :class="row[f.key] ? 'ok' : 'cancelled'">{{ row[f.key] ? 'Ya' : 'Tidak' }}</span>
              <span v-else-if="i === 0" class="cell-main">{{ show(f, row) }}</span>
              <template v-else>{{ show(f, row) }}</template>
            </td>
            <td class="actions" @click.stop>
              <router-link v-if="linkTo" :to="linkTo(row)" class="btn sm">Detail<Icon name="chevron-right" /></router-link>
              <button v-if="auth.isAdmin" class="btn ghost icon sm" title="Ubah" @click="startEdit(row)"><Icon name="edit" /></button>
              <button v-if="auth.isAdmin" class="btn ghost icon sm danger" title="Hapus" @click="remove(row)"><Icon name="trash" /></button>
            </td>
          </tr>
          <tr v-if="!rows.length && !loading" class="empty"><td :colspan="cols.length + 1">
            <EmptyState icon="database" :title="q ? 'Tidak ditemukan' : 'Belum ada data'" :text="auth.isAdmin && !q ? 'Tekan tombol Tambah untuk mengisi data pertama.' : ''" />
          </td></tr>
        </tbody>
      </table>
    </div>

    <Modal v-if="editing" :title="(editing.id ? 'Ubah ' : 'Tambah ') + conf.title.toLowerCase()" @close="editing = null">
      <form :id="'mf-' + resource" class="form-grid" @submit.prevent="save">
        <label v-for="f in fields" :key="f.key" class="field" :class="{ check: f.type === 'bool', full: f.type === 'tags' || f.key === 'address' || f.key === 'billing_address' }">
          <template v-if="f.type === 'bool'"><input type="checkbox" v-model="editing[f.key]" /><span>{{ f.label }}</span></template>
          <template v-else>
            <span>{{ f.label }}<b v-if="f.required"> *</b></span>
            <input v-if="f.readonly" :value="editing[f.key] ?? 'otomatis'" disabled />
            <select v-else-if="f.type === 'select'" v-model="editing[f.key]">
              <option v-for="(l, k) in f.options" :key="k" :value="k">{{ l }}</option>
            </select>
            <select v-else-if="f.type === 'ref'" v-model="editing[f.key]">
              <option :value="null">-</option>
              <option v-for="o in refs[f.key]" :key="o.id" :value="o.id">{{ o[f.refLabel] }}</option>
            </select>
            <input v-else :type="f.type === 'number' ? 'number' : 'text'" step="any" v-model="editing[f.key]" />
            <small v-if="f.hint">{{ f.hint }}</small>
          </template>
        </label>
        <p v-if="error" class="notice red full"><Icon name="alert" />{{ error }}</p>
      </form>
      <template #foot>
        <button type="button" class="btn" @click="editing = null">Batal</button>
        <button :form="'mf-' + resource" class="btn primary" :disabled="busy">Simpan</button>
      </template>
    </Modal>
  </div>
</template>
