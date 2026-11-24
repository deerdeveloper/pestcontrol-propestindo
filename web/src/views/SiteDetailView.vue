<script setup>
import { ref, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { api } from '../lib/api'
import MasterTable from '../components/MasterTable.vue'
import Icon from '../components/Icon.vue'
const route = useRoute()
const site = ref(null)
const tab = ref('areas')
onMounted(async () => { site.value = await api('/master/sites/' + route.params.id) })
const tabs = [['areas', 'Area', 'layers'], ['stations', 'Stasiun monitoring', 'radar'], ['site-contacts', 'Kontak PIC', 'phone']]
</script>

<template>
  <div v-if="site" class="page">
    <div class="page-head">
      <div class="t">
        <router-link :to="'/customers/' + site.customer_id" class="back"><Icon name="arrow-left" />Pelanggan</router-link>
        <h1>{{ site.name }}</h1>
        <p class="row" style="gap: 6px"><Icon name="map-pin" />{{ site.address }}</p>
      </div>
    </div>
    <nav class="tabs">
      <button v-for="[k, l, ic] in tabs" :key="k" :class="{ active: tab === k }" @click="tab = k"><Icon :name="ic" />{{ l }}</button>
    </nav>
    <p v-if="tab === 'stations'" class="notice blue" style="margin-bottom: 14px"><Icon name="qr" />Isi QR dicetak sebagai stiker dan ditempel di alat. Teknisi memindainya dari aplikasi HP atau web.</p>
    <MasterTable :resource="tab" :fixed="{ site_id: site.id }" :key="tab" />
  </div>
</template>
