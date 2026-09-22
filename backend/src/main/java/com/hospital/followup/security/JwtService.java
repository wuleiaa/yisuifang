package com.hospital.followup.security;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.JwtException;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Date;

/**
 * JWT 签发与校验。
 *
 * 说明：这里只用 JWT 承载"身份标识"，不放任何患者信息，
 * 因为 JWT 的 payload 只是 Base64，任何人拿到都能看到内容。
 */
@Service
public class JwtService {

    private final SecretKey key;
    private final long expireMinutes;

    public JwtService(@Value("${app.jwt.secret}") String secret,
                      @Value("${app.jwt.expire-minutes:480}") long expireMinutes) {
        if (secret == null || secret.length() < 32) {
            throw new IllegalStateException("app.jwt.secret 长度不足 32 位，存在被破解风险");
        }
        this.key = Keys.hmacShaKeyFor(sha256(secret));
        this.expireMinutes = expireMinutes;
    }

    private static byte[] sha256(String s) {
        try {
            return MessageDigest.getInstance("SHA-256").digest(s.getBytes(StandardCharsets.UTF_8));
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    public String issue(Long accountId, Long staffId, String staffNo, String name, Long deptId, boolean manager) {
        Instant now = Instant.now();
        return Jwts.builder()
                .subject(String.valueOf(accountId))
                .claim("sid", staffId)
                .claim("no", staffNo)
                .claim("nm", name)
                .claim("did", deptId)
                .claim("mgr", manager)
                .claim("pt", false)
                .issuedAt(Date.from(now))
                .expiration(Date.from(now.plus(expireMinutes, ChronoUnit.MINUTES)))
                .signWith(key)
                .compact();
    }

    /**
     * 患者端令牌。
     *
     * 与医护令牌用同一个密钥签发，但带 pt=true 标记，
     * 由 JwtAuthFilter 区分成两种身份，避免患者令牌被当成医护令牌使用。
     */
    public String issueForPatient(Long accountId, Long patientId, String name) {
        Instant now = Instant.now();
        return Jwts.builder()
                .subject(String.valueOf(accountId))
                .claim("pid", patientId)
                .claim("nm", name)
                .claim("pt", true)
                .issuedAt(Date.from(now))
                .expiration(Date.from(now.plus(expireMinutes, ChronoUnit.MINUTES)))
                .signWith(key)
                .compact();
    }

    /**
     * 解析并校验 token。失败时返回 null（由调用方决定是 401 还是放行）。
     */
    public Claims parse(String token) {
        try {
            return Jwts.parser().verifyWith(key).build()
                    .parseSignedClaims(token).getPayload();
        } catch (JwtException | IllegalArgumentException e) {
            return null;
        }
    }

    public long getExpireMinutes() {
        return expireMinutes;
    }
}
