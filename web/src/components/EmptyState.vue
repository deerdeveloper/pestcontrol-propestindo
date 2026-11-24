<script setup>
import Icon from './Icon.vue'
defineProps({ icon: { type: String, default: 'clipboard' }, title: String, text: String })
</script>
<template>
  <div class="empty-state">
    <div class="ic"><Icon :name="icon" /></div>
    <b>{{ title }}</b><span v-if="text">{{ text }}</span>
    <div v-if="$slots.default" style="margin-top: 14px"><slot /></div>
  </div>
</template>
