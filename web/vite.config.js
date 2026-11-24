import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { VitePWA } from 'vite-plugin-pwa'

export default defineConfig({
  // Aplikasi web disajikan di /app/; halaman publik (landing page) ada di "/" (backend Go).
  base: '/app/',
  plugins: [
    vue(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['logo.png', 'emblem.svg', 'favicon.ico', 'favicon.svg', 'apple-touch-icon.png'],
      manifest: {
        name: 'Propestindo - Laporan Pest Control',
        lang: 'id',
        short_name: 'Propestindo',
        description: 'Sistem laporan kunjungan pest control Propestindo',
        theme_color: '#062616',
        background_color: '#ffffff',
        display: 'standalone',
        start_url: '/app/',
        orientation: 'portrait',
        shortcuts: [{ name: 'Jadwal teknisi', url: '/app/tech' }, { name: 'Dashboard admin', url: '/app/dashboard' }],
        scope: '/app/',
        id: '/app/',
        icons: [
          { src: 'icon-192.png', sizes: '192x192', type: 'image/png' },
          { src: 'icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
          { src: 'icon-maskable-192.png', sizes: '192x192', type: 'image/png', purpose: 'maskable' },
          { src: 'icon-maskable-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
        ],
      },
      workbox: {
        // Font & ikon ikut di-cache supaya aplikasi teknisi tetap terbuka saat offline.
        globPatterns: ['**/*.{js,css,html,ico,png,svg,woff2,webmanifest}'],
        // Data API tidak di-cache oleh service worker; hanya aset aplikasi.
        navigateFallback: '/app/index.html',
        navigateFallbackDenylist: [/^\/api/],
      },
    }),
  ],
  server: {
    proxy: { '/api': 'http://localhost:8080', '/site': 'http://localhost:8080' },
  },
})
