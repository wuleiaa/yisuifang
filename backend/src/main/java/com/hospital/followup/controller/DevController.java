package com.hospital.followup.controller;

import com.hospital.followup.bootstrap.DevDataSeeder;
import com.hospital.followup.common.ApiResponse;
import com.hospital.followup.common.BusinessException;
import com.hospital.followup.common.ErrorCode;
import com.hospital.followup.security.CurrentUser;
import org.springframework.context.annotation.Profile;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

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

    public DevController(DevDataSeeder seeder) {
        this.seeder = seeder;
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
}
