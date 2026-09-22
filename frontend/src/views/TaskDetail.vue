<script setup>
import { ref, onMounted, computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { api } from '../api'
import { toastMessage, toast, fmtDate, fmtDateTime, callPhone } from '../ui'

const route = useRoute()
const router = useRouter()
const taskId = route.params.id

const loading = ref(true)
const submitting = ref(false)
const detail = ref(null)

/** 被同事占锁：仍然能看到任务信息，但提交时后端会拦（30 分钟后锁自动失效） */
const lockedByOther = ref(false)

/** 危险症状：勾选后立即弹窗，不等表单填完 —— 第 7 轮定的规则 */
const DANGER = ['呕血', '黑便', '便血', '发热', '黄疸', '剧烈腹痛', '明显异常']
const SYMPTOMS = ['腹痛', '便血', '呕血', '黑便', '发热', '黄疸', '恶心呕吐', '无明显症状']

/** 常用语模板：点一下填入结论栏，护士只需微调（目标：30 秒填完） */
const TEMPLATES = {
  '恢复良好': '患者自述恢复良好，无腹痛、便血、呕血、黑便、发热等不适，饮食睡眠正常。',
  '已告知低脂': '已告知低脂饮食，避免油炸食品、肥肉、蛋黄及动物内脏。',
  '已告知饮食': '已告知注意清淡饮食、少食多餐，禁食辛辣刺激及烟酒。',
  '已告知用药': '已告知按时服药，疗程未结束不可自行停药，如有不适及时就诊。',
  '提醒复查': '已提醒按期门诊复查，建议提前在公众号预约挂号。',
  '告知急诊': '已告知如出现呕血、黑便、剧烈腹痛、高热、皮肤眼睛发黄，请立即急诊就诊。',
  '需医生判断': '患者所述情况已记录，将转达主管医生进一步判断。',
  '联系家属': '未联系到患者本人，已与家属沟通并请其转达。'
}

const form = ref({
  contacted: true,
  contactTarget: '本人',
  durationSeconds: null,
  symptoms: ['无明显症状'],
  recoveryLevel: 'GOOD',
  medicationAdherence: '按时服药',
  conclusion: '',
  advice: '',
  nextAction: 'CONTINUE'
})

const urgentVisible = ref(false)
const urgentSymptom = ref('')
const submitted = ref(false)

/** 连点两下会申请两次号码、写两条审计，这里挡一下 */
const dialing = ref(false)

const isAbnormal = computed(
  () => form.value.symptoms.some((s) => DANGER.includes(s)) || form.value.recoveryLevel === 'ABNORMAL'
)

async function load() {
  loading.value = true
  try {
    // 打开任务即抢占锁。两位护士同时给同一位患者打电话是真实会发生的事，
    // 后端 claim 接口就是为此设计的；这里不调用它，锁就形同虚设。
    detail.value = await api.claimTask(taskId)
  } catch (e) {
    if (e.code === 42005) {
      // 被占用不是错误，只是提示；先把任务信息读出来给护士看
      lockedByOther.value = true
      try {
        detail.value = await api.taskDetail(taskId)
      } catch (e2) {
        toast(e2.message)
      }
    } else {
      toast(e.message)
    }
  } finally {
    loading.value = false
  }
}

function pick(field, value) {
  form.value[field] = value
}

function toggleSymptom(s) {
  const list = form.value.symptoms
  const idx = list.indexOf(s)

  // 勾选任何症状时，都要取消"无明显症状"——两者逻辑互斥
  const removeNoSymptom = () => {
    const i = list.indexOf('无明显症状')
    if (i !== -1) list.splice(i, 1)
  }

  if (DANGER.includes(s)) {
    // 危险症状：立即弹窗，不用等提交
    if (idx === -1) {
      removeNoSymptom()
      list.push(s)
    }
    urgentSymptom.value = s
    urgentVisible.value = true
    return
  }

  // 非危险症状：与"无明显症状"互斥
  if (s === '无明显症状') {
    form.value.symptoms = idx === -1 ? ['无明显症状'] : []
    return
  }
  if (idx === -1) {
    removeNoSymptom()
    list.push(s)
  } else {
    list.splice(idx, 1)
  }
}

function useTemplate(text) {
  form.value.conclusion = form.value.conclusion
    ? `${form.value.conclusion}${text}`
    : text
}

async function onDial() {
  if (dialing.value || !detail.value) return
  dialing.value = true
  try {
    await callPhone(taskId, detail.value.phoneMask)
  } finally {
    dialing.value = false
  }
}

async function submit(notifyDoctor) {
  if (submitting.value) return
  if (!form.value.contacted) {
    // 未接通也要提交，记录"未接听"并安排重拨
  } else if (!form.value.conclusion.trim()) {
    toast('请填写回访结论')
    return
  }

  submitting.value = true
  try {
    const res = await api.completeTask({
      taskId: Number(taskId),
      contacted: form.value.contacted,
      contactTarget: form.value.contactTarget,
      durationSeconds: form.value.durationSeconds,
      symptoms: form.value.symptoms,
      recoveryLevel: form.value.recoveryLevel,
      medicationAdherence: form.value.medicationAdherence,
      conclusion: form.value.conclusion,
      advice: form.value.advice,
      nextAction: form.value.nextAction,
      notifyDoctorImmediately: !!notifyDoctor
    })
    submitted.value = true
    toast(res.message || '回访记录已提交')
    setTimeout(() => router.replace('/todo'), 900)
  } catch (e) {
    toast(e.message || '提交失败')
  } finally {
    submitting.value = false
    urgentVisible.value = false
  }
}

function onUrgentNotify() {
  urgentVisible.value = false
  // 立即上报：不等表单填完，直接提交并通知医生
  if (!form.value.conclusion.trim()) {
    form.value.conclusion = `电话回访中患者报告「${urgentSymptom.value}」，已立即通知主管医生。`
  }
  form.value.recoveryLevel = 'ABNORMAL'
  submit(true)
}

function onUrgentIgnore() {
  urgentVisible.value = false
}

onMounted(load)
</script>

<template>
  <div class="page">
    <header class="appbar">
      <button class="iconbtn" type="button" @click="router.back()">‹</button>
      <h1>回访任务<span class="sub" v-if="detail">{{ detail.title }}</span></h1>
    </header>

    <div v-if="loading" class="loading">加载中…</div>

    <template v-else-if="detail">
      <!-- 患者信息 -->
      <section class="card m14">
        <div class="row-between">
          <div>
            <div style="font-size: 18px; font-weight: 600">
              {{ detail.patientName }}
              <span class="muted">{{ detail.genderText }} · {{ detail.age }}岁</span>
            </div>
            <div class="muted mt8">
              病案号 {{ detail.medicalRecordNo || '—' }} · 住院号 {{ detail.inpatientNo }}
            </div>
          </div>
          <span v-if="detail.overdueDays > 0" class="chip red">逾期 {{ detail.overdueDays }} 天</span>
          <span v-else class="chip blue">今日</span>
        </div>

        <div class="mt12">
          <div class="kv"><span class="k">随访路径</span><span class="v">{{ detail.pathwayLabel || '—' }}</span></div>
          <div class="kv" v-if="detail.procedureName">
            <span class="k">手术/操作</span>
            <span class="v">{{ detail.procedureName }}<br /><span class="muted">{{ fmtDateTime(detail.procedureDate) }}</span></span>
          </div>
          <div class="kv"><span class="k">出院诊断</span><span class="v">{{ (detail.diagnoses || []).join('、') || '—' }}</span></div>
          <div class="kv"><span class="k">住院时间</span><span class="v">{{ fmtDate(detail.admitDate) }} ~ {{ fmtDate(detail.dischargeDate) }}</span></div>
          <div class="kv"><span class="k">任务要求</span><span class="v">{{ detail.contentHint || '按科室随访规范执行' }}</span></div>
        </div>
      </section>

      <!-- 联系与拨号 -->
      <div class="m14" style="display: flex; gap: 10px">
        <button
          class="btn-primary"
          style="flex: 1; padding: 14px"
          type="button"
          :disabled="dialing"
          @click="onDial"
        >
          <svg viewBox="0 0 24 24" style="width:17px;height:17px;margin-right:6px;stroke:currentColor;fill:none;stroke-width:1.6;stroke-linecap:round;stroke-linejoin:round;vertical-align:-3px">
            <path d="M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3.1 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.1 4.2 2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7c.1 1 .4 2 .7 2.9a2 2 0 0 1-.5 2.1L8.1 9.9a16 16 0 0 0 6 6l1.2-1.2a2 2 0 0 1 2.1-.5c.9.3 1.9.6 2.9.7a2 2 0 0 1 1.7 2z" />
          </svg>
          一键拨号 {{ detail.phoneMask }}
        </button>
        <button class="btn-ghost" type="button" @click="toast('查看完整号码需二次验证，操作会记入审计日志')">
          <svg viewBox="0 0 24 24" style="width:17px;height:17px;margin-right:6px;stroke:currentColor;fill:none;stroke-width:1.6;stroke-linecap:round;stroke-linejoin:round;vertical-align:-3px">
            <path d="M1.5 12S5 5.5 12 5.5 22.5 12 22.5 12S19 18.5 12 18.5 1.5 12 1.5 12z" /><circle cx="12" cy="12" r="3" />
          </svg>
          完整号码
        </button>
      </div>

      <div v-if="isAbnormal" class="notice warn">
        已勾选危险症状，提交后系统将立即通知主管医生。
      </div>

      <div v-if="lockedByOther" class="notice warn">
        该任务正在被其他同事处理。为避免重复打扰患者，建议先与同事确认；
        若确认无人处理（超过 30 分钟），可直接提交。
      </div>

      <!-- 回访表单 -->
      <section class="card m14">
        <div style="font-size: 15px; font-weight: 600; margin-bottom: 16px">回访记录</div>

        <div class="form-row">
          <label>是否接通 <span class="req">*</span></label>
          <div class="opts">
            <div class="opt" :class="{ on: form.contacted === true }" @click="pick('contacted', true)">已接通</div>
            <div class="opt" :class="{ on: form.contacted === false }" @click="pick('contacted', false)">未接听</div>
          </div>
        </div>

        <div class="form-row">
          <label>联系的是</label>
          <div class="opts">
            <div class="opt" :class="{ on: form.contactTarget === '本人' }" @click="pick('contactTarget', '本人')">本人</div>
            <div class="opt" :class="{ on: form.contactTarget === '家属' }" @click="pick('contactTarget', '家属')">家属</div>
          </div>
        </div>

        <div class="form-row">
          <label>有无以下症状（可多选）<span class="req">*</span></label>
          <div class="opts">
            <div
              v-for="s in SYMPTOMS"
              :key="s"
              class="opt"
              :class="{
                on: form.symptoms.includes(s),
                danger: form.symptoms.includes(s) && DANGER.includes(s)
              }"
              @click="toggleSymptom(s)"
            >
              {{ s }}
            </div>
          </div>
        </div>

        <div class="form-row">
          <label>恢复情况</label>
          <div class="opts">
            <div class="opt" :class="{ on: form.recoveryLevel === 'GOOD' }" @click="pick('recoveryLevel', 'GOOD')">恢复良好</div>
            <div class="opt" :class="{ on: form.recoveryLevel === 'MILD' }" @click="pick('recoveryLevel', 'MILD')">轻度不适</div>
            <div class="opt danger" :class="{ on: form.recoveryLevel === 'ABNORMAL' }" @click="pick('recoveryLevel', 'ABNORMAL')">明显异常</div>
          </div>
        </div>

        <div class="form-row">
          <label>用药依从性</label>
          <div class="opts">
            <div class="opt" :class="{ on: form.medicationAdherence === '按时服药' }" @click="pick('medicationAdherence', '按时服药')">按时服药</div>
            <div class="opt" :class="{ on: form.medicationAdherence === '偶尔漏服' }" @click="pick('medicationAdherence', '偶尔漏服')">偶尔漏服</div>
            <div class="opt" :class="{ on: form.medicationAdherence === '已自行停药' }" @click="pick('medicationAdherence', '已自行停药')">已自行停药</div>
          </div>
        </div>

        <div class="form-row">
          <label>结论与指导 <span class="req">*</span></label>
          <div class="tpl-row">
            <div v-for="(text, name) in TEMPLATES" :key="name" class="tpl" @click="useTemplate(text)">
              {{ name }}
            </div>
          </div>
          <textarea v-model="form.conclusion" placeholder="点上方常用语快速填入，或手动输入…"></textarea>
        </div>

        <div class="form-row">
          <label>补充指导（选填）</label>
          <textarea v-model="form.advice" placeholder="如饮食、复诊、注意事项…" style="height: 72px"></textarea>
        </div>

        <div class="form-row">
          <label>下一步</label>
          <div class="opts">
            <div class="opt" :class="{ on: form.nextAction === 'CONTINUE' }" @click="pick('nextAction', 'CONTINUE')">继续原计划</div>
            <div class="opt" :class="{ on: form.nextAction === 'ADVANCE_VISIT' }" @click="pick('nextAction', 'ADVANCE_VISIT')">提前复诊</div>
            <div class="opt warn" :class="{ on: form.nextAction === 'ESCALATE' }" @click="pick('nextAction', 'ESCALATE')">上报医生</div>
          </div>
        </div>
      </section>

      <div class="m14">
        <button
          class="btn-primary btn-block"
          type="button"
          :disabled="submitting || submitted"
          @click="submit(false)"
        >
          {{ submitting ? '提交中…' : '提交回访记录' }}
        </button>
      </div>
    </template>

    <!-- 危险症状：立即通知医生（不等表单填完） -->
    <div v-if="urgentVisible" class="mask center">
      <div class="dialog">
        <svg viewBox="0 0 24 24" style="width:40px;height:40px;stroke:var(--danger);fill:none;stroke-width:1.3;stroke-linecap:round;stroke-linejoin:round">
          <path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z" /><path d="M12 9v4M12 17h.01" />
        </svg>
        <h3 style="color: var(--danger); margin-top: 10px">发现异常症状</h3>
        <p>
          患者：{{ detail?.patientName }}（{{ detail?.genderText }} {{ detail?.age }}岁）<br />
          症状：<b style="color: var(--danger)">{{ urgentSymptom }}</b>
        </p>
        <p style="font-size: 12.5px">不需要填完表单即可通知，系统会同时生成紧急任务。</p>
        <div class="row2">
          <button class="no" type="button" @click="onUrgentIgnore">仅记录</button>
          <button class="yes" type="button" @click="onUrgentNotify">立即通知医生</button>
        </div>
      </div>
    </div>
  </div>

  <div v-if="toastMessage" class="toast">{{ toastMessage }}</div>
</template>
