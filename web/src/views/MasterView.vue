<script setup>
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import { masters } from '../lib/masters'
import MasterTable from '../components/MasterTable.vue'
const route = useRoute()
const resource = computed(() => route.params.resource)
const tabs = ['pest-types', 'treatment-methods', 'chemicals', 'chemical-doses', 'equipment-types', 'building-types']
</script>

<template>
  <div>
    <h1>Data master</h1>
    <nav class="tabs">
      <router-link v-for="t in tabs" :key="t" :to="'/master/' + t">{{ masters[t].title }}</router-link>
    </nav>
    <MasterTable :resource="resource" :key="resource" />
  </div>
</template>
