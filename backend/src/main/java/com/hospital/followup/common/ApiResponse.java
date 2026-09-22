package com.hospital.followup.common;

/**
 * 统一响应结构。
 * 前端只需判断 code == 0。
 */
public record ApiResponse<T>(int code, String message, T data) {

    public static <T> ApiResponse<T> ok(T data) {
        return new ApiResponse<>(0, "ok", data);
    }

    public static ApiResponse<Void> ok() {
        return new ApiResponse<>(0, "ok", null);
    }

    public static <T> ApiResponse<T> fail(ErrorCode ec, String message) {
        return new ApiResponse<>(ec.getCode(), message == null ? ec.getDefaultMessage() : message, null);
    }
}

