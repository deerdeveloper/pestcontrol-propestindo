<script setup>
// Tabel CRUD generik untuk data master. `fixed` mengunci filter, misalnya { site_id }.
import { ref, computed, onMounted, watch } from 'vue'
import { api } from '../lib/api'
import { masters } from '../lib/masters'
import { useAuth } from '../stores/auth'

const props = defineProps({
  resource: { type: String, required: true },
  fixed: { type: Object, default: () => ({}) },
  linkTo: { type: Function, default: null },
})
const auth = useAuth()
const conf = computed(() => masters[props.resource])
const fields = computed(() => conf.value.fields.filter((f) => !(f.key in props.fixed)))
const rows = ref([])
const refs = ref({})
const q = ref('')
const editing = ref(null)
const error = ref('')
const busy = ref(false)

async function load() {
  const params = new URLSearchParams({ ...props.fixed })
  if (q.value) params.set('q', q.value)
  rows.value = await api(`/master/${props.resource}?${params}`)
  for (const f of fields.value.filter((f) => f.type === 'ref')) {
    const p = f.refFilter ? `?${f.refFilter}=${props.fixed[f.refFilter] || ''}` : ''
    refs.value[f.key] = await api(`/master/${f.ref}${p}`)
  }
}
onMounted(load)
watch(() => [props.resource, JSON.stringify(props.fixed)], load)

function refName(f, id) {
  const r = refs.value[f.key]?.find((x) => x.id === id)
  return r ? r[f.refLabel] : '-'
}
function show(f, row) {
  const v = row[f.key]
  if (f.type === 'bool') return v ? 'Ya' : 'Tidak'
  if (f.type === 'ref') return refName(f, v)
  if (f.type === 'select') return f.options[v] ?? v
  if (f.type === 'tags') return (v || []).join(', ')
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
    await load()
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}

async function remove(row) {
  if (!confirm('Hapus data ini?')) return
  try { await api(`/master/${props.resource}/${row.id}`, { method: 'DELETE' }); await load() } catch (e) { alert(e.message) }
}
</script>

<template>
  <div>
    <div class="toolbar">
      <input v-model="q" placeholder="Cari..." @keyup.enter="load" class="search" />
      <button v-if="auth.isAdmin" class="primary" @click="startNew">+ Tambah {{ conf.title.toLowerCase() }}</button>
    </div>

    <form v-if="editing" class="card form" @submit.prevent="save">
      <h3>{{ editing.id ? 'Ubah' : 'Tambah' }} {{ conf.title.toLowerCase() }}</h3>
      <div class="grid2">
        <label v-for="f in fields" :key="f.key">
          <span>{{ f.label }}<b v-if="f.required"> *</b></span>
          <input v-if="f.readonly" :value="editing[f.key] ?? 'otomatis'" disabled />
          <input v-else-if="f.type === 'bool'" type="checkbox" v-model="editing[f.key]" class="check" />
          <select v-else-if="f.type === 'select'" v-model="editing[f.key]">
            <option v-for="(l, k) in f.options" :key="k" :value="k">{{ l }}</option>
          </select>
          <select v-else-if="f.type === 'ref'" v-model="editing[f.key]">
            <option :value="null">-</option>
            <option v-for="o in refs[f.key]" :key="o.id" :value="o.id">{{ o[f.refLabel] }}</option>
          </select>
          <input v-else :type="f.type === 'number' ? 'number' : 'text'" step="any" v-model="editing[f.key]" />
          <small v-if="f.hint">{{ f.hint }}</small>
        </label>
      </div>
      <p v-if="error" class="error">{{ error }}</p>
      <div class="actions">
        <button type="button" @click="editing = null">Batal</button>
        <button class="primary" :disabled="busy">Simpan</button>
      </div>
    </form>

    <table class="table">
      <thead><tr><th v-for="f in fields.filter((f) => !f.hideInTable)" :key="f.key">{{ f.label }}</th><th></th></tr></thead>
      <tbody>
        <tr v-for="row in rows" :key="row.id">
          <td v-for="f in fields.filter((f) => !f.hideInTable)" :key="f.key">{{ show(f, row) }}</td>
          <td class="row-actions">
            <router-link v-if="linkTo" :to="linkTo(row)">Detail</router-link>
            <a v-if="auth.isAdmin" href="#" @click.prevent="startEdit(row)">Ubah</a>
            <a v-if="auth.isAdmin" href="#" class="danger" @click.prevent="remove(row)">Hapus</a>
          </td>
        </tr>
        <tr v-if="!rows.length"><td :colspan="fields.length + 1" class="muted">Belum ada data.</td></tr>
      </tbody>
    </table>
  </div>
</template>
