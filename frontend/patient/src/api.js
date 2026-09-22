import axios from 'axios'

/**
 * 患者端接口客户端。
 *
 * 与医护端分开存 token（portal_token），这样同一台手机上
 * 同时开着医护端和患者端调试也不会互相顶掉登录态。
 */
const client = axios.create({ baseURL: '/api/portal', timeout: 20000 })

const TOKEN_KEY = 'portal_token'
const PROFILE_KEY = 'portal_profile'

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
      return Promise.reject(new Error(body.message || '操作失败'))
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

    const message =
      body?.message ||
      (status === 403 ? '没有权限查看' : null) ||
      (error.code === 'ECONNABORTED' ? '网络较慢，请稍后再试' : null) ||
      '网络异常，请稍后再试'
    return Promise.reject(new Error(message))
  }
)

export const api = {
  sendCode: (phone) => client.post('/auth/code', { phone }),
  login: (phone, code) => client.post('/auth/login', { phone, code }),
  me: () => client.get('/me'),
  timeline: () => client.get('/timeline'),
  reports: () => client.get('/reports'),
  task: (id) => client.get(`/tasks/${id}`),
  questionnaire: () => client.get('/questionnaire'),
  submitQuestionnaire: (taskId, answers) =>
    client.post(`/tasks/${taskId}/questionnaire`, { answers })
}

export default client
