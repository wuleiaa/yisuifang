package com.hospital.followup.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.hospital.followup.common.ApiResponse;
import com.hospital.followup.common.ErrorCode;
import com.hospital.followup.domain.Account;
import com.hospital.followup.repository.AccountRepository;
import io.jsonwebtoken.Claims;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Set;

/**
 * 从 Authorization: Bearer xxx 中解析身份，写入 CurrentUser。
 *
 * 注意：这里不负责"拦截未登录请求"，那是 SecurityConfig 的职责。
 * 本过滤器只做"身份识别"，无论成功与否都放行，保证请求结束后一定清理上下文。
 *
 * 本类不标注 @Component，而是由 SecurityConfig 显式注册进过滤器链，
 * 避免被 Spring Boot 当成普通 Servlet Filter 重复注册执行两次。
 *
 * 【除了识别身份，这里还挡两道门】
 *  1. 账号被停用（或已删除）后，旧令牌立即失效。
 *     令牌是有有效期的（默认 8 小时），只在登录时校验状态的话，
 *     "刚被停用的人继续用手上的令牌干活"这段窗口就是安全漏洞。
 *  2. 处于"必须先改密"状态的账号，只能调改密所需的接口。
 *     原先这个约束只做在界面上：只要绕过页面直接调接口，
 *     拿着初始密码（演示账号的是公开的默认口令）照样能把管理接口全用一遍。
 */
public class JwtAuthFilter extends OncePerRequestFilter {

    /** "必须先改密"状态下允许访问的接口，其余一律 403 */
    private static final Set<String> ALLOWED_WHILE_MUST_CHANGE_PASSWORD = Set.of(
            "/api/auth/me",
            "/api/auth/change-password"
    );

    private final JwtService jwtService;
    private final AccountRepository accountRepository;
    private final ObjectMapper objectMapper;

    public JwtAuthFilter(JwtService jwtService, AccountRepository accountRepository, ObjectMapper objectMapper) {
        this.jwtService = jwtService;
        this.accountRepository = accountRepository;
        this.objectMapper = objectMapper;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {
        try {
            String header = request.getHeader("Authorization");
            if (header != null && header.startsWith("Bearer ")) {
                Claims claims = jwtService.parse(header.substring(7).trim());
                if (claims != null) {
                    Long accountId = Long.valueOf(claims.getSubject());

                    if (!accountStillUsable(accountId, request, response)) {
                        return;
                    }

                    Boolean patientToken = claims.get("pt", Boolean.class);
                    String name = claims.get("nm", String.class);

                    if (Boolean.TRUE.equals(patientToken)) {
                        // 患者端令牌：只给患者身份，绝不放任何医护权限
                        Long patientId = claims.get("pid", Long.class);
                        CurrentUser.set(CurrentUser.Principal.forPatient(accountId, patientId, name));

                        // 写入 Spring Security 上下文，否则 .authenticated() 会拒绝请求
                        var patientAuthorities = List.of(new SimpleGrantedAuthority("ROLE_PATIENT"));
                        var patientAuth = new UsernamePasswordAuthenticationToken(
                                String.valueOf(accountId), null, patientAuthorities);
                        SecurityContextHolder.getContext().setAuthentication(patientAuth);
                    } else {
                        Long staffId = claims.get("sid", Long.class);
                        String staffNo = claims.get("no", String.class);
                        Long deptId = claims.get("did", Long.class);
                        Boolean mgr = claims.get("mgr", Boolean.class);

                        CurrentUser.set(new CurrentUser.Principal(
                                accountId, staffId, staffNo, name, deptId,
                                Boolean.TRUE.equals(mgr),
                                // 权限点在后续迭代从数据库加载；本版先给全部基础权限
                                Set.of("patient:read", "patient:phone:view", "encounter:read",
                                       "task:read", "task:execute", "plan:write",
                                       "pathology:enter", "pathology:review", "pathology:publish"),
                                null, false
                        ));

                        var authorities = List.of(new SimpleGrantedAuthority("ROLE_STAFF"));
                        var authToken = new UsernamePasswordAuthenticationToken(
                                String.valueOf(accountId), null, authorities);
                        SecurityContextHolder.getContext().setAuthentication(authToken);
                    }
                }
            }
            chain.doFilter(request, response);
        } finally {
            // 线程池复用，必须清理，否则会串号
            CurrentUser.clear();
            SecurityContextHolder.clearContext();
        }
    }

    /**
     * 账号状态校验。返回 false 表示已经写好错误响应、请求到此为止。
     *
     * 每次请求多一次主键查询（account 表，走索引，亚毫秒级），
     * 换来的是"停用立刻生效"和"强制改密无法绕过"。
     */
    private boolean accountStillUsable(Long accountId, HttpServletRequest request,
                                       HttpServletResponse response) throws IOException {
        Account account = accountRepository.findById(accountId).orElse(null);
        if (account == null || account.getDeletedAt() != null) {
            writeError(response, HttpServletResponse.SC_UNAUTHORIZED, ErrorCode.UNAUTHORIZED);
            return false;
        }
        if ("DISABLED".equals(account.getStatus())) {
            writeError(response, HttpServletResponse.SC_UNAUTHORIZED, ErrorCode.ACCOUNT_DISABLED);
            return false;
        }
        if (Boolean.TRUE.equals(account.getMustChangePassword()) && !allowedBeforePasswordChange(request)) {
            writeError(response, HttpServletResponse.SC_FORBIDDEN, ErrorCode.PASSWORD_CHANGE_REQUIRED);
            return false;
        }
        return true;
    }

    /**
     * 只约束 /api/ 接口；其他路径（如 /actuator/health）不在这里管，
     * 免得把运维类请求一并挡掉。
     */
    private static boolean allowedBeforePasswordChange(HttpServletRequest request) {
        String path = request.getRequestURI();
        return !path.startsWith("/api/") || ALLOWED_WHILE_MUST_CHANGE_PASSWORD.contains(path);
    }

    /** 与 SecurityConfig 的异常响应保持同一种格式，前端按 code 处理 */
    private void writeError(HttpServletResponse res, int status, ErrorCode code) throws IOException {
        res.setStatus(status);
        res.setContentType(MediaType.APPLICATION_JSON_VALUE);
        res.setCharacterEncoding(StandardCharsets.UTF_8.name());
        objectMapper.writeValue(res.getWriter(), ApiResponse.fail(code, null));
    }
}
