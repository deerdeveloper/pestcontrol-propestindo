<script setup>
import { ref, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { api } from '../lib/api'
import MasterTable from '../components/MasterTable.vue'
const route = useRoute()
const site = ref(null)
const tab = ref('areas')
onMounted(async () => { site.value = await api('/master/sites/' + route.params.id) })
</script>

<template>
  <div v-if="site">
    <router-link :to="'/customers/' + site.customer_id" class="muted">← Pelanggan</router-link>
    <h1>{{ site.name }}</h1>
    <p class="muted">{{ site.address }}</p>
    <nav class="tabs">
      <a href="#" :class="{ active: tab === 'areas' }" @click.prevent="tab = 'areas'">Area</a>
      <a href="#" :class="{ active: tab === 'stations' }" @click.prevent="tab = 'stations'">Stasiun monitoring</a>
      <a href="#" :class="{ active: tab === 'site-contacts' }" @click.prevent="tab = 'site-contacts'">Kontak PIC</a>
    </nav>
    <MasterTable :resource="tab" :fixed="{ site_id: site.id }" :key="tab" />
    <p v-if="tab === 'stations'" class="muted">Isi QR dicetak sebagai stiker dan ditempel di alat. Teknisi memindainya di aplikasi HP.</p>
  </div>
</template>
