package com.hospital.followup.controller;

import com.hospital.followup.common.ApiResponse;
import com.hospital.followup.dto.TaskDtos;
import com.hospital.followup.service.TaskService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/tasks")
public class TaskController {

    private final TaskService taskService;

    public TaskController(TaskService taskService) {
        this.taskService = taskService;
    }

    /**
     * 待办列表。
     * scope=MINE 只看指派给我的；scope=TEAM 看我和搭档组的（默认）。
     */
    @GetMapping("/todo")
    public ApiResponse<TaskDtos.TodoSummary> todo(
            @RequestParam(defaultValue = "TEAM") String scope,
            @RequestParam(defaultValue = "7") int days,
            @RequestParam(defaultValue = "100") int limit) {
        return ApiResponse.ok(taskService.todo(scope, days, limit));
    }

    @GetMapping("/{id}")
    public ApiResponse<TaskDtos.TaskDetail> detail(@PathVariable Long id) {
        return ApiResponse.ok(taskService.detail(id));
    }

    /** 开始处理：抢占锁，防止两位护士同时给同一位患者打电话 */
    @PostMapping("/{id}/claim")
    public ApiResponse<TaskDtos.TaskDetail> claim(@PathVariable Long id) {
        return ApiResponse.ok(taskService.claim(id));
    }

    /**
     * 一键拨号：取回可拨号码用于调用系统拨号器。
     *
     * 用 POST 而不是 GET：这是一次"解密并留痕"的动作，不能被浏览器预取/缓存，
     * 每次点击都必须真的写一条审计。
     */
    @PostMapping("/{id}/dial")
    public ApiResponse<TaskDtos.DialPhone> dial(@PathVariable Long id) {
        return ApiResponse.ok(taskService.dial(id));
    }

    @PostMapping("/complete")
    public ApiResponse<TaskDtos.CompleteTaskResponse> complete(
            @Valid @RequestBody TaskDtos.CompleteTaskRequest req) {
        return ApiResponse.ok(taskService.complete(req));
    }
}
