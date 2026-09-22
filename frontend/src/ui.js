import { ref } from 'vue'
import { api } from './api'

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

/** 当前设备能不能直接呼出（桌面浏览器不认 tel:） */
export function isMobileDevice() {
  const ua = (typeof navigator !== 'undefined' && navigator.userAgent) || ''
  return /Android|iPhone|iPad|iPod|Windows Phone|HarmonyOS|Mobile/i.test(ua)
}

/**
 * 把号码交给系统拨号器。
 *
 * 用"隐藏链接 click"而不是 window.location.href：
 *   - 微信/QQ 内置浏览器里直接改 location 经常被拦，链接点击更稳；
 *   - iOS Safari、Android Chrome、华为/小米自带浏览器都识别 tel:；
 *   - 不引入任何外部依赖，也不需要 App 壳。
 */
function openDialer(digits) {
  const a = document.createElement('a')
  a.href = `tel:${digits}`
  a.rel = 'noopener'
  a.style.display = 'none'
  document.body.appendChild(a)
  a.click()
  // 立刻摘掉：号码不该留在页面里，DOM 里也不留
  a.remove()
}

/**
 * 一键拨号。
 *
 * 【为什么要问后端要号码】
 *  界面上显示的永远是脱敏号码（138****5678），而 tel: 需要真实号码，
 *  只拿脱敏值去拨号就是"点了没反应"。所以先调 /dial：
 *  后端解密一次并**写审计**（谁、何时、拨给谁），再把号码交给拨号器。
 *
 * 【号码不落界面】
 *  拿到的完整号码只进拨号链接，不进 DOM 文本、不进提示语；
 *  提示里只出现脱敏值。"查看完整号码"（给人看）仍是另一条需要
 *  二次验证的路径，本函数不碰它。
 *
 * 【桌面兜底】
 *  桌面浏览器不认 tel:（点了没反应是护士报障的常见来源），
 *  所以桌面端明确提示"请在手机上操作"，而不是装作拨出去了。
 */
export async function callPhone(taskId, maskedHint) {
  let info
  try {
    info = await api.dialTask(taskId)
  } catch (e) {
    toast(e.message || '获取号码失败')
    return false
  }

  const digits = String(info.phone || '').replace(/[^\d+]/g, '')
  const masked = info.phoneMask || maskedHint || ''

  if (!digits) {
    toast('没有可拨打的号码')
    return false
  }

  if (isMobileDevice()) {
    openDialer(digits)
    toast(`正在呼出 ${masked}（本次拨号已记入审计）`, 3000)
    return true
  }

  toast('桌面浏览器无法直接拨号，请在手机上打开本页操作', 3600)
  return false
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
