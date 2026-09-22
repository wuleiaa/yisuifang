<script setup>
import { ref, onMounted } from 'vue'
import { api } from '../api'

const list = ref([])
const keyword = ref('')
const loading = ref(false)
const error = ref('')

async function load() {
  loading.value = true
  error.value = ''
  try {
    list.value = await api.logins({ keyword: keyword.value.trim() || undefined, limit: 100 })
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

onMounted(load)
</script>

<template>
  <div class="page-head">
    <div>
      <h1>登录记录</h1>
      <div class="sub">用于排查"这个账号最近是谁在用"；登录名只记脱敏值</div>
    </div>
  </div>

  <div v-if="error" class="notice err">{{ error }}</div>

  <div class="card">
    <div class="toolbar">
      <input
        v-model="keyword"
        class="grow"
        type="text"
        placeholder="按脱敏登录名筛选，如 D0**1"
        @keyup.enter="load"
      />
      <button class="btn ghost" @click="load">查询</button>
    </div>

    <div v-if="loading" class="empty">加载中…</div>

    <table v-else>
      <thead>
        <tr>
          <th style="width: 160px">时间</th>
          <th style="width: 140px">登录名</th>
          <th style="width: 120px">账号类型</th>
          <th style="width: 120px">登录方式</th>
          <th style="width: 100px">结果</th>
          <th>失败原因</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="(r, i) in list" :key="i">
          <td>{{ String(r.createdAt || '').replace('T', ' ').slice(0, 19) }}</td>
          <td>{{ r.loginNameMasked || '—' }}</td>
          <td>{{ r.accountType === 'PATIENT' ? '患者' : '医护' }}</td>
          <td>{{ r.loginType === 'SMS_CODE' ? '短信验证码' : '密码' }}</td>
          <td>
            <span class="tag" :class="r.success ? 'ok' : 'danger'">{{ r.success ? '成功' : '失败' }}</span>
          </td>
          <td>{{ r.failReason || '—' }}</td>
        </tr>
      </tbody>
    </table>

    <div v-if="!loading && !list.length" class="empty">暂无登录记录</div>
  </div>
</template>
