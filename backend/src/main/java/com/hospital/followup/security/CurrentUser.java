package com.hospital.followup.security;

import java.util.Set;

/**
 * 当前登录用户上下文（线程级）。
 *
 * 由 JwtAuthFilter 在请求开始时写入，请求结束时清除。
 * RlsSession 依赖它来设置数据库会话变量。
 */
public final class CurrentUser {

    public record Principal(
            Long accountId,
            Long staffId,
            String staffNo,
            String name,
            Long deptId,
            boolean manager,
            Set<String> permissions,
            /** 患者端登录时才有值 */
            Long patientId,
            /** 是否为患者端（小程序）请求 */
            boolean patientPortal
    ) {
        public boolean hasPermission(String code) {
            return permissions != null && permissions.contains(code);
        }

        /** 患者端身份：没有工号、没有科室、没有管理权限 */
        public static Principal forPatient(Long accountId, Long patientId, String name) {
            return new Principal(accountId, null, null, name, null, false,
                    Set.of("portal:read", "portal:submit"), patientId, true);
        }
    }

    private static final ThreadLocal<Principal> HOLDER = new ThreadLocal<>();

    private CurrentUser() {
    }

    public static void set(Principal p) {
        HOLDER.set(p);
    }

    public static Principal get() {
        return HOLDER.get();
    }

    public static void clear() {
        HOLDER.remove();
    }

    public static Long staffId() {
        Principal p = HOLDER.get();
        return p == null ? null : p.staffId();
    }

    public static Long deptId() {
        Principal p = HOLDER.get();
        return p == null ? null : p.deptId();
    }

    public static boolean isManager() {
        Principal p = HOLDER.get();
        return p != null && p.manager();
    }

    public static Long patientId() {
        Principal p = HOLDER.get();
        return p == null ? null : p.patientId();
    }

    public static boolean isPatientPortal() {
        Principal p = HOLDER.get();
        return p != null && p.patientPortal();
    }

    public static boolean hasPermission(String code) {
        Principal p = HOLDER.get();
        return p != null && p.hasPermission(code);
    }

    /** 取当前用户，未登录时抛异常（供 Service 使用） */
    public static Principal require() {
        Principal p = HOLDER.get();
        if (p == null) {
            throw new com.hospital.followup.common.BusinessException(
                    com.hospital.followup.common.ErrorCode.UNAUTHORIZED);
        }
        return p;
    }
}
