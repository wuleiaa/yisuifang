package com.hospital.followup.controller;

import com.hospital.followup.bootstrap.DevDataSeeder;
import com.hospital.followup.common.ApiResponse;
import com.hospital.followup.common.BusinessException;
import com.hospital.followup.common.ErrorCode;
import com.hospital.followup.security.CurrentUser;
import com.hospital.followup.service.ReminderService;
import org.springframework.context.annotation.Profile;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.util.Map;

/**
 * 开发 / 演示辅助接口。
 *
 * 【安全边界】整个类标注 @Profile("dev")，生产环境这个 Bean 根本不会被创建，
 * 所以即使有人猜到路径也调不到；再加上"仅科室管理者可调用"的业务校验，
 * 双保险。
 */
@RestController
@RequestMapping("/api/dev")
@Profile("dev")
public class DevController {

    private final DevDataSeeder seeder;
    private final ReminderService reminderService;

    public DevController(DevDataSeeder seeder, ReminderService reminderService) {
        this.seeder = seeder;
        this.reminderService = reminderService;
    }

    /**
     * 一键重置演示数据：清空业务数据并按种子重新生成。
     * 反复跑联调、性能测试、演示前复位都用它，避免演示任务被消耗光。
     */
    @PostMapping("/demo-data/reset")
    public ApiResponse<Map<String, Object>> resetDemoData() {
        CurrentUser.Principal p = CurrentUser.require();
        if (!p.manager()) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "仅科室管理者可重置演示数据");
        }
        return ApiResponse.ok(seeder.resetAndSeed());
    }

    /**
     * 立刻跑一次提醒扫描（C12）。
     *
     * 定时器每 10 分钟才跑一次，测试和排查需要"现在就按指定时刻扫一遍"。
     * 走的是与定时器完全相同的 ReminderService.scanDue，所以测到的就是线上逻辑。
     *
     * @param at 可选：按指定时刻扫描（ISO-8601）；为空用当前时刻
     */
    @PostMapping("/reminders/scan")
    public ApiResponse<Map<String, Object>> scanReminders(@RequestParam(required = false) String at) {
        CurrentUser.Principal p = CurrentUser.require();
        if (!p.manager()) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "仅科室管理者可触发提醒扫描");
        }
        OffsetDateTime when = (at == null || at.isBlank())
                ? OffsetDateTime.now(ZoneId.of("Asia/Shanghai"))
                : OffsetDateTime.parse(at).atZoneSameInstant(ZoneId.of("Asia/Shanghai")).toOffsetDateTime();
        int written = reminderService.scanDue(when, 10);
        return ApiResponse.ok(Map.of("at", when.toString(), "created", written));
    }

    /** 当前生效的提醒策略（演示时给同行看"什么时候会提醒"） */
    @GetMapping("/reminders/rule")
    public ApiResponse<?> reminderRule() {
        CurrentUser.Principal p = CurrentUser.require();
        return ApiResponse.ok(reminderService.ruleFor(p.deptId()).view());
    }
}
