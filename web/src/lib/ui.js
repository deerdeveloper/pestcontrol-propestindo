// Toast dan dialog konfirmasi/isian yang tampil konsisten (pengganti alert/confirm/prompt bawaan browser).
import { reactive } from 'vue'

export const ui = reactive({ toasts: [], dialog: null })
let seq = 0

export function toast(message, type = 'ok', ms = 3200) {
  const id = ++seq
  ui.toasts = [...ui.toasts.slice(-1), { id, message, type }] // maksimal 2 toast sekaligus
  setTimeout(() => { ui.toasts = ui.toasts.filter((t) => t.id !== id) }, ms)
}

function open(d) {
  return new Promise((resolve) => { ui.dialog = { ...d, resolve } })
}

/** Dialog ya/tidak. Mengembalikan true bila disetujui. */
export function confirmDialog({ title, message = '', ok = 'Ya', cancel = 'Batal', danger = false }) {
  return open({ kind: 'confirm', title, message, ok, cancel, danger })
}

/** Dialog isian teks. Mengembalikan teks, atau null bila dibatalkan. */
export function promptDialog({ title, message = '', label = '', value = '', ok = 'Simpan', cancel = 'Batal', required = false, multiline = true, placeholder = '' }) {
  return open({ kind: 'prompt', title, message, label, value, ok, cancel, required, multiline, placeholder })
}

export function closeDialog(result) {
  const d = ui.dialog
  ui.dialog = null
  d?.resolve(result)
}
