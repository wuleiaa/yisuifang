package com.hospital.followup.controller;

import com.hospital.followup.common.ApiResponse;
import com.hospital.followup.dto.PortalDtos;
import com.hospital.followup.service.PortalAuthService;
import com.hospital.followup.service.PortalService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * 患者端接口（微信小程序 / 手机 H5）。
 *
 * 路径统一在 /api/portal 下，SecurityConfig 里限定了
 * 「只允许 ROLE_PATIENT 访问」，医护令牌调不通，反之亦然。
 */
@RestController
@RequestMapping("/api/portal")
public class PortalController {

    private final PortalAuthService portalAuthService;
    private final PortalService portalService;

    public PortalController(PortalAuthService portalAuthService, PortalService portalService) {
        this.portalAuthService = portalAuthService;
        this.portalService = portalService;
    }

    /** 请求验证码（未登录可访问） */
    @PostMapping("/auth/code")
    public ApiResponse<PortalDtos.CodeResponse> sendCode(@Valid @RequestBody PortalDtos.CodeRequest req) {
        return ApiResponse.ok(portalAuthService.sendCode(req));
    }

    /** 患者登录（未登录可访问） */
    @PostMapping("/auth/login")
    public ApiResponse<PortalDtos.LoginResponse> login(@Valid @RequestBody PortalDtos.LoginRequest req) {
        return ApiResponse.ok(portalAuthService.login(req));
    }

    /** 我的基本信息 */
    @GetMapping("/me")
    public ApiResponse<PortalDtos.PatientProfile> me() {
        return ApiResponse.ok(portalService.me());
    }

    /** 我的随访时间轴 */
    @GetMapping("/timeline")
    public ApiResponse<PortalDtos.Timeline> timeline() {
        return ApiResponse.ok(portalService.timeline());
    }

    /** 我的病理报告（仅已发布） */
    @GetMapping("/reports")
    public ApiResponse<List<PortalDtos.ReportItem>> reports() {
        return ApiResponse.ok(portalService.reports());
    }

    /** 某条随访安排详情 */
    @GetMapping("/tasks/{id}")
    public ApiResponse<PortalDtos.TimelineItem> task(@PathVariable Long id) {
        return ApiResponse.ok(portalService.taskDetail(id));
    }

    /** 提交随访问卷 */
    @PostMapping("/tasks/{id}/questionnaire")
    public ApiResponse<PortalDtos.SubmitResult> submit(@PathVariable Long id,
                                                       @Valid @RequestBody PortalDtos.QuestionnaireSubmit req) {
        return ApiResponse.ok(portalService.submitQuestionnaire(id, req.answers()));
    }

    /** 随访问卷题目（从数据库读，前端不写死） */
    @GetMapping("/questionnaire")
    public ApiResponse<PortalDtos.Questionnaire> questionnaire() {
        return ApiResponse.ok(portalService.questionnaire());
    }
}
