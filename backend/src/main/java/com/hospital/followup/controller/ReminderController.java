package com.hospital.followup.controller;

import com.hospital.followup.common.ApiResponse;
import com.hospital.followup.dto.ReminderDtos;
import com.hospital.followup.security.CurrentUser;
import com.hospital.followup.service.ReminderService;
import org.springframework.web.bind.annotation.*;

/**
 * 提醒（C12）。
 *
 * 医护端 App 打开时拉一次计划，把未来的提醒排进手机系统；排完回执一次。
 * 与服务端定时扫描共用同一套"时点键"，所以不会重复提醒。
 */
@RestController
@RequestMapping("/api/reminders")
public class ReminderController {

    private final ReminderService reminderService;

    public ReminderController(ReminderService reminderService) {
        this.reminderService = reminderService;
    }

    /**
     * 未来 48 小时的提醒计划。
     *
     * @param at 可选，形如 2026-09-24T07:30:00+08:00；仅用于测试与排查（按指定时刻算计划）
     */
    @GetMapping("/plan")
    public ApiResponse<ReminderDtos.ReminderPlan> plan(@RequestParam(required = false) String at) {
        return ApiResponse.ok(reminderService.plan(at));
    }

    /** 当前生效的提醒策略（App 可以用来展示"什么时候会提醒我"） */
    @GetMapping("/rule")
    public ApiResponse<ReminderDtos.ReminderRuleView> rule() {
        CurrentUser.Principal me = CurrentUser.require();
        return ApiResponse.ok(reminderService.ruleFor(me.deptId()).view());
    }

    /** App 排程完成后的回执 */
    @PostMapping("/ack")
    public ApiResponse<ReminderDtos.AckResult> ack(@RequestBody ReminderDtos.AckRequest req) {
        return ApiResponse.ok(reminderService.ack(req));
    }
}
