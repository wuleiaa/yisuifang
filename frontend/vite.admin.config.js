import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { fileURLToPath } from 'node:url'

/**
 * 管理后台（桌面端）构建配置。
 *
 * 与医护端 / 患者端共用 frontend/node_modules，不额外安装依赖：
 *   npm run dev:admin    → http://127.0.0.1:5175
 *   npm run build:admin  → frontend/dist-admin
 */
export default defineConfig({
  // 【必须设置】管理后台部署在 /admin/ 子路径下。
  // Vite 默认把 index.html 里的资源写成绝对根路径 /assets/xxx.js，
  // 那样浏览器会去请求根路径的资源，被 nginx 当成医护端的文件，
  // 结果是"HTML 打开了但页面白屏"（实测踩过）。
  base: '/admin/',
  root: fileURLToPath(new URL('./admin', import.meta.url)),
  publicDir: fileURLToPath(new URL('./public', import.meta.url)),
  plugins: [vue()],
  server: {
    host: '127.0.0.1',
    port: 5175,
    proxy: {
      '/api': {
        target: 'http://127.0.0.1:8080',
        changeOrigin: true
      }
    }
  },
  build: {
    outDir: fileURLToPath(new URL('./dist-admin', import.meta.url)),
    emptyOutDir: true,
    minify: 'esbuild',
    chunkSizeWarningLimit: 800
  }
})
