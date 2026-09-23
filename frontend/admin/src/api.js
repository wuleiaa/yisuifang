import axios from 'axios'
import { ref } from 'vue'

/**
 * 管理后台接口客户端。
 * token 单独存（admin_token），跟医护端 App 互不影响。
 */
const client = axios.create({ baseURL: '/api', timeout: 20000 })

const TOKEN_KEY = 'admin_token'
const PROFILE_KEY = 'admin_profile'

function readProfile() {
  const raw = sessionStorage.getItem(PROFILE_KEY)
  if (!raw) return null
  try {
    return JSON.parse(raw)
  } catch {
    return null
  }
}

/**
 * 用 ref 保存当前登录人。
 *
 * 【为什么不能只读 sessionStorage】App.vue 在登录前就已经渲染过一次，
 * 如果用 computed(() => getProfile()) 直接读存储，computed 没有任何响应式依赖，
 * 登录后不会再算一遍——侧边栏就会一直显示"管理员"而不是本人姓名。
 */
export const profileRef = ref(readProfile())

export function getToken() {
  return localStorage.getItem(TOKEN_KEY)
}

export function setSession(token, prof) {
  localStorage.setItem(TOKEN_KEY, token)
  sessionStorage.setItem(PROFILE_KEY, JSON.stringify(prof))
  profileRef.value = prof
}

export function clearSession() {
  localStorage.removeItem(TOKEN_KEY)
  sessionStorage.removeItem(PROFILE_KEY)
  profileRef.value = null
}

export function getProfile() {
  return profileRef.value
}

/** 改完密码后清掉"待改密"标记，否则路由守卫会一直把人挡在改密页 */
export function markPasswordChanged() {
  const p = readProfile()
  if (!p) return
  const next = { ...p, mustChangePassword: false }
  sessionStorage.setItem(PROFILE_KEY, JSON.stringify(next))
  profileRef.value = next
}

client.interceptors.request.use((config) => {
  const token = getToken()
  if (token) config.headers.Authorization = `Bearer ${token}`
  return config
})

let redirecting = false

client.interceptors.response.use(
  (response) => {
    const body = response.data
    if (body && typeof body.code === 'number') {
      if (body.code === 0) return body.data
      const err = new Error(body.message || '操作失败')
      err.code = body.code
      return Promise.reject(err)
    }
    return body
  },
  (error) => {
    const status = error.response?.status
    const body = error.response?.data
    if (status === 401 && !redirecting) {
      redirecting = true
      clearSession()
      setTimeout(() => {
        redirecting = false
        window.location.hash = '#/login'
      }, 50)
      return Promise.reject(new Error('登录已过期，请重新登录'))
    }
    // 41005：账号处于"必须先改初始密码"状态，后端只放行改密相关接口。
    // 常见于"管理员刚给别人重置了密码"。把人送到改密页，别让他对着一堆报错发呆。
    if (body?.code === 41005 && !redirecting) {
      redirecting = true
      setTimeout(() => {
        redirecting = false
        window.location.hash = '#/change-password'
      }, 50)
      return Promise.reject(new Error(body.message || '请先修改初始密码'))
    }

    const message =
      body?.message ||
      (status === 403 ? '没有管理权限' : null) ||
      (error.code === 'ECONNABORTED' ? '请求超时' : null) ||
      '网络异常，请稍后再试'
    const err = new Error(message)
    err.code = body?.code
    return Promise.reject(err)
  }
)

export const api = {
  login: (staffNo, password) => client.post('/auth/login', { staffNo, password }),
  /** 修改自己的密码（管理后台也需要，否则被要求改密的人无处可去） */
  changePassword: (oldPassword, newPassword) =>
    client.post('/auth/change-password', { oldPassword, newPassword }),
  overview: () => client.get('/admin/overview'),
  /** 质控看板（C13） */
  qc: () => client.get('/admin/qc'),
  roles: () => client.get('/admin/roles'),
  staff: (params) => client.get('/admin/staff', { params }),
  logins: (params) => client.get('/admin/logins', { params }),
  createStaff: (payload) => client.post('/admin/staff', payload),
  resetPassword: (id) => client.post(`/admin/staff/${id}/reset-password`),
  setStatus: (id, status) => client.post(`/admin/staff/${id}/status`, { status })
}

export default client
