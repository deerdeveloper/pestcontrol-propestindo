<script setup>
// Modal di desktop, bottom sheet di HP.
import { onMounted, onUnmounted } from 'vue'
import Icon from './Icon.vue'
const props = defineProps({ title: String, wide: Boolean, closable: { type: Boolean, default: true } })
const emit = defineEmits(['close'])
function onKey(e) { if (e.key === 'Escape' && props.closable) emit('close') }
onMounted(() => { document.addEventListener('keydown', onKey); document.body.style.overflow = 'hidden' })
onUnmounted(() => { document.removeEventListener('keydown', onKey); document.body.style.overflow = '' })
</script>

<template>
  <Teleport to="body">
    <div class="modal-wrap" @click.self="closable && emit('close')">
      <div class="modal" :class="{ wide }" role="dialog" aria-modal="true">
        <div class="grabber" />
        <div class="modal-head">
          <h2>{{ title }}</h2>
          <slot name="head" />
          <button v-if="closable" type="button" class="btn ghost icon sm" aria-label="Tutup" @click="emit('close')"><Icon name="x" /></button>
        </div>
        <div class="modal-body"><slot /></div>
        <div v-if="$slots.foot" class="modal-foot"><slot name="foot" /></div>
      </div>
    </div>
  </Teleport>
</template>
