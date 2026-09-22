package com.hospital.followup.common;

/**
 * 业务错误码。
 * 前端按码做提示，不要依赖中文文案。
 */
public enum ErrorCode {

    BAD_REQUEST(40000, "请求参数有误"),
    UNAUTHORIZED(40100, "请先登录"),
    TOKEN_EXPIRED(40101, "登录已过期，请重新登录"),
    FORBIDDEN(40300, "没有权限执行该操作"),
    NOT_FOUND(40400, "数据不存在"),
    CONFLICT(40900, "数据冲突"),
    TOO_MANY_REQUESTS(42900, "操作过于频繁，请稍后再试"),

    LOGIN_FAILED(41001, "工号或密码错误"),
    ACCOUNT_LOCKED(41002, "账号已被锁定，请稍后再试"),
    ACCOUNT_DISABLED(41003, "账号已停用，请联系管理员"),
    PASSWORD_EXPIRED(41004, "密码已过期，请修改密码"),
    /** 首次登录（或管理员重置密码后）必须先把密码改掉，才能使用其他功能 */
    PASSWORD_CHANGE_REQUIRED(41005, "请先修改初始密码，再使用其他功能"),

    /** 需要二次验证才能查看完整手机号 */
    REAUTH_REQUIRED(42001, "该操作需要二次身份验证"),
    /** 高风险病理报告未完成患者告知，不允许发布 */
    PATHOLOGY_NOT_NOTIFIED(42002, "高风险报告必须先告知患者才能发布"),
    PATHOLOGY_NOT_REVIEWED(42003, "报告必须经主管医生审核后才能发布"),
    PATHOLOGY_NO_INTERPRETATION(42004, "报告必须填写医生解读后才能发布"),
    /** 任务已被他人锁定 */
    TASK_LOCKED(42005, "该任务正在被他人处理"),

    INTERNAL_ERROR(50000, "系统繁忙，请稍后再试");

    private final int code;
    private final String defaultMessage;

    ErrorCode(int code, String defaultMessage) {
        this.code = code;
        this.defaultMessage = defaultMessage;
    }

    public int getCode() {
        return code;
    }

    public String getDefaultMessage() {
        return defaultMessage;
    }
}
