<script setup>
// Wadah toast dan dialog global (lihat lib/ui.js).
import { ref, watch } from 'vue'
import { ui, closeDialog } from '../lib/ui'
import Modal from './Modal.vue'
import Icon from './Icon.vue'
const text = ref('')
watch(() => ui.dialog, (d) => { text.value = d?.value || '' })
function submit() {
  const d = ui.dialog
  if (d.kind === 'prompt') {
    if (d.required && !text.value.trim()) return
    closeDialog(text.value.trim())
  } else closeDialog(true)
}
function cancel() { closeDialog(ui.dialog?.kind === 'prompt' ? null : false) }
</script>

<template>
  <div class="toasts" aria-live="polite">
    <div v-for="t in ui.toasts" :key="t.id" class="toast" :class="t.type">
      <Icon :name="t.type === 'error' ? 'alert' : 'check-circle'" />{{ t.message }}
    </div>
  </div>
  <Modal v-if="ui.dialog" :title="ui.dialog.title" @close="cancel">
    <form id="ui-dialog" class="stack" @submit.prevent="submit">
      <p v-if="ui.dialog.message" class="muted">{{ ui.dialog.message }}</p>
      <label v-if="ui.dialog.kind === 'prompt'" class="field">
        <span v-if="ui.dialog.label">{{ ui.dialog.label }}</span>
        <textarea v-if="ui.dialog.multiline" v-model="text" rows="3" :placeholder="ui.dialog.placeholder" autofocus />
        <input v-else v-model="text" :placeholder="ui.dialog.placeholder" autofocus />
      </label>
    </form>
    <template #foot>
      <button type="button" class="btn" @click="cancel">{{ ui.dialog.cancel }}</button>
      <button form="ui-dialog" class="btn" :class="ui.dialog.danger ? 'danger-solid' : 'primary'"
        :disabled="ui.dialog.kind === 'prompt' && ui.dialog.required && !text.trim()">{{ ui.dialog.ok }}</button>
    </template>
  </Modal>
</template>
