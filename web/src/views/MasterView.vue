<script setup>
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import { masters } from '../lib/masters'
import MasterTable from '../components/MasterTable.vue'
import Icon from '../components/Icon.vue'
const route = useRoute()
const resource = computed(() => route.params.resource)
const tabs = [
  ['pest-types', 'bug'], ['treatment-methods', 'spray'], ['chemicals', 'flask'], ['chemical-doses', 'tag'],
  ['equipment-types', 'radar'], ['building-types', 'building'],
]
</script>

<template>
  <div class="page">
    <div class="page-head"><div class="t"><h1>Data master</h1><p>Daftar pilihan yang dipakai teknisi saat mengisi laporan.</p></div></div>
    <nav class="tabs">
      <router-link v-for="[t, ic] in tabs" :key="t" :to="'/master/' + t"><Icon :name="ic" />{{ masters[t].title }}</router-link>
    </nav>
    <MasterTable :resource="resource" :key="resource" />
  </div>
</template>
