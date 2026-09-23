package com.hospital.followup.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.hospital.followup.common.ApiResponse;
import com.hospital.followup.common.ErrorCode;
import com.hospital.followup.repository.AccountRepository;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.MediaType;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import java.nio.charset.StandardCharsets;
import java.util.List;

@Configuration
@EnableMethodSecurity
public class SecurityConfig {

    private final ObjectMapper objectMapper;

    /**
     * 允许从浏览器调用接口的来源。
     *
     * 【为什么必须可配、而且必须含真实域名】
     * HTTPS 由 nginx 终结，容器里的应用看到的 scheme 是 http；
     * 浏览器发来的 Origin 却是 https://<域名>。只要白名单里没有这个域名，
     * Spring 的 CORS 过滤器就会把它当跨域请求拒掉——症状是
     * 「页面能打开，但登录/提交全部 403、响应体 20 字节（Invalid CORS request）」。
     * 2026-09-22 HTTPS 上线后线上正是这个状态，而 PowerShell 发的请求不带
     * Origin，所以所有自动化测试都发现不了。默认值见 application.yml。
     */
    @Value("${app.cors.allowed-origins:http://localhost:*,http://127.0.0.1:*}")
    private String allowedOriginsRaw;

    public SecurityConfig(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    /** 密码使用 BCrypt（自带盐、可调强度），绝不使用 MD5/SHA1 */
    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder(10);
    }

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http, JwtService jwtService,
                                          AccountRepository accountRepository) throws Exception {
        http
            .csrf(csrf -> csrf.disable())                 // 纯 API + JWT，无 Cookie 会话
            .cors(cors -> cors.configurationSource(corsSource()))
            .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .headers(h -> h
                    .frameOptions(f -> f.deny())
                    .contentTypeOptions(c -> {})
            )
            .authorizeHttpRequests(auth -> auth
                    // 未登录可访问：医护登录、患者端验证码与登录、对外公开接口
                    .requestMatchers("/api/auth/login", "/api/portal/auth/**", "/api/public/**").permitAll()
                    .requestMatchers("/actuator/health", "/actuator/info").permitAll()
                    // 管理后台只允许医护身份（科室管理者在业务层再校验）
                    .requestMatchers("/api/admin/**").hasRole("STAFF")
                    // 患者端只允许患者身份
                    .requestMatchers("/api/portal/**").hasRole("PATIENT")
                    // 【关键】其余 /api/** 全部是医护接口。
                    // 不能只写 authenticated()：患者令牌也是"已认证"，
                    // 那样患者拿着自己的令牌就能调用医护接口（提交回访、看患者列表）。
                    .requestMatchers("/api/**").hasRole("STAFF")
                    .anyRequest().authenticated())
            .exceptionHandling(e -> e
                    .authenticationEntryPoint((req, res, ex) -> writeError(res, HttpServletResponse.SC_UNAUTHORIZED,
                            ErrorCode.UNAUTHORIZED))
                    .accessDeniedHandler((req, res, ex) -> writeError(res, HttpServletResponse.SC_FORBIDDEN,
                            ErrorCode.FORBIDDEN)))
            .httpBasic(b -> b.disable())
            .formLogin(f -> f.disable())
            .logout(l -> l.disable());

        // 把 JWT 过滤器插到用户名密码过滤器之前
        http.addFilterBefore(new JwtAuthFilter(jwtService, accountRepository, objectMapper),
                UsernamePasswordAuthenticationFilter.class);

        return http.build();
    }

    private void writeError(HttpServletResponse res, int status, ErrorCode code) throws java.io.IOException {
        res.setStatus(status);
        res.setContentType(MediaType.APPLICATION_JSON_VALUE);
        res.setCharacterEncoding(StandardCharsets.UTF_8.name());
        objectMapper.writeValue(res.getWriter(), ApiResponse.fail(code, null));
    }

    private CorsConfigurationSource corsSource() {
        CorsConfiguration c = new CorsConfiguration();
        // 见 allowedOriginsRaw 的注释：本地开发端口 + 真实域名，都从配置读
        List<String> origins = java.util.Arrays.stream(allowedOriginsRaw.split(","))
                .map(String::trim)
                .filter(s -> !s.isEmpty())
                .toList();
        c.setAllowedOriginPatterns(origins);
        c.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"));
        c.setAllowedHeaders(List.of("*"));
        c.setAllowCredentials(true);
        c.setMaxAge(3600L);

        UrlBasedCorsConfigurationSource src = new UrlBasedCorsConfigurationSource();
        src.registerCorsConfiguration("/**", c);
        return src;
    }
}
