<script setup>
// Pemindai QR memakai kamera + BarcodeDetector (Chrome Android). Jika tidak didukung, tampilkan pesan.
import { ref, onMounted, onUnmounted } from 'vue'
const emit = defineEmits(['detect'])
const video = ref(null)
const error = ref('')
const supported = 'BarcodeDetector' in window
let stream = null, timer = null, done = false

onMounted(async () => {
  if (!supported) { error.value = 'Browser ini belum bisa memindai QR. Pilih stasiun dari daftar, atau pakai Chrome terbaru di Android.'; return }
  try {
    stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' }, audio: false })
    video.value.srcObject = stream
    await video.value.play()
    const det = new window.BarcodeDetector({ formats: ['qr_code'] })
    const tick = async () => {
      if (done) return
      try {
        const codes = await det.detect(video.value)
        if (codes[0]?.rawValue) { done = true; emit('detect', codes[0].rawValue); return }
      } catch {}
      timer = setTimeout(tick, 250)
    }
    tick()
  } catch {
    error.value = 'Kamera tidak bisa dibuka. Izinkan akses kamera untuk situs ini.'
  }
})
onUnmounted(() => { done = true; clearTimeout(timer); stream?.getTracks().forEach((t) => t.stop()) })
</script>

<template>
  <div class="qr">
    <p v-if="error" class="notice">{{ error }}</p>
    <div v-else class="cam"><video ref="video" playsinline muted /><i class="frame" /></div>
  </div>
</template>

<style scoped>
.cam { position: relative; border-radius: 18px; overflow: hidden; background: #000; aspect-ratio: 1; }
video { width: 100%; height: 100%; object-fit: cover; display: block; }
.frame { position: absolute; inset: 18%; border: 3px solid var(--gold); border-radius: 18px; box-shadow: 0 0 0 999px rgba(0, 0, 0, .35); }
</style>
