<script setup>
import MasterTable from '../components/MasterTable.vue'
</script>
<template>
  <div>
    <h1>Pelanggan</h1>
    <MasterTable resource="customers" :link-to="(c) => '/customers/' + c.id" />
  </div>
</template>
