package com.hospital.followup.service;

import com.hospital.followup.common.BusinessException;
import com.hospital.followup.common.ErrorCode;
import com.hospital.followup.crypto.CryptoService;
import com.hospital.followup.domain.Account;
import com.hospital.followup.domain.Patient;
import com.hospital.followup.dto.PortalDtos;
import com.hospital.followup.repository.AccountRepository;
import com.hospital.followup.repository.PatientRepository;
import com.hospital.followup.security.JwtService;
import com.hospital.followup.security.RlsSession;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.security.SecureRandom;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * 患者端登录：手机号 + 短信验证码。
 *
 * 安全要点：
 *  1. 请求验证码时**不区分**手机号是否在库——无论是否为本院患者，返回内容完全一致，
 *     否则接口会变成"查询某人是否在本院就诊"的探测工具（这属于隐私泄露）。
 *  2. 验证码 5 分钟有效，最多校验 5 次，校验通过或超次即作废。
 *  3. 患者账号不设密码（password_hash 存随机值），只能靠短信验证码登录。
 *  4. 登录成功/失败都写审计日志。
 *
 * 【已知限制】验证码暂存在单机内存里，只适用于单实例部署。
 * 多实例部署必须换成 Redis（application-dev.yml 里已经预留了 Redis 配置）。
 */
@Service
public class PortalAuthService {

    private static final Logger log = LoggerFactory.getLogger(PortalAuthService.class);
    private static final int CODE_TTL_SECONDS = 300;
    private static final int MAX_VERIFY_ATTEMPTS = 5;

    private record CodeEntry(String code, long expiresAt, AtomicInteger attempts) {
        boolean expired() {
            return System.currentTimeMillis() > expiresAt;
        }
    }

    private final Map<String, CodeEntry> codeStore = new ConcurrentHashMap<>();
    private final SecureRandom random = new SecureRandom();

    private final PatientRepository patientRepository;
    private final AccountRepository accountRepository;
    private final CryptoService cryptoService;
    private final JwtService jwtService;
    private final RlsSession rlsSession;
    private final LoginLogService loginLogService;
    private final AuditLogService auditLogService;

    /** dev 环境把验证码直接回给前端，方便本地联调；生产环境不返回 */
    @Value("${app.portal.sms-mode:dev}")
    private String smsMode;

    public PortalAuthService(PatientRepository patientRepository,
                             AccountRepository accountRepository,
                             CryptoService cryptoService,
                             JwtService jwtService,
                             RlsSession rlsSession,
                             LoginLogService loginLogService,
                             AuditLogService auditLogService) {
        this.patientRepository = patientRepository;
        this.accountRepository = accountRepository;
        this.cryptoService = cryptoService;
        this.jwtService = jwtService;
        this.rlsSession = rlsSession;
        this.loginLogService = loginLogService;
        this.auditLogService = auditLogService;
    }

    /** 请求验证码。返回结构与"手机号是否存在"无关。 */
    public PortalDtos.CodeResponse sendCode(PortalDtos.CodeRequest req) {
        String phone = req.phone().trim();
        String hash = cryptoService.hash(phone);
        String code = String.format("%06d", random.nextInt(1_000_000));

        codeStore.put(hash, new CodeEntry(code,
                System.currentTimeMillis() + CODE_TTL_SECONDS * 1000L, new AtomicInteger()));

        String mask = cryptoService.maskPhone(phone);

        if (!"dev".equalsIgnoreCase(smsMode)) {
            // 生产环境必须接入短信通道。宁可明确报错，也不做"假发送"。
            codeStore.remove(hash);
            throw new BusinessException(ErrorCode.INTERNAL_ERROR,
                    "短信通道尚未配置，请联系科室工作人员协助");
        }

        log.info("【dev】患者端验证码 phone={} code={}", mask, code);
        return new PortalDtos.CodeResponse(mask, CODE_TTL_SECONDS, code);
    }

    @Transactional
    public PortalDtos.LoginResponse login(PortalDtos.LoginRequest req) {
        String phone = req.phone().trim();
        String hash = cryptoService.hash(phone);

        CodeEntry entry = codeStore.get(hash);
        if (entry == null || entry.expired()) {
            codeStore.remove(hash);
            audit(null, null, "PORTAL_LOGIN", "FAIL", "验证码不存在或已过期");
            throw new BusinessException(ErrorCode.LOGIN_FAILED, "验证码已过期，请重新获取");
        }
        if (entry.attempts().incrementAndGet() > MAX_VERIFY_ATTEMPTS) {
            codeStore.remove(hash);
            audit(null, null, "PORTAL_LOGIN", "FAIL", "验证码尝试次数超限");
            throw new BusinessException(ErrorCode.LOGIN_FAILED, "验证码错误次数过多，请重新获取");
        }
        if (!entry.code().equals(req.code().trim())) {
            audit(null, null, "PORTAL_LOGIN", "FAIL", "验证码不相符");
            throw new BusinessException(ErrorCode.LOGIN_FAILED, "验证码不正确");
        }
        codeStore.remove(hash);

        // 患者主档在行级安全之下，登录阶段还没有身份，必须以系统身份查询
        rlsSession.applyAsSystem();

        List<Patient> patients = patientRepository.findByPhoneHashAndDeletedAtIsNull(hash);
        if (patients.isEmpty()) {
            audit(null, null, "PORTAL_LOGIN", "FAIL", "手机号未关联患者");
            throw new BusinessException(ErrorCode.LOGIN_FAILED, "该手机号未关联到随访记录，请联系科室");
        }
        Patient patient = patients.get(0);
        if (patients.size() > 1) {
            // 一家人共用一个手机号的情况真实存在，此处取第一位并在日志里留痕
            log.warn("手机号 {} 关联了 {} 位患者，本次按第一位（id={}）登录",
                    cryptoService.maskPhone(phone), patients.size(), patient.getId());
        }

        Account account = accountRepository.findByPatientIdAndDeletedAtIsNull(patient.getId())
                .orElseThrow(() -> {
                    audit(null, patient.getId(), "PORTAL_LOGIN", "FAIL", "患者没有登录账号");
                    return new BusinessException(ErrorCode.LOGIN_FAILED,
                            "该患者尚未开通查询账号，请联系科室工作人员");
                });

        if ("DISABLED".equals(account.getStatus())) {
            throw new BusinessException(ErrorCode.ACCOUNT_DISABLED);
        }

        account.setLastLoginAt(OffsetDateTime.now());
        if ("PENDING".equals(account.getStatus())) {
            account.setStatus("ACTIVE");
        }
        accountRepository.save(account);

        audit(account.getId(), patient.getId(), "PORTAL_LOGIN", "SUCCESS", null);
        loginLogService.record(account.getId(), cryptoService.maskPhone(phone), "PATIENT", "SMS_CODE", true, null);

        String token = jwtService.issueForPatient(account.getId(), patient.getId(), patient.getName());
        return new PortalDtos.LoginResponse(token, jwtService.getExpireMinutes() * 60, toProfile(patient));
    }

    static PortalDtos.PatientProfile toProfile(Patient p) {
        return new PortalDtos.PatientProfile(
                p.getId(), p.getName(),
                p.getGender() != null && p.getGender() == 2 ? "女" : "男",
                p.getAge(), p.getPhoneMask(), p.getMedicalRecordNo());
    }

    private void audit(Long accountId, Long patientId, String action, String result, String detail) {
        // 统一走 AuditLogService：独立事务（登录失败会回滚主事务）+ 自动带 IP / User-Agent
        auditLogService.record(accountId, null, patientId, action, "account", null, result,
                AuditLogService.noteJson(detail));
    }
}
