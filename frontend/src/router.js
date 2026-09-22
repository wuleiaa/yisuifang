import { createRouter, createWebHashHistory } from 'vue-router'
import { getToken, getProfile } from './api'

// 使用 hash 模式：打包成安卓 App 后不需要服务端路由配置，
// 直接本地文件也能跑，避免"白屏"这类部署问题。
const routes = [
  { path: '/', redirect: '/todo' },
  { path: '/login', name: 'login', component: () => import('./views/Login.vue'), meta: { public: true, plain: true } },
  { path: '/todo', name: 'todo', component: () => import('./views/Todo.vue'), meta: { title: '待办' } },
  { path: '/task/:id', name: 'task', component: () => import('./views/TaskDetail.vue'), meta: { title: '回访任务' } },
  { path: '/patients', name: 'patients', component: () => import('./views/Patients.vue'), meta: { title: '患者' } },
  { path: '/patient/:id', name: 'patient', component: () => import('./views/PatientDetail.vue'), meta: { title: '患者详情' } },
  { path: '/me', name: 'me', component: () => import('./views/Me.vue'), meta: { title: '我的' } },
  {
    path: '/change-password',
    name: 'changePassword',
    component: () => import('./views/ChangePassword.vue'),
    meta: { title: '修改密码' }
  },
  { path: '/:pathMatch(.*)*', redirect: '/todo' }
]

const router = createRouter({
  history: createWebHashHistory(),
  routes,
  scrollBehavior: () => ({ top: 0 })
})

router.beforeEach((to) => {
  if (to.meta.public) return true
  if (!getToken()) {
    return { name: 'login', query: { redirect: to.fullPath } }
  }
  // 首次登录 / 被管理员重置过密码的人，必须先改密码才能用系统。
  // 放在路由守卫里而不是页面上，是为了防止直接敲地址绕过去。
  const profile = getProfile()
  if (profile?.mustChangePassword && to.name !== 'changePassword') {
    return { name: 'changePassword' }
  }
  return true
})

export default router
