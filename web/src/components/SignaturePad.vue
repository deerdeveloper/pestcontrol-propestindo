<script setup>
// Kanvas tanda tangan (jari/stylus/mouse). Hasil PNG berlatar putih lewat toBlob().
import { ref, onMounted, onUnmounted } from 'vue'
const emit = defineEmits(['change'])
const canvas = ref(null)
const empty = ref(true)
let ctx, drawing = false, last = null

function setup() {
  const c = canvas.value
  const r = c.getBoundingClientRect()
  const dpr = Math.max(1, window.devicePixelRatio || 1)
  c.width = Math.round(r.width * dpr)
  c.height = Math.round(r.height * dpr)
  ctx = c.getContext('2d')
  ctx.scale(dpr, dpr)
  ctx.fillStyle = '#fff'
  ctx.fillRect(0, 0, r.width, r.height)
  ctx.lineCap = 'round'
  ctx.lineJoin = 'round'
  ctx.strokeStyle = '#0b1f3a'
  ctx.lineWidth = 2.6
}
function pos(e) {
  const r = canvas.value.getBoundingClientRect()
  return { x: e.clientX - r.left, y: e.clientY - r.top }
}
function down(e) { drawing = true; last = pos(e); canvas.value.setPointerCapture(e.pointerId); dot(last) }
function dot(p) { ctx.beginPath(); ctx.arc(p.x, p.y, 1.2, 0, Math.PI * 2); ctx.fillStyle = ctx.strokeStyle; ctx.fill(); mark() }
function move(e) {
  if (!drawing) return
  const p = pos(e)
  ctx.beginPath(); ctx.moveTo(last.x, last.y); ctx.lineTo(p.x, p.y); ctx.stroke()
  last = p
  mark()
}
function up() { drawing = false }
function mark() { if (empty.value) { empty.value = false; emit('change', false) } }
function clear() { setup(); empty.value = true; emit('change', true) }
const toBlob = () => new Promise((res) => canvas.value.toBlob(res, 'image/png'))
defineExpose({ clear, toBlob, empty })
// Ukuran layar berubah (mis. keyboard HP muncul): kanvas disiapkan ulang hanya bila masih kosong.
const onResize = () => { if (empty.value) setup() }
onMounted(() => { setup(); addEventListener('resize', onResize) })
onUnmounted(() => removeEventListener('resize', onResize))
</script>

<template>
  <div class="sigpad">
    <canvas ref="canvas" @pointerdown.prevent="down" @pointermove.prevent="move" @pointerup="up" @pointercancel="up" @pointerleave="up" />
    <span v-if="empty" class="ph">Tanda tangan di sini</span>
    <i class="baseline" />
  </div>
</template>

<style scoped>
.sigpad { position: relative; border: 1.5px dashed #b7c6bd; border-radius: 16px; background: #fff; overflow: hidden; }
canvas { display: block; width: 100%; height: 240px; touch-action: none; cursor: crosshair; }
.ph { position: absolute; inset: 0; display: grid; place-items: center; color: #a7b6ad; font-weight: 600; pointer-events: none; }
.baseline { position: absolute; left: 24px; right: 24px; bottom: 54px; border-bottom: 1px solid #e3e9e5; pointer-events: none; }
</style>
