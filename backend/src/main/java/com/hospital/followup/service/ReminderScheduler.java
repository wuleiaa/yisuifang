package com.hospital.followup.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.OffsetDateTime;
import java.time.ZoneId;

/**
 * 提醒调度器（C12）：定时把"此刻该提醒"的时点写进 notify_log。
 *
 * 【它到底做了什么、没做什么】做的是**算出该提醒谁、并留下待发记录**；
 * 没做的是"推送到手机"——本项目没有 FCM/微信推送资质，真正的弹窗由
 * 安卓端把计划排进系统闹钟（LocalNotifications/AlarmManager）来完成。
 * 所以这里的记录既是审计，也是"这轮扫到过什么"的证据。
 *
 * 频率默认每 10 分钟一次（app.reminder.scan-interval-minutes），
 * 时点键保证同一时点只写一条（见 ReminderService.scanDue）。
 */
@Component
public class ReminderScheduler {

    private static final Logger log = LoggerFactory.getLogger(ReminderScheduler.class);
    private static final ZoneId ZONE = ZoneId.of("Asia/Shanghai");

    private final ReminderService reminderService;

    @Value("${app.reminder.enabled:true}")
    private boolean enabled;

    @Value("${app.reminder.scan-interval-minutes:10}")
    private int intervalMinutes;

    public ReminderScheduler(ReminderService reminderService) {
        this.reminderService = reminderService;
    }

    @Scheduled(fixedDelayString = "${app.reminder.scan-interval-ms:600000}",
               initialDelayString = "${app.reminder.initial-delay-ms:60000}")
    public void scan() {
        if (!enabled) {
            return;
        }
        try {
            int written = reminderService.scanDue(OffsetDateTime.now(ZONE), intervalMinutes);
            if (written > 0) {
                log.info("提醒扫描：新增 {} 条待发提醒", written);
            }
        } catch (Exception e) {
            // 定时任务抛异常会让后续调度停掉，所以这里必须自己吞掉并留日志
            log.error("提醒扫描失败", e);
        }
    }
}
