<script setup>
import { visitStatus } from '../lib/labels'
defineProps({ status: String })
</script>
<template><span class="badge" :class="status">{{ visitStatus[status] || status }}</span></template>
