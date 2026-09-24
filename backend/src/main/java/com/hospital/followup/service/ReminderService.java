package com.hospital.followup.service;

import com.hospital.followup.dto.ReminderDtos;
import com.hospital.followup.security.CurrentUser;
import com.hospital.followup.security.RlsSession;
import jakarta.persistence.EntityManager;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.LocalTime;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 提醒调度（C12）。
 *
 * 【策略来自哪里】reminder_rule 表（科室级 > 全局级），不是写死的常量。
 * 当前生效的全局规则与第 4 轮定稿一致：
 *   T-1 18:00 预告 → T 日 08:00 起每 2 小时催办（到 18:00）→ 逾期 1–3 天每天 3 次
 *   （08:00/12:00/17:00）→ 逾期 4–14 天每天 1 次（08:00）→ 22:00–07:00 免打扰
 *   → 逾期超过 14 天停止提醒。
 *
 * 【为什么服务端只生成"时点"，不直接推】
 * 安卓端的本地通知由手机自己排程（Capacitor LocalNotifications → AlarmManager），
 * 不依赖推送通道；服务端负责算出"什么时候该提醒什么"，App 拉取后排到系统里。
 * 这样没有 FCM/微信推送资质也能用，代价是"只在 App 打开时同步一次排程"。
 *
 * 【隐私】通知正文只写数量与紧急度，不写患者姓名（第 4 轮定的保守默认值）：
 * 锁屏弹窗会暴露给旁边所有人，点进 App 再看是谁。
 */
@Service
public class ReminderService {

    private static final Logger log = LoggerFactory.getLogger(ReminderService.class);
    private static final ZoneId ZONE = ZoneId.of("Asia/Shanghai");
    private static final DateTimeFormatter HHMM = DateTimeFormatter.ofPattern("HH:mm");

    /** 计划窗口：只排未来 48 小时内的提醒，避免一次排到几个月以后 */
    private static final int PLAN_HORIZON_HOURS = 48;
    /** 一次最多返回多少条（防止极端数据把通知排爆） */
    private static final int MAX_ITEMS = 40;
    /** App 一次最多回执多少条 */
    private static final int MAX_ACK = 200;

    /** 逾期 1–3 天的三个时点：第 7 轮定稿写死 08:00 / 12:00 / 17:00 */
    private static final List<LocalTime> OVERDUE_SLOTS =
            List.of(LocalTime.of(8, 0), LocalTime.of(12, 0), LocalTime.of(17, 0));

    /** 表里取不到规则时的兜底（与第 4 轮定稿一致） */
    private static final Rule DEFAULT_RULE = new Rule(
            "默认策略（表里没有可用规则）",
            1, LocalTime.of(18, 0), LocalTime.of(8, 0), 2, LocalTime.of(18, 0),
            LocalTime.of(22, 0), LocalTime.of(7, 0), 3, 1, 14);

    private final EntityManager em;
    private final RlsSession rlsSession;

    public ReminderService(EntityManager em, RlsSession rlsSession) {
        this.em = em;
        this.rlsSession = rlsSession;
    }

    // ------------------------------------------------------------------ 策略

    /** 科室级优先、其次全局、最后兜底 */
    public Rule ruleFor(Long deptId) {
        @SuppressWarnings("unchecked")
        List<Object[]> rows = em.createNativeQuery("""
                select name, advance_notify_days, advance_notify_time, day_start_time, interval_hours,
                       day_end_time, quiet_start, quiet_end, overdue_day_times, overdue_week_times,
                       stop_after_days
                  from reminder_rule
                 where status = 1
                   and ((scope = 'DEPT' and dept_id = :deptId) or scope = 'GLOBAL')
                 order by case when scope = 'DEPT' then 0 else 1 end
                 limit 1
                """).setParameter("deptId", deptId).getResultList();
        if (rows.isEmpty()) {
            return DEFAULT_RULE;
        }
        Object[] r = rows.get(0);
        return new Rule(
                (String) r[0],
                ((Number) r[1]).intValue(),
                toLocalTime(r[2], DEFAULT_RULE.advanceNotifyTime()),
                toLocalTime(r[3], DEFAULT_RULE.dayStartTime()),
                ((Number) r[4]).intValue(),
                toLocalTime(r[5], DEFAULT_RULE.dayEndTime()),
                toLocalTime(r[6], DEFAULT_RULE.quietStart()),
                toLocalTime(r[7], DEFAULT_RULE.quietEnd()),
                ((Number) r[8]).intValue(),
                ((Number) r[9]).intValue(),
                ((Number) r[10]).intValue());
    }

    /** 原生查询里的 time 字段可能是 LocalTime，也可能是老的 java.sql.Time——两种都接住 */
    private static LocalTime toLocalTime(Object value, LocalTime fallback) {
        if (value == null) {
            return fallback;
        }
        if (value instanceof LocalTime lt) {
            return lt;
        }
        if (value instanceof java.sql.Time t) {
            return t.toLocalTime();
        }
        if (value instanceof String s) {
            return LocalTime.parse(s.length() > 8 ? s.substring(0, 8) : s);
        }
        return fallback;
    }

    // ------------------------------------------------------------------ 计划

    /**
     * 当前登录人未来 48 小时要弹的提醒。
     *
     * @param at 可选：按指定时刻计算（ISO-8601，供测试与排查用）；为空则用当前时刻
     */
    @Transactional(readOnly = true)
    public ReminderDtos.ReminderPlan plan(String at) {
        rlsSession.apply();
        CurrentUser.Principal me = CurrentUser.require();
        Rule rule = ruleFor(me.deptId());
        OffsetDateTime now = parseAt(at);

        List<TaskRow> tasks = openTasks(me.staffId(),
                now.toLocalDate().plusDays(Math.max(rule.advanceNotifyDays(), 0)));

        int dueToday = 0;
        int overdue = 0;
        // 同一个时点上可能有多条任务 → 合并成一条"今天有 N 条待办"的通知
        Map<String, Slot> slots = new LinkedHashMap<>();
        for (TaskRow t : tasks) {
            long over = ChronoUnit.DAYS.between(t.dueDate(), now.toLocalDate());
            if (over > rule.stopAfterDays()) {
                continue;   // 逾期太久，不再打扰
            }
            if (over == 0) {
                dueToday++;
            } else if (over > 0) {
                overdue++;
            }
            for (OffsetDateTime time : scheduleFor(t, rule, now)) {
                // 等级按"通知响的那一刻"算：今天到期的任务，排到明天的那条就已经是逾期了
                String level = levelOf(t, time.toLocalDate());
                String key = level + ":" + time.format(DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm"));
                slots.computeIfAbsent(key, k -> new Slot(level, time)).add(t);
            }
        }

        List<ReminderDtos.ReminderItem> items = new ArrayList<>();
        for (Slot slot : slots.values()) {
            if (items.size() >= MAX_ITEMS) {
                break;
            }
            int n = slot.tasks.size();
            String title = "OVERDUE".equals(slot.level) ? "随访任务逾期提醒" : "随访待办提醒";
            String message = switch (slot.level) {
                case "PREVIEW" -> "明天有 " + n + " 条随访任务，请提前安排";
                case "OVERDUE" -> "有 " + n + " 条随访任务已逾期，请尽快处理";
                default -> "今天有 " + n + " 条随访任务待处理";
            };
            items.add(new ReminderDtos.ReminderItem(
                    slot.key(), slot.at.toString(), slot.level, title, message, n, slot.tasks.get(0).id()));
        }

        return new ReminderDtos.ReminderPlan(
                now.toString(), rule.view(), tasks.size(), dueToday, overdue, items);
    }

    /** 一条任务在"未来 48 小时内"落到哪些提醒时点 */
    private List<OffsetDateTime> scheduleFor(TaskRow task, Rule rule, OffsetDateTime now) {
        LocalDate today = now.toLocalDate();
        List<OffsetDateTime> out = new ArrayList<>();

        // 候选时点的规则：
        //   T-1 预告：due_date = 明天 → 当天 advanceNotifyTime（默认 18:00）
        //   T 日：due_date = 今天 → dayStartTime 起每 intervalHours，到 dayEndTime 为止
        //   逾期 1–3 天：每天 3 次（08:00/12:00/17:00）；4 天以上：每天 1 次（dayStartTime）
        for (int dayOffset = 0; dayOffset <= 1; dayOffset++) {
            LocalDate day = today.plusDays(dayOffset);
            long overThatDay = ChronoUnit.DAYS.between(task.dueDate(), day);
            if (overThatDay > rule.stopAfterDays()) {
                continue;
            }
            List<LocalTime> times = new ArrayList<>();
            if (overThatDay == 0) {
                for (LocalTime t = rule.dayStartTime();
                     !t.isAfter(rule.dayEndTime());
                     t = t.plusHours(Math.max(rule.intervalHours(), 1))) {
                    times.add(t);
                }
            } else if (overThatDay > 0) {
                if (overThatDay <= 3) {
                    times.addAll(OVERDUE_SLOTS);
                } else if (overThatDay <= rule.stopAfterDays()) {
                    times.add(rule.dayStartTime());
                }
            } else if (overThatDay == -rule.advanceNotifyDays()) {
                times.add(rule.advanceNotifyTime());
            }

            for (LocalTime t : times) {
                if (inQuietHours(t, rule)) {
                    continue;   // 夜间免打扰
                }
                OffsetDateTime at = day.atTime(t).atZone(ZONE).toOffsetDateTime();
                if (at.isBefore(now) || at.isAfter(now.plusHours(PLAN_HORIZON_HOURS))) {
                    continue;   // 已经过去的、或超出计划窗口的不排
                }
                out.add(at);
            }
        }
        return out;
    }

    private static String levelOf(TaskRow task, LocalDate today) {
        long over = ChronoUnit.DAYS.between(task.dueDate(), today);
        if (over > 0) {
            return "OVERDUE";
        }
        if (over == 0) {
            return "DUE_TODAY";
        }
        return "PREVIEW";
    }

    /** 夜间免打扰：22:00–07:00（含跨零点） */
    private static boolean inQuietHours(LocalTime t, Rule rule) {
        LocalTime start = rule.quietStart();
        LocalTime end = rule.quietEnd();
        if (start.equals(end)) {
            return false;
        }
        return start.isBefore(end) ? (t.compareTo(start) >= 0 && t.compareTo(end) < 0)
                                   : (t.compareTo(start) >= 0 || t.compareTo(end) < 0);
    }

    private OffsetDateTime parseAt(String at) {
        if (at == null || at.isBlank()) {
            return OffsetDateTime.now(ZONE);
        }
        try {
            return OffsetDateTime.parse(at).atZoneSameInstant(ZONE).toOffsetDateTime();
        } catch (Exception e) {
            return OffsetDateTime.now(ZONE);
        }
    }

    @SuppressWarnings("unchecked")
    private List<TaskRow> openTasks(Long staffId, LocalDate limitDate) {
        List<Object[]> rows = em.createNativeQuery("""
                select t.id, t.title, t.due_date
                  from followup_task t
                 where t.deleted_at is null
                   and t.status in ('PENDING','DOING')
                   and t.assignee_staff_id = :me
                   and t.due_date <= :limitDate
                 order by t.due_date, t.id
                """)
                .setParameter("me", staffId)
                .setParameter("limitDate", limitDate)
                .getResultList();
        List<TaskRow> out = new ArrayList<>(rows.size());
        for (Object[] r : rows) {
            out.add(new TaskRow(((Number) r[0]).longValue(), (String) r[1], toLocalDate(r[2])));
        }
        return out;
    }

    private static LocalDate toLocalDate(Object value) {
        if (value instanceof LocalDate d) {
            return d;
        }
        if (value instanceof java.sql.Date d) {
            return d.toLocalDate();
        }
        if (value == null) {
            return LocalDate.now(ZONE);
        }
        return LocalDate.parse(value.toString().substring(0, 10));
    }

    // ------------------------------------------------------------------ 扫描

    /**
     * 定时扫描：把"此刻该提醒"的时点写进 notify_log（status=PENDING）。
     *
     * 幂等：同一 (staff_id, template_code=时点键) 只写一条；App 回执后这条会变成 SENT。
     * 这样即使扫描频率调来调去，也不会重复打扰同一个人。
     *
     * @param toleranceMinutes 扫描间隔（分钟内落到的时点都算"该提醒了"）
     */
    @Transactional
    public int scanDue(OffsetDateTime now, int toleranceMinutes) {
        rlsSession.applyAsSystem();
        @SuppressWarnings("unchecked")
        List<Object[]> rows = em.createNativeQuery("""
                select t.assignee_staff_id, t.id, t.due_date
                  from followup_task t
                 where t.deleted_at is null
                   and t.status in ('PENDING','DOING')
                   and t.assignee_staff_id is not null
                   and t.due_date <= (cast(:today as date) + 1)
                 order by t.assignee_staff_id, t.due_date, t.id
                """).setParameter("today", now.toLocalDate()).getResultList();

        int written = 0;
        for (Object[] r : rows) {
            Long staffId = ((Number) r[0]).longValue();
            TaskRow task = new TaskRow(((Number) r[1]).longValue(), null, toLocalDate(r[2]));
            Rule rule = ruleFor(null);
            for (OffsetDateTime at : scheduleFor(task, rule, now.minusMinutes(toleranceMinutes))) {
                if (at.isAfter(now) || at.isBefore(now.minusMinutes(toleranceMinutes))) {
                    continue;   // 只处理这一轮扫描窗口内的时点
                }
                String level = levelOf(task, at.toLocalDate());
                String key = level + ":" + at.format(DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm"));
                written += insertPendingIfAbsent(staffId, task.id(), level, key, at);
            }
        }
        return written;
    }

    private int insertPendingIfAbsent(Long staffId, Long taskId, String level, String key, OffsetDateTime at) {
        Number exist = (Number) em.createNativeQuery("""
                select count(*) from notify_log where staff_id = :sid and template_code = :key
                """).setParameter("sid", staffId).setParameter("key", key).getSingleResult();
        if (exist != null && exist.longValue() > 0) {
            return 0;
        }
        em.createNativeQuery("""
                insert into notify_log (task_id, staff_id, channel_code, template_code, biz_type,
                                        title, content_masked, status, created_at)
                values (:taskId, :staffId, 'ANDROID_LOCAL', :key, :biz,
                        :title, :content, 'PENDING', now())
                """)
                .setParameter("taskId", taskId)
                .setParameter("staffId", staffId)
                .setParameter("key", key)
                .setParameter("biz", "OVERDUE".equals(level) ? "TASK_OVERDUE" : "TASK_REMIND")
                .setParameter("title", "OVERDUE".equals(level) ? "随访任务逾期提醒" : "随访待办提醒")
                .setParameter("content", key)
                .executeUpdate();
        return 1;
    }

    // ------------------------------------------------------------------ 回执

    /** App 排程完成后的回执：把这些时点标记为已发送，并登记设备 */
    @Transactional
    public ReminderDtos.AckResult ack(ReminderDtos.AckRequest req) {
        rlsSession.apply();
        CurrentUser.Principal me = CurrentUser.require();
        List<String> keys = req == null || req.keys() == null ? List.of() : req.keys();
        if (keys.size() > MAX_ACK) {
            keys = keys.subList(0, MAX_ACK);
        }

        int acked = 0;
        for (String key : keys) {
            if (key == null || key.isBlank()) {
                continue;
            }
            int updated = em.createNativeQuery("""
                    update notify_log
                       set status = 'SENT', sent_at = now(), channel_code = 'ANDROID_LOCAL'
                     where staff_id = :sid and template_code = :key
                    """).setParameter("sid", me.staffId()).setParameter("key", key).executeUpdate();
            if (updated == 0) {
                // 服务端还没扫到这个时点（App 提前排程）→ 直接补一条 SENT，保留审计
                String level = key.startsWith("OVERDUE") ? "OVERDUE" : (key.startsWith("PREVIEW") ? "PREVIEW" : "DUE_TODAY");
                em.createNativeQuery("""
                        insert into notify_log (staff_id, channel_code, template_code, biz_type,
                                                title, content_masked, status, sent_at, created_at)
                        values (:sid, 'ANDROID_LOCAL', :key, :biz, :title, :key, 'SENT', now(), now())
                        """)
                        .setParameter("sid", me.staffId())
                        .setParameter("key", key)
                        .setParameter("biz", "OVERDUE".equals(level) ? "TASK_OVERDUE" : "TASK_REMIND")
                        .setParameter("title", "OVERDUE".equals(level) ? "随访任务逾期提醒" : "随访待办提醒")
                        .executeUpdate();
                updated = 1;
            }
            acked += updated;
        }
        registerDevice(me.accountId(), req);
        return new ReminderDtos.AckResult(acked, req == null ? null : req.deviceId());
    }

    /** 登记设备（user_device 就是为"安卓本地通知重建"准备的） */
    private void registerDevice(Long accountId, ReminderDtos.AckRequest req) {
        if (req == null || req.deviceId() == null || req.deviceId().isBlank()) {
            return;
        }
        String platform = req.platform() == null || req.platform().isBlank() ? "ANDROID" : req.platform();
        em.createNativeQuery("""
                insert into user_device (account_id, device_id, platform, last_active_at, status, created_at, updated_at)
                values (:aid, :did, :platform, now(), 1, now(), now())
                on conflict (account_id, device_id)
                do update set last_active_at = now(), platform = excluded.platform,
                              status = 1, updated_at = now()
                """)
                .setParameter("aid", accountId)
                .setParameter("did", req.deviceId())
                .setParameter("platform", platform)
                .executeUpdate();
        log.debug("登记设备 account={} device={}", accountId, req.deviceId());
    }

    // ------------------------------------------------------------------ 内部类型

    /** 生效的提醒策略 */
    public record Rule(
            String name,
            int advanceNotifyDays,
            LocalTime advanceNotifyTime,
            LocalTime dayStartTime,
            int intervalHours,
            LocalTime dayEndTime,
            LocalTime quietStart,
            LocalTime quietEnd,
            int overdueDayTimes,
            int overdueWeekTimes,
            int stopAfterDays
    ) {
        public ReminderDtos.ReminderRuleView view() {
            return new ReminderDtos.ReminderRuleView(name, advanceNotifyDays,
                    advanceNotifyTime.format(HHMM), dayStartTime.format(HHMM), intervalHours,
                    dayEndTime.format(HHMM), quietStart.format(HHMM), quietEnd.format(HHMM),
                    overdueDayTimes, overdueWeekTimes, stopAfterDays);
        }
    }

    private record TaskRow(Long id, String title, LocalDate dueDate) {
    }

    /** 同一时点的多条任务合并成一条通知 */
    private static final class Slot {
        private final String level;
        private final OffsetDateTime at;
        private final List<TaskRow> tasks = new ArrayList<>();

        private Slot(String level, OffsetDateTime at) {
            this.level = level;
            this.at = at;
        }

        private void add(TaskRow t) {
            tasks.add(t);
        }

        private String key() {
            return level + ":" + at.format(DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm"));
        }
    }
}
