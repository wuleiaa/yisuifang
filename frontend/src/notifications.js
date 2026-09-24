import { Capacitor } from '@capacitor/core'
import { LocalNotifications } from '@capacitor/local-notifications'
import { api } from './api'

/**
 * 安卓本地通知（C12）。
 *
 * 【为什么不用推送】本项目没有 FCM / 微信订阅消息资质，所以走"手机自己排程"：
 * 打开 App 时拉一次服务端的提醒计划，把未来的提醒写进系统闹钟
 * （LocalNotifications → Android AlarmManager），到点由系统弹窗，
 * App 没开着也会响（插件带开机恢复广播）。
 *
 * 【浏览器里必须是空操作】网页端没有本地通知能力，直接调用插件会抛错；
 * 所有入口都用 isNativeApp() 挡住，保证 H5 端一点不受影响。
 */

/** 本应用占用 2000–2999 这段通知 id，便于一次性清理旧排程 */
const ID_BASE = 2000
const ID_SPAN = 1000
const DEVICE_KEY = 'followup_device_id'

export function isNativeApp() {
  try {
    return Capacitor?.isNativePlatform?.() === true
  } catch {
    return false
  }
}

/** 设备标识：只用于服务端登记"哪些设备排了提醒"，不含任何个人信息 */
function deviceId() {
  let id = localStorage.getItem(DEVICE_KEY)
  if (!id) {
    id = 'd-' + Math.random().toString(36).slice(2, 10) + Date.now().toString(36)
    localStorage.setItem(DEVICE_KEY, id)
  }
  return id
}

/**
 * 同步提醒排程。返回 { skipped } 表示没做事（非安卓壳 / 没授权），
 * 返回 { scheduled } 表示排了多少条。
 */
export async function syncReminders() {
  if (!isNativeApp()) {
    return { skipped: 'not-native' }
  }

  let perm = await LocalNotifications.checkPermissions()
  if (perm.display !== 'granted') {
    perm = await LocalNotifications.requestPermissions()
  }
  if (perm.display !== 'granted') {
    return { skipped: 'permission-denied' }
  }

  const plan = await api.reminderPlan()
  const items = plan.items || []

  // 计划会变（任务完成了、改期了），所以先把这段 id 里旧的排程撤掉再重排，
  // 否则昨天的提醒还会按时响。
  const pending = await LocalNotifications.getPending()
  const mine = (pending.notifications || []).filter((n) => n.id >= ID_BASE && n.id < ID_BASE + ID_SPAN)
  if (mine.length) {
    await LocalNotifications.cancel({ notifications: mine.map((n) => ({ id: n.id })) })
  }

  if (items.length) {
    await LocalNotifications.schedule({
      notifications: items.slice(0, ID_SPAN).map((it, i) => ({
        id: ID_BASE + i,
        title: it.title,
        body: it.message,
        schedule: { at: new Date(it.notifyAt) },
        extra: { key: it.key, level: it.level, taskId: it.sampleTaskId }
      }))
    })
    try {
      // 回执：服务端据此把这些时点记成"已发送到设备"（也是审计）
      await api.reminderAck({ keys: items.map((it) => it.key), deviceId: deviceId(), platform: 'ANDROID' })
    } catch {
      // 回执失败不影响手机上的提醒，不打扰用户
    }
  }

  return { scheduled: items.length, dueToday: plan.dueTodayCount, overdue: plan.overdueCount }
}

let listenerBound = false

/** 点通知直接跳到那条任务；只绑定一次 */
export function bindNotificationTap() {
  if (!isNativeApp() || listenerBound) {
    return
  }
  listenerBound = true
  LocalNotifications.addListener('localNotificationActionPerformed', (event) => {
    const taskId = event?.notification?.extra?.taskId
    if (taskId) {
      window.location.hash = `#/task/${taskId}`
    }
  })
}
