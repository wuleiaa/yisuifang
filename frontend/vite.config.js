import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  server: {
    host: '127.0.0.1',
    port: 5173,
    // 后端接口代理，前端不需要处理跨域
    proxy: {
      '/api': {
        target: 'http://127.0.0.1:8080',
        changeOrigin: true
      }
    }
  },
  build: {
    outDir: 'dist',
    // 老机器上降低构建并发，避免风扇狂转
    minify: 'esbuild',
    chunkSizeWarningLimit: 800
  }
})

