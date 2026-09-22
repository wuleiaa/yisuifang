import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { fileURLToPath } from 'node:url'

/**
 * 患者端（手机 H5）独立构建配置。
 *
 * 与医护端共用 frontend/node_modules，不额外安装依赖：
 *   npm run dev:patient    → http://127.0.0.1:5174
 *   npm run build:patient  → frontend/dist-patient
 *
 * 端口与医护端分开，是为了两台机器/两个窗口同时开着调试时不打架。
 */
export default defineConfig({
  // 【必须设置】患者端部署在 /patient/ 子路径下，理由同管理后台。
  base: '/patient/',
  // 用绝对路径解析：这样从哪个目录执行 npm 都能构建
  root: fileURLToPath(new URL('./patient', import.meta.url)),
  // 与医护端共用同一个 public 目录，照片只存一份
  publicDir: fileURLToPath(new URL('./public', import.meta.url)),
  plugins: [vue()],
  server: {
    host: '127.0.0.1',
    port: 5174,
    proxy: {
      '/api': {
        target: 'http://127.0.0.1:8080',
        changeOrigin: true
      }
    }
  },
  build: {
    outDir: fileURLToPath(new URL('./dist-patient', import.meta.url)),
    emptyOutDir: true,
    minify: 'esbuild',
    chunkSizeWarningLimit: 800
  }
})
