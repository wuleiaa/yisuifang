import axios from 'axios'

/**
 * 统一的接口客户端。
 *
 * 后端统一返回 { code, message, data }：
 *   code === 0  表示成功，直接返回 data
 *   其他        抛出带 message 的错误，由调用方提示
 *
 * 401 时清除本地登录态并跳回登录页——避免用户卡在"点了没反应"的状态。
 */
const client = axios.create({
  baseURL: '/api',
  timeout: 20000
})

export const TOKEN_KEY = 'followup_token'
export const PROFILE_KEY = 'followup_profile'

export function getToken() {
  return localStorage.getItem(TOKEN_KEY)
}

export function setSession(token, profile) {
  localStorage.setItem(TOKEN_KEY, token)
  sessionStorage.setItem(PROFILE_KEY, JSON.stringify(profile))
}

export function clearSession() {
  localStorage.removeItem(TOKEN_KEY)
  sessionStorage.removeItem(PROFILE_KEY)
}

export function getProfile() {
  const raw = sessionStorage.getItem(PROFILE_KEY)
  if (!raw) return null
  try {
    return JSON.parse(raw)
  } catch {
    return null
  }
}

/** 改完密码后清掉"待改密"标记，否则路由守卫会一直把人挡在改密页 */
export function markPasswordChanged() {
  const p = getProfile()
  if (p) {
    sessionStorage.setItem(PROFILE_KEY, JSON.stringify({ ...p, mustChangePassword: false }))
  }
}

client.interceptors.request.use((config) => {
  const token = getToken()
  if (token) {
    config.headers.Authorization = `Bearer ${token}`
  }
  return config
})

let redirecting = false

client.interceptors.response.use(
  (response) => {
    const body = response.data
    if (body && typeof body.code === 'number') {
      if (body.code === 0) {
        return body.data
      }
      // 把业务错误码一起带上：界面需要区分"被同事占锁"这类可预期的情况
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
    // 走到这里通常是"会话还在，但管理员刚重置过密码"——把人送到改密页，
    // 别让他对着一堆接口报错发呆。
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
      (status === 403 ? '没有权限执行该操作' : null) ||
      (error.code === 'ECONNABORTED' ? '请求超时，请检查网络' : null) ||
      '网络异常，请稍后再试'

    const err = new Error(message)
    err.code = body?.code
    return Promise.reject(err)
  }
)

export const api = {
  login: (staffNo, password) => client.post('/auth/login', { staffNo, password }),
  me: () => client.get('/auth/me'),
  cryptoCheck: () => client.get('/auth/crypto-check'),
  changePassword: (oldPassword, newPassword) =>
    client.post('/auth/change-password', { oldPassword, newPassword }),

  todo: (scope = 'MINE', days = 7, limit = 100) =>
    client.get('/tasks/todo', { params: { scope, days, limit } }),
  taskDetail: (id) => client.get(`/tasks/${id}`),
  claimTask: (id) => client.post(`/tasks/${id}/claim`),
  // 一键拨号：后端解密并写审计，只把号码交给系统拨号器，不要渲染到页面上
  dialTask: (id) => client.post(`/tasks/${id}/dial`),
  // 历史回访（C9）：同一患者以前的回访记录，第二次回访时参考
  taskHistory: (id) => client.get(`/tasks/${id}/history`),
  completeTask: (payload) => client.post('/tasks/complete', payload),

  patients: (keyword, limit = 50) =>
    client.get('/patients', { params: { keyword, limit } }),
  patientDetail: (id) => client.get(`/patients/${id}`)
}

export default client
