package com.hospital.followup.dto;

import java.util.List;

/**
 * 提醒计划（C12）出入参。
 *
 * 【为什么通知正文里没有患者姓名】
 * 第 4 轮定的默认值就是"通知栏不显示患者姓名"（可配置的保守档）：
 * 锁屏上弹出"张春 术后 3 天电话回访"等于把患者信息暴露给旁边任何人。
 * 所以通知只写数量与紧急度，点进来才在 App 里看具体是谁。
 */
public final class ReminderDtos {

    private ReminderDtos() {
    }

    /** 生效的提醒策略（来自 reminder_rule，取不到就用代码里的默认值） */
    public record ReminderRuleView(
            String name,
            int advanceNotifyDays,
            String advanceNotifyTime,
            String dayStartTime,
            int intervalHours,
            String dayEndTime,
            String quietStart,
            String quietEnd,
            int overdueDayTimes,
            int overdueWeekTimes,
            int stopAfterDays
    ) {
    }

    /**
     * 一条待排程的提醒。
     *
     * key 是稳定去重键（形如 {@code DUE_TODAY:2026-09-24T10:00}）：
     * 服务端扫描与 App 回执都用它判重，避免同一时点重复提醒。
     */
    public record ReminderItem(
            String key,
            /** ISO-8601（东八区），设备按本地时间弹窗 */
            String notifyAt,
            /** PREVIEW（T-1 预告）/ DUE_TODAY（当天）/ OVERDUE（逾期） */
            String level,
            String title,
            String message,
            int taskCount,
            /** 点开通知时先跳这条任务（可为空） */
            Long sampleTaskId
    ) {
    }

    public record ReminderPlan(
            String generatedAt,
            ReminderRuleView rule,
            int openTaskCount,
            int dueTodayCount,
            int overdueCount,
            List<ReminderItem> items
    ) {
    }

    /** App 排程完成后回执：告诉服务端"这些时点已经安排到手机上了"。 */
    public record AckRequest(
            List<String> keys,
            String deviceId,
            /** ANDROID（当前只有安卓壳） */
            String platform
    ) {
    }

    public record AckResult(int acked, String deviceId) {
    }
}
