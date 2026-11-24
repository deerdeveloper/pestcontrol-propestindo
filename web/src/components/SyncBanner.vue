<script setup>
// Jumlah data yang belum terkirim dan error sinkronisasi terakhir (aplikasi teknisi).
import { sync, run } from '../lib/tech/sync'
import Icon from './Icon.vue'
</script>

<template>
  <div v-if="sync.pending" class="syncb" :class="{ bad: sync.lastError && !sync.offline }">
    <Icon :name="sync.running ? 'refresh' : sync.offline ? 'cloud-off' : sync.lastError ? 'alert' : 'cloud-up'" :class="{ spin: sync.running }" />
    <div class="grow"><b>{{ sync.pending }} data belum terkirim</b><small>{{ sync.lastError || (sync.running ? 'Sedang mengirim…' : 'Tekan Kirim untuk mencoba sekarang') }}</small></div>
    <button class="btn sm" :disabled="sync.running" @click="run()">Kirim</button>
  </div>
</template>

<style scoped>
.syncb { display: flex; align-items: center; gap: 12px; padding: 12px 14px; border-radius: 16px; background: var(--gold-50); border: 1px solid var(--gold-100); color: #6d4c00; }
.syncb.bad { background: var(--red-50); border-color: #f6caca; color: var(--red); }
.syncb b { display: block; font-size: 14px; }
.syncb small { display: block; font-size: 12px; opacity: .9; word-break: break-word; }
</style>
