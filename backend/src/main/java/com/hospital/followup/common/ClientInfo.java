package com.hospital.followup.common;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

/**
 * 取当前请求的客户端 IP 与 User-Agent，供登录日志、审计日志使用。
 *
 * 【为什么取值顺序是这样】
 *  线上部署时后端只在 Docker 内网暴露（见 deploy/demo/docker-compose.yml：
 *  app 只有 expose，没有 ports），唯一入口是我们自己配置的 nginx，
 *  它会把真实来源写进 X-Real-IP，这一项是可信的。
 *  X-Forwarded-For 是一条"逗号分隔的链路"，最左边那一段可能被客户端自己伪造，
 *  最右边那一段才是 nginx 看到的直连地址，所以取最后一段。
 *  两者都没有（本地直连后端调试）才退回 socket 地址。
 *
 * 【为什么必须记下来】
 *  "谁在什么时候从哪个 IP 登录/改密码"是安全事件排查的起点。
 *  只记工号不记来源，事后无法判断是不是异地盗用。
 */
public final class ClientInfo {

    private static final int IP_MAX = 45;    // 库里是 varchar(45)，够放 IPv6
    private static final int UA_MAX = 300;   // 库里是 varchar(300)

    private ClientInfo() {
    }

    /** 客户端 IP，取不到返回 null */
    public static String ip() {
        HttpServletRequest req = current();
        if (req == null) {
            return null;
        }
        String ip = trim(req.getHeader("X-Real-IP"));
        if (ip == null) {
            String xff = trim(req.getHeader("X-Forwarded-For"));
            if (xff != null) {
                int lastComma = xff.lastIndexOf(',');
                ip = trim(lastComma >= 0 ? xff.substring(lastComma + 1) : xff);
            }
        }
        if (ip == null) {
            ip = trim(req.getRemoteAddr());
        }
        return truncate(ip, IP_MAX);
    }

    /** User-Agent，取不到返回 null */
    public static String userAgent() {
        HttpServletRequest req = current();
        return req == null ? null : truncate(trim(req.getHeader("User-Agent")), UA_MAX);
    }

    private static HttpServletRequest current() {
        if (RequestContextHolder.getRequestAttributes() instanceof ServletRequestAttributes attrs) {
            return attrs.getRequest();
        }
        return null;
    }

    private static String trim(String s) {
        if (s == null) {
            return null;
        }
        String t = s.trim();
        return t.isEmpty() ? null : t;
    }

    private static String truncate(String s, int max) {
        if (s == null || s.length() <= max) {
            return s;
        }
        return s.substring(0, max);
    }
}
