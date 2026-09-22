import { ref } from 'vue'

/** 全局提示条 */
export const toastMessage = ref('')
let timer = null

export function toast(msg, ms = 2400) {
  toastMessage.value = msg
  clearTimeout(timer)
  timer = setTimeout(() => {
    toastMessage.value = ''
  }, ms)
}

/** 手机拨号：只拨号，不需要解密手机号 */
export function callPhone(masked) {
  toast(`正在拨打 ${masked}`)
}

/** 日期格式化：2026-09-15 */
export function fmtDate(v) {
  if (!v) return '—'
  return String(v).slice(0, 10)
}

/** 日期时间：09-15 09:00 */
export function fmtDateTime(v) {
  if (!v) return '—'
  const s = String(v).replace('T', ' ')
  return s.slice(5, 16)
}

export function genderLabel(t) {
  return t || ''
}

