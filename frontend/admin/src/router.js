import { createRouter, createWebHashHistory } from 'vue-router'
import { getToken, getProfile } from './api'

const routes = [
  { path: '/', redirect: '/accounts' },
  { path: '/login', name: 'login', component: () => import('./views/Login.vue'), meta: { public: true } },
  { path: '/overview', name: 'overview', component: () => import('./views/Overview.vue') },
  { path: '/accounts', name: 'accounts', component: () => import('./views/Accounts.vue') },
  { path: '/logins', name: 'logins', component: () => import('./views/Logins.vue') },
  { path: '/change-password', name: 'changePassword', component: () => import('./views/ChangePassword.vue') },
  { path: '/:pathMatch(.*)*', redirect: '/accounts' }
]

const router = createRouter({ history: createWebHashHistory(), routes, scrollBehavior: () => ({ top: 0 }) })

router.beforeEach((to) => {
  if (to.meta.public) return true
  if (!getToken()) return { name: 'login' }
  // 处于"必须先改密"状态的人，只能待在改密页
  if (getProfile()?.mustChangePassword && to.name !== 'changePassword') {
    return { name: 'changePassword' }
  }
  return true
})

export default router
