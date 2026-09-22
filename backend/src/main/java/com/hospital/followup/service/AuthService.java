package com.hospital.followup.service;

import com.hospital.followup.common.BusinessException;
import com.hospital.followup.common.ErrorCode;
import com.hospital.followup.crypto.CryptoService;
import com.hospital.followup.domain.Account;
import com.hospital.followup.domain.Department;
import com.hospital.followup.domain.Staff;
import com.hospital.followup.dto.AuthDtos;
import com.hospital.followup.repository.AccountRepository;
import com.hospital.followup.repository.DepartmentRepository;
import com.hospital.followup.repository.StaffRepository;
import com.hospital.followup.security.CurrentUser;
import com.hospital.followup.security.JwtService;
import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * 登录服务。
 *
 * 安全要点：
 *  1. 登录名不存明文，存 HMAC 哈希（login_hash），防止脱库后被枚举工号；
 *  2. 密码用 BCrypt 校验，绝不明文比较；
 *  3. 连续失败 N 次锁定账号，防止暴力破解；
 *  4. 不区分"工号不存在"和"密码错误"，统一返回同一提示，
 *     避免攻击者用返回信息判断哪些工号有效。
 */
@Service
public class AuthService {

    private static final Logger log = LoggerFactory.getLogger(AuthService.class);

    private final AccountRepository accountRepository;
    private final StaffRepository staffRepository;
    private final DepartmentRepository departmentRepository;
    private final CryptoService cryptoService;
    private final PasswordEncoder passwordEncoder;
    private final JwtService jwtService;
    private final LoginLogService loginLogService;
    private final AuditLogService auditLogService;

    @PersistenceContext
    private EntityManager em;

    @Value("${app.security.login-max-fail:5}")
    private int loginMaxFail;

    @Value("${app.security.lock-minutes:15}")
    private int lockMinutes;

    public AuthService(AccountRepository accountRepository,
                       StaffRepository staffRepository,
                       DepartmentRepository departmentRepository,
                       CryptoService cryptoService,
                       PasswordEncoder passwordEncoder,
                       JwtService jwtService,
                       LoginLogService loginLogService,
                       AuditLogService auditLogService) {
        this.accountRepository = accountRepository;
        this.staffRepository = staffRepository;
        this.departmentRepository = departmentRepository;
        this.cryptoService = cryptoService;
        this.passwordEncoder = passwordEncoder;
        this.jwtService = jwtService;
        this.loginLogService = loginLogService;
        this.auditLogService = auditLogService;
    }

    @Transactional
    public AuthDtos.LoginResponse login(AuthDtos.LoginRequest req) {
        String staffNo = req.staffNo().trim().toUpperCase();
        String loginHash = cryptoService.hash(staffNo);

        Account account = accountRepository.findByLoginHashAndDeletedAtIsNull(loginHash)
                .orElseThrow(() -> {
                    loginLogService.record(null, staffNo, "STAFF", "PASSWORD", false, "账号不存在");
                    return new BusinessException(ErrorCode.LOGIN_FAILED);
                });

        if ("DISABLED".equals(account.getStatus())) {
            loginLogService.record(account.getId(), staffNo, "STAFF", "PASSWORD", false, "账号已停用");
            throw new BusinessException(ErrorCode.ACCOUNT_DISABLED);
        }
        if (account.getLockedUntil() != null && account.getLockedUntil().isAfter(OffsetDateTime.now())) {
            loginLogService.record(account.getId(), staffNo, "STAFF", "PASSWORD", false, "账号锁定中");
            throw new BusinessException(ErrorCode.ACCOUNT_LOCKED);
        }

        if (!passwordEncoder.matches(req.password(), account.getPasswordHash())) {
            int fails = (account.getFailedAttempts() == null ? 0 : account.getFailedAttempts()) + 1;
            account.setFailedAttempts(fails);
            if (fails >= loginMaxFail) {
                account.setLockedUntil(OffsetDateTime.now().plusMinutes(lockMinutes));
                account.setFailedAttempts(0);
                log.warn("账号 {} 连续登录失败 {} 次，已锁定 {} 分钟", req.staffNo(), fails, lockMinutes);
            }
            accountRepository.save(account);
            loginLogService.record(account.getId(), staffNo, "STAFF", "PASSWORD", false, "密码错误");
            throw new BusinessException(ErrorCode.LOGIN_FAILED);
        }

        Staff staff = staffRepository.findById(account.getStaffId())
                .orElseThrow(() -> {
                    loginLogService.record(account.getId(), staffNo, "STAFF", "PASSWORD", false, "员工档案缺失");
                    return new BusinessException(ErrorCode.ACCOUNT_DISABLED);
                });

        account.setFailedAttempts(0);
        account.setLockedUntil(null);
        account.setLastLoginAt(OffsetDateTime.now());
        if ("PENDING".equals(account.getStatus())) {
            account.setStatus("ACTIVE");
        }
        accountRepository.save(account);

        Set<String> roles = loadRoles(staff.getId());
        boolean admin = isAdmin(staff, roles);
        Set<String> permissions = resolvePermissions(staff, roles);
        String token = jwtService.issue(account.getId(), staff.getId(), staff.getStaffNo(),
                staff.getName(), staff.getDeptId(), Boolean.TRUE.equals(staff.getIsManager()));

        String deptName = departmentRepository.findById(staff.getDeptId())
                .map(Department::getName).orElse("");

        loginLogService.record(account.getId(), staffNo, "STAFF", "PASSWORD", true, null);

        return new AuthDtos.LoginResponse(
                token,
                jwtService.getExpireMinutes() * 60,
                new AuthDtos.StaffProfile(
                        staff.getId(), staff.getStaffNo(), staff.getName(), staff.getTitle(),
                        staff.getDeptId(), deptName,
                        Boolean.TRUE.equals(staff.getIsManager()),
                        admin, roles,
                        Boolean.TRUE.equals(account.getMustChangePassword()),
                        permissions));
    }

    /** 读取角色编码（role / staff_role 表） */
    private Set<String> loadRoles(Long staffId) {
        if (staffId == null) {
            return Set.of();
        }
        @SuppressWarnings("unchecked")
        List<Object> rows = em.createNativeQuery("""
                select r.code from staff_role sr
                  join role r on r.id = sr.role_id
                 where sr.staff_id = :sid
                """).setParameter("sid", staffId).getResultList();
        Set<String> set = new HashSet<>();
        for (Object o : rows) {
            set.add(String.valueOf(o));
        }
        return set;
    }

    /** 管理员 = 系统管理员 / 科室管理者 / is_manager 标志 */
    private boolean isAdmin(Staff staff, Set<String> roles) {
        return roles.contains("SUPER_ADMIN")
                || roles.contains("DEPT_MANAGER")
                || Boolean.TRUE.equals(staff.getIsManager());
    }

    /**
     * 权限点。当前版本按"是否科室管理者"给出基础集合，
     * 完整的 RBAC（role / permission 表）在后续迭代接入。
     */
    private Set<String> resolvePermissions(Staff staff, Set<String> roles) {
        Set<String> perms = new HashSet<>();
        if (roles.contains("SUPER_ADMIN") || roles.contains("DEPT_MANAGER")
                || Boolean.TRUE.equals(staff.getIsManager())) {
            perms.addAll(Set.of(
                    "patient:read", "patient:write", "patient:phone:view",
                    "encounter:read", "encounter:write", "encounter:import",
                    "task:read", "task:execute", "task:assign", "plan:write",
                    "template:write", "template:approve",
                    "pathology:enter", "pathology:review", "pathology:publish",
                    "audit:read", "admin:staff"));
        } else {
            perms.addAll(Set.of(
                    "patient:read", "patient:phone:view", "encounter:read",
                    "task:read", "task:execute", "plan:write",
                    "pathology:enter", "pathology:review", "pathology:publish"));
        }
        return perms;
    }

    public AuthDtos.StaffProfile currentProfile() {
        CurrentUser.Principal p = CurrentUser.require();
        String deptName = departmentRepository.findById(p.deptId())
                .map(Department::getName).orElse("");
        Set<String> roles = loadRoles(p.staffId());
        boolean admin = roles.contains("SUPER_ADMIN") || roles.contains("DEPT_MANAGER") || p.manager();
        return new AuthDtos.StaffProfile(p.staffId(), p.staffNo(), p.name(), null,
                p.deptId(), deptName, p.manager(), admin, roles, false, p.permissions());
    }

    /**
     * 修改自己的密码。
     *
     * 规则：
     *  1. 必须提供正确的原密码 —— 防止别人趁人离开电脑时改掉密码；
     *  2. 新密码不能和原密码相同；
     *  3. 至少 8 位，且必须同时含字母和数字（纯数字太容易被猜到，
     *     而且医院里常见"工号后六位"这种密码）；
     *  4. 改完之后清掉"待改密"标记，并写审计日志。
     */
    @Transactional
    public void changePassword(AuthDtos.ChangePasswordRequest req) {
        CurrentUser.Principal p = CurrentUser.require();
        Account account = accountRepository.findById(p.accountId())
                .orElseThrow(() -> new BusinessException(ErrorCode.UNAUTHORIZED, "请先登录"));

        if (!passwordEncoder.matches(req.oldPassword(), account.getPasswordHash())) {
            auditPasswordChange(p, "FAIL", "原密码不正确");
            throw new BusinessException(ErrorCode.LOGIN_FAILED, "原密码不正确");
        }
        if (passwordEncoder.matches(req.newPassword(), account.getPasswordHash())) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "新密码不能与原密码相同");
        }
        String weak = checkStrength(req.newPassword());
        if (weak != null) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, weak);
        }

        account.setPasswordHash(passwordEncoder.encode(req.newPassword()));
        account.setMustChangePassword(Boolean.FALSE);
        account.setPasswordUpdatedAt(OffsetDateTime.now());
        account.setFailedAttempts(0);
        account.setLockedUntil(null);
        accountRepository.save(account);

        auditPasswordChange(p, "SUCCESS", null);
        log.info("工号 {} 修改了自己的密码", p.staffNo());
    }

    /** 返回 null 表示合格，否则返回不合格的原因 */
    private String checkStrength(String pwd) {
        if (pwd.length() < 8) {
            return "新密码至少 8 位";
        }
        boolean hasLetter = pwd.chars().anyMatch(Character::isLetter);
        boolean hasDigit = pwd.chars().anyMatch(Character::isDigit);
        if (!hasLetter || !hasDigit) {
            return "新密码必须同时包含字母和数字";
        }
        return null;
    }

    private void auditPasswordChange(CurrentUser.Principal p, String result, String note) {
        // 【必须走独立事务】改密失败时本方法会抛异常、主事务回滚，
        // 如果审计写在同一事务里，恰恰"失败的改密尝试"一条都留不下。
        auditLogService.record(p.accountId(), p.staffId(), "STAFF_CHANGE_PASSWORD",
                "account", p.staffNo(), result, AuditLogService.noteJson(note));
    }
}
