<script setup>
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import { useAuth } from './stores/auth'
import AppLayout from './layouts/AppLayout.vue'
import TechLayout from './layouts/TechLayout.vue'
import UiHost from './components/UiHost.vue'
const auth = useAuth()
const route = useRoute()
const layout = computed(() => (route.meta.public || !auth.user ? null : route.meta.layout === 'tech' ? TechLayout : AppLayout))
</script>

<template>
  <component :is="layout" v-if="layout"><router-view :key="route.fullPath" /></component>
  <router-view v-else-if="route.meta.public" />
  <UiHost />
</template>
