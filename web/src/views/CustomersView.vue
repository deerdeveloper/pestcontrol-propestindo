<script setup>
import MasterTable from '../components/MasterTable.vue'
</script>
<template>
  <div class="page">
    <div class="page-head"><div class="t"><h1>Pelanggan & lokasi</h1><p>Data perusahaan pelanggan. Buka detail untuk mengatur lokasi, area, stasiun, dan akun portal.</p></div></div>
    <MasterTable resource="customers" :link-to="(c) => '/customers/' + c.id" />
  </div>
</template>
