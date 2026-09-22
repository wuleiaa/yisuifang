import { createRouter, createWebHashHistory } from 'vue-router'
import { getToken } from './api'

// hash 路由：将来用同一套代码打成小程序 / App 时，不需要服务端路由配置
const routes = [
  { path: '/', redirect: '/timeline' },
  { path: '/login', name: 'login', component: () => import('./views/Login.vue'), meta: { public: true } },
  { path: '/timeline', name: 'timeline', component: () => import('./views/Timeline.vue') },
  { path: '/task/:id', name: 'task', component: () => import('./views/TaskDetail.vue') },
  { path: '/reports', name: 'reports', component: () => import('./views/Reports.vue') },
  { path: '/me', name: 'me', component: () => import('./views/Me.vue') },
  { path: '/:pathMatch(.*)*', redirect: '/timeline' }
]

const router = createRouter({
  history: createWebHashHistory(),
  routes,
  scrollBehavior: () => ({ top: 0 })
})

router.beforeEach((to) => {
  if (to.meta.public) return true
  if (!getToken()) return { name: 'login' }
  return true
})

export default router
