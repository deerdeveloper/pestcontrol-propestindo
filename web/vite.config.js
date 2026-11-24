import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { VitePWA } from 'vite-plugin-pwa'

export default defineConfig({
  plugins: [
    vue(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['logo.png', 'favicon.ico', 'favicon.svg', 'apple-touch-icon.png'],
      manifest: {
        name: 'Propestindo - Laporan Pest Control',
        short_name: 'Propestindo',
        description: 'Sistem laporan kunjungan pest control Propestindo',
        theme_color: '#14532d',
        background_color: '#ffffff',
        display: 'standalone',
        start_url: '/',
        icons: [
          { src: 'icon-192.png', sizes: '192x192', type: 'image/png' },
          { src: 'icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
          { src: 'icon-maskable-192.png', sizes: '192x192', type: 'image/png', purpose: 'maskable' },
          { src: 'icon-maskable-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
        ],
      },
      workbox: {
        // Data API tidak di-cache oleh service worker; hanya aset aplikasi.
        navigateFallbackDenylist: [/^\/api/],
      },
    }),
  ],
  server: {
    proxy: { '/api': 'http://localhost:8080' },
  },
})
