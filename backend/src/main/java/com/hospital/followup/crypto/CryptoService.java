package com.hospital.followup.crypto;

import jakarta.annotation.PostConstruct;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import javax.crypto.Cipher;
import javax.crypto.Mac;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.HexFormat;

/**
 * 敏感字段加密服务。
 *
 * 设计要点（对应第 6 轮的数据模型）：
 *   手机号存三个字段：
 *     phone_cipher  = AES-256-GCM 密文（可解密，用于拨号/导出）
 *     phone_hash    = HMAC-SHA256(明文, pepper)（不可逆，用于等值查找）
 *     phone_mask    = 138****5678（列表页直接展示，根本不解密）
 *
 * 密钥要求：
 *   - dataKey 与 hashPepper 必须不同，且都通过环境变量注入；
 *   - 一旦上线不可更改，否则历史数据无法解密；
 *   - 必须单独备份（数据库备份里没有密钥）。
 */
@Service
public class CryptoService {

    /** AES/GCM 的 IV 长度：12 字节是标准推荐值 */
    private static final int GCM_IV_BYTES = 12;
    /** GCM 认证标签 128 位 */
    private static final int GCM_TAG_BITS = 128;

    private final SecureRandom random = new SecureRandom();

    @Value("${app.crypto.data-key}")
    private String dataKeyRaw;

    @Value("${app.crypto.hash-pepper}")
    private String hashPepperRaw;

    private SecretKeySpec aesKey;
    private byte[] pepper;

    @PostConstruct
    void init() {
        if (dataKeyRaw == null || dataKeyRaw.isBlank()) {
            throw new IllegalStateException("app.crypto.data-key 未配置，服务不能启动");
        }
        if (hashPepperRaw == null || hashPepperRaw.isBlank()) {
            throw new IllegalStateException("app.crypto.hash-pepper 未配置，服务不能启动");
        }
        if (dataKeyRaw.equals(hashPepperRaw)) {
            throw new IllegalStateException("数据密钥与哈希盐不能相同，这会让加密形同虚设");
        }
        // 用 SHA-256 把任意长度的配置值规整成 32 字节密钥
        this.aesKey = new SecretKeySpec(sha256(dataKeyRaw), "AES");
        this.pepper = sha256(hashPepperRaw);
    }

    private static byte[] sha256(String s) {
        try {
            return MessageDigest.getInstance("SHA-256").digest(s.getBytes(StandardCharsets.UTF_8));
        } catch (Exception e) {
            throw new IllegalStateException("SHA-256 不可用", e);
        }
    }

    /**
     * 加密。返回 IV + 密文（IV 随机生成，因此同一明文每次密文都不同）。
     */
    public byte[] encrypt(String plain) {
        if (plain == null) {
            return null;
        }
        try {
            byte[] iv = new byte[GCM_IV_BYTES];
            random.nextBytes(iv);

            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, aesKey, new GCMParameterSpec(GCM_TAG_BITS, iv));
            byte[] cipherText = cipher.doFinal(plain.getBytes(StandardCharsets.UTF_8));

            byte[] out = new byte[iv.length + cipherText.length];
            System.arraycopy(iv, 0, out, 0, iv.length);
            System.arraycopy(cipherText, 0, out, iv.length, cipherText.length);
            return out;
        } catch (Exception e) {
            throw new IllegalStateException("加密失败", e);
        }
    }

    /**
     * 解密。调用方必须保证这是"需要审计"的行为（如查看完整手机号）。
     */
    public String decrypt(byte[] data) {
        if (data == null || data.length <= GCM_IV_BYTES) {
            return null;
        }
        try {
            byte[] iv = new byte[GCM_IV_BYTES];
            System.arraycopy(data, 0, iv, 0, GCM_IV_BYTES);

            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, aesKey, new GCMParameterSpec(GCM_TAG_BITS, iv));
            byte[] plain = cipher.doFinal(data, GCM_IV_BYTES, data.length - GCM_IV_BYTES);
            return new String(plain, StandardCharsets.UTF_8);
        } catch (Exception e) {
            throw new IllegalStateException("解密失败，可能是密钥不匹配或数据被篡改", e);
        }
    }

    /**
     * 计算可检索的哈希（HMAC-SHA256）。
     * 相比裸 SHA256，加了 pepper 之后攻击者无法用彩虹表反查手机号。
     */
    public String hash(String plain) {
        if (plain == null) {
            return null;
        }
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(pepper, "HmacSHA256"));
            return HexFormat.of().formatHex(mac.doFinal(plain.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception e) {
            throw new IllegalStateException("哈希计算失败", e);
        }
    }

    /**
     * 生成脱敏展示值。
     * 手机号：13812345678 -> 138****5678
     * 身份证：18 位 -> 前 6 后 4
     */
    public String maskPhone(String phone) {
        if (phone == null || phone.length() < 7) {
            return phone;
        }
        return phone.substring(0, 3) + "****" + phone.substring(phone.length() - 4);
    }

    public String maskIdCard(String idCard) {
        if (idCard == null || idCard.length() < 10) {
            return idCard;
        }
        return idCard.substring(0, 6) + "********" + idCard.substring(idCard.length() - 4);
    }

    /** 仅供自检接口使用，验证密钥装载正确且能往返加解密 */
    public boolean selfCheck() {
        String sample = "13812345678";
        byte[] cipher = encrypt(sample);
        String plain = decrypt(cipher);
        return sample.equals(plain) && hash(sample).length() == 64;
    }

    public String randomToken(int bytes) {
        byte[] b = new byte[bytes];
        random.nextBytes(b);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(b);
    }
}
