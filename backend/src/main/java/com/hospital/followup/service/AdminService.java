package com.hospital.followup.service;

import com.hospital.followup.common.BusinessException;
import com.hospital.followup.common.ErrorCode;
import com.hospital.followup.crypto.CryptoService;
import com.hospital.followup.domain.Account;
import com.hospital.followup.domain.Staff;
import com.hospital.followup.dto.AdminDtos;
import com.hospital.followup.repository.AccountRepository;
import com.hospital.followup.repository.StaffRepository;
import com.hospital.followup.security.CurrentUser;
import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.security.SecureRandom;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;

/**
 * 管理后台：员工与账号管理。
 *
 * 权限模型（两级）：
 *   - 系统管理员（SUPER_ADMIN）：管理全院账号
 *   - 科室管理者（DEPT_MANAGER 或 staff.is_manager）：只管本科室账号
 * 两者都不是的普通医护，调任何管理接口都会被拒。
 *
 * 【密码处理】新建/重置密码时由系统生成随机初始密码，**只在响应里返回一次**，
 * 库里存的是 BCrypt 哈希，事后无法再查。管理员的职责是"发密码"，不是"看密码"。
 */
@Service
public class AdminService {

    private static final Logger log = LoggerFactory.getLogger(AdminService.class);
    private static final ZoneId ZONE = ZoneId.of("Asia/Shanghai");
    private static final String ROLE_SUPER_ADMIN = "SUPER_ADMIN";
    private static final String ROLE_DEPT_MANAGER = "DEPT_MANAGER";

    /** 初始密码字符集：去掉了 0/O/1/l/I 这些看起来容易读错的字符 */
    private static final char[] PWD_CHARS =
            "ABCDEFGHJKMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789".toCharArray();

    private final StaffRepository staffRepository;
    private final AccountRepository accountRepository;
    private final PasswordEncoder passwordEncoder;
    private final CryptoService cryptoService;
    private final AuditLogService auditLogService;
    private final SecureRandom random = new SecureRandom();

    @PersistenceContext
    private EntityManager em;

    public AdminService(StaffRepository staffRepository,
                        AccountRepository accountRepository,
                        PasswordEncoder passwordEncoder,
                        CryptoService cryptoService,
                        AuditLogService auditLogService) {
        this.staffRepository = staffRepository;
        this.accountRepository = accountRepository;
        this.passwordEncoder = passwordEncoder;
        this.cryptoService = cryptoService;
        this.auditLogService = auditLogService;
    }

    // ------------------------------------------------------------------ 权限

    /** 当前登录人必须是管理员，否则抛 403 */
    public CurrentUser.Principal requireAdmin() {
        CurrentUser.Principal p = CurrentUser.require();
        if (p.staffId() == null || !isAdmin(p.staffId())) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "该功能仅管理员可用");
        }
        return p;
    }

    public boolean isAdmin(Long staffId) {
        if (staffId == null) {
            return false;
        }
        if (hasRole(staffId, ROLE_SUPER_ADMIN)) {
            return true;
        }
        if (hasRole(staffId, ROLE_DEPT_MANAGER)) {
            return true;
        }
        return staffRepository.findById(staffId)
                .map(s -> Boolean.TRUE.equals(s.getIsManager()))
                .orElse(false);
    }

    /** 是否系统管理员（可跨科室） */
    private boolean isSuperAdmin(Long staffId) {
        return hasRole(staffId, ROLE_SUPER_ADMIN);
    }

    private boolean hasRole(Long staffId, String roleCode) {
        Number n = (Number) em.createNativeQuery("""
                select count(*) from staff_role sr
                  join role r on r.id = sr.role_id
                 where sr.staff_id = :sid and r.code = :code
                """).setParameter("sid", staffId).setParameter("code", roleCode).getSingleResult();
        return n != null && n.longValue() > 0;
    }

    /** 数据范围：系统管理员全院，科室管理者仅本科室 */
    private Long scopeDeptId(CurrentUser.Principal admin) {
        return isSuperAdmin(admin.staffId()) ? null : admin.deptId();
    }

    // ------------------------------------------------------------------ 查询

    @Transactional(readOnly = true)
    public AdminDtos.Overview overview() {
        requireAdmin();
        Long deptId = scopeDeptId(CurrentUser.require());

        int staffTotal = count("""
                select count(*) from staff s where s.deleted_at is null
                  and s.dept_id = coalesce(cast(:deptId as bigint), s.dept_id)
                """, deptId);
        int doctorCount = countRole("DOCTOR", deptId);
        int nurseCount = countRole("NURSE", deptId);
        int managerCount = count("""
                select count(*) from staff s where s.deleted_at is null and s.is_manager = true
                  and s.dept_id = coalesce(cast(:deptId as bigint), s.dept_id)
                """, deptId);
        int disabledCount = count("""
                select count(*) from account a join staff s on s.id = a.staff_id
                 where a.deleted_at is null and a.account_type = 'STAFF' and a.status = 'DISABLED'
                   and s.dept_id = coalesce(cast(:deptId as bigint), s.dept_id)
                """, deptId);
        int todayLogin = count("""
                select count(*) from login_log l join account a on a.id = l.account_id
                  join staff s on s.id = a.staff_id
                 where l.success = true and l.created_at >= current_date
                   and s.dept_id = coalesce(cast(:deptId as bigint), s.dept_id)
                """, deptId);
        int pendingTask = count("""
                select count(*) from followup_task t join staff s on s.id = t.assignee_staff_id
                 where t.deleted_at is null and t.status in ('PENDING','DOING')
                   and s.dept_id = coalesce(cast(:deptId as bigint), s.dept_id)
                """, deptId);
        int overdueTask = count("""
                select count(*) from followup_task t join staff s on s.id = t.assignee_staff_id
                 where t.deleted_at is null and t.status in ('PENDING','DOING')
                   and t.due_date < current_date
                   and s.dept_id = coalesce(cast(:deptId as bigint), s.dept_id)
                """, deptId);

        return new AdminDtos.Overview(staffTotal, doctorCount, nurseCount, managerCount,
                disabledCount, todayLogin, pendingTask, overdueTask);
    }

    private int countRole(String roleCode, Long deptId) {
        return count("""
                select count(*) from staff s
                  join staff_role sr on sr.staff_id = s.id
                  join role r on r.id = sr.role_id
                 where s.deleted_at is null and r.code = :role
                   and s.dept_id = coalesce(cast(:deptId as bigint), s.dept_id)
                """, deptId, roleCode);
    }

    private int count(String sql, Long deptId) {
        return count(sql, deptId, null);
    }

    private int count(String sql, Long deptId, String role) {
        var q = em.createNativeQuery(sql).setParameter("deptId", deptId);
        if (role != null) {
            q.setParameter("role", role);
        }
        Number n = (Number) q.getSingleResult();
        return n == null ? 0 : n.intValue();
    }

    /** 账号列表 / 搜索：工号、姓名、角色、状态 */
    @Transactional(readOnly = true)
    public AdminDtos.StaffList listStaff(String keyword, String roleCode, String status) {
        requireAdmin();
        Long deptId = scopeDeptId(CurrentUser.require());

        String kw = (keyword == null || keyword.isBlank()) ? null : "%" + keyword.trim() + "%";
        String role = (roleCode == null || roleCode.isBlank()) ? null : roleCode.trim();
        String st = (status == null || status.isBlank()) ? null : status.trim();

        @SuppressWarnings("unchecked")
        List<Object[]> rows = em.createNativeQuery("""
                select s.id, s.staff_no, s.name, s.title, s.gender, s.is_manager,
                       coalesce((select string_agg(r.code, ',' order by r.code)
                                   from staff_role sr join role r on r.id = sr.role_id
                                  where sr.staff_id = s.id), '') as roles,
                       a.status, a.last_login_at, a.must_change_password
                  from staff s
                  left join account a on a.staff_id = s.id and a.deleted_at is null
                 where s.deleted_at is null
                   and s.dept_id = coalesce(cast(:deptId as bigint), s.dept_id)
                   and (cast(:kw as text) is null
                        or s.name like cast(:kw as text)
                        or s.staff_no like cast(:kw as text)
                        or coalesce(s.phone_mask, '') like cast(:kw as text))
                   and (cast(:role as text) is null or exists (
                         select 1 from staff_role sr2 join role r2 on r2.id = sr2.role_id
                          where sr2.staff_id = s.id and r2.code = cast(:role as text)))
                   and (cast(:st as text) is null or coalesce(a.status, 'NONE') = cast(:st as text))
                 order by s.id
                """)
                .setParameter("deptId", deptId)
                .setParameter("kw", kw)
                .setParameter("role", role)
                .setParameter("st", st)
                .getResultList();

        List<AdminDtos.StaffRow> items = new ArrayList<>(rows.size());
        for (Object[] r : rows) {
            Short gender = r[4] == null ? null : ((Number) r[4]).shortValue();
            items.add(new AdminDtos.StaffRow(
                    ((Number) r[0]).longValue(),
                    (String) r[1],
                    (String) r[2],
                    (String) r[3],
                    gender == null ? "" : (gender == 2 ? "女" : "男"),
                    Boolean.TRUE.equals(r[5]),
                    (String) r[6],
                    r[7] == null ? "未开通" : (String) r[7],
                    toOffsetDateTime(r[8]),
                    Boolean.TRUE.equals(r[9])));
        }
        return new AdminDtos.StaffList(items, items.size());
    }

    @Transactional(readOnly = true)
    public List<AdminDtos.RoleOption> roles() {
        requireAdmin();
        @SuppressWarnings("unchecked")
        List<Object[]> rows = em.createNativeQuery(
                "select code, name, description from role order by id").getResultList();
        List<AdminDtos.RoleOption> list = new ArrayList<>(rows.size());
        for (Object[] r : rows) {
            list.add(new AdminDtos.RoleOption((String) r[0], (String) r[1], (String) r[2]));
        }
        return list;
    }

    /** 最近登录记录：用于排查"这个账号最近是谁在用" */
    @Transactional(readOnly = true)
    public List<AdminDtos.LoginRow> recentLogins(String keyword, int limit) {
        requireAdmin();
        String kw = (keyword == null || keyword.isBlank()) ? null : "%" + keyword.trim() + "%";
        @SuppressWarnings("unchecked")
        List<Object[]> rows = em.createNativeQuery("""
                select l.login_name_masked, l.account_type, l.login_type, l.success,
                       l.fail_reason, l.created_at
                 from login_log l
                 where (cast(:kw as text) is null
                        or coalesce(l.login_name_masked, '') like cast(:kw as text))
                 order by l.created_at desc
                 limit :lim
                """)
                .setParameter("kw", kw)
                .setParameter("lim", Math.max(1, Math.min(limit, 200)))
                .getResultList();
        List<AdminDtos.LoginRow> list = new ArrayList<>(rows.size());
        for (Object[] r : rows) {
            list.add(new AdminDtos.LoginRow(
                    (String) r[0], (String) r[1], (String) r[2],
                    Boolean.TRUE.equals(r[3]), (String) r[4], toOffsetDateTime(r[5])));
        }
        return list;
    }

    // ------------------------------------------------------------------ 写操作

    /**
     * 新建医护账号。系统生成初始密码并只在本次响应返回。
     */
    @Transactional
    public AdminDtos.CreatedStaff createStaff(AdminDtos.CreateStaffRequest req) {
        CurrentUser.Principal admin = requireAdmin();

        String staffNo = req.staffNo().trim().toUpperCase();
        if (staffRepository.findByStaffNoAndDeletedAtIsNull(staffNo).isPresent()) {
            throw new BusinessException(ErrorCode.CONFLICT, "工号 " + staffNo + " 已存在");
        }
        if (accountRepository.findByLoginHashAndDeletedAtIsNull(cryptoService.hash(staffNo)).isPresent()) {
            throw new BusinessException(ErrorCode.CONFLICT, "该工号已经开通过登录账号");
        }

        String roleCode = req.roleCode().trim().toUpperCase();
        Long roleId = roleIdOf(roleCode);
        if (roleId == null) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "角色不存在：" + roleCode);
        }

        // 科室管理者只能在自己科室里建号；系统管理员可以指定，默认建到自己科室
        Long deptId = admin.deptId();
        if (deptId == null) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "当前管理员没有绑定科室，无法建号");
        }

        Staff staff = new Staff();
        staff.setDeptId(deptId);
        staff.setStaffNo(staffNo);
        staff.setName(req.name().trim());
        staff.setTitle(req.title() == null ? null : req.title().trim());
        staff.setGender(req.gender() == null ? (short) 1 : req.gender());
        staff.setStatus((short) 1);
        staff.setIsManager(ROLE_DEPT_MANAGER.equals(roleCode) || ROLE_SUPER_ADMIN.equals(roleCode));
        if (req.phone() != null && !req.phone().isBlank()) {
            String phone = req.phone().trim();
            staff.setPhoneCipher(cryptoService.encrypt(phone));
            staff.setPhoneHash(cryptoService.hash(phone));
            staff.setPhoneMask(cryptoService.maskPhone(phone));
        }
        staffRepository.save(staff);

        String initialPassword = randomPassword();
        Account account = new Account();
        account.setAccountType("STAFF");
        account.setStaffId(staff.getId());
        account.setLoginHash(cryptoService.hash(staffNo));
        account.setLoginDisplay(staffNo);
        account.setPasswordHash(passwordEncoder.encode(initialPassword));
        account.setStatus("ACTIVE");
        account.setFailedAttempts(0);
        account.setMustChangePassword(Boolean.TRUE);
        accountRepository.save(account);

        em.createNativeQuery("""
                insert into staff_role (staff_id, role_id, granted_by, granted_at)
                values (:sid, :rid, :by, now())
                on conflict (staff_id, role_id) do nothing
                """)
                .setParameter("sid", staff.getId())
                .setParameter("rid", roleId)
                .setParameter("by", admin.staffId())
                .executeUpdate();

        audit(admin.staffId(), staff.getId(), "STAFF_CREATE", staffNo,
                "role=" + roleCode + ",mustChangePassword=true");

        log.info("管理员 {} 创建了账号 {}（{}）", admin.staffNo(), staffNo, req.name());
        return new AdminDtos.CreatedStaff(staff.getId(), staffNo, staff.getName(), roleCode,
                initialPassword, true,
                "账号已创建。初始密码只显示这一次，请当场交给本人，并要求首次登录后修改。");
    }

    /** 重置密码：旧密码无法查看，只能重置 */
    @Transactional
    public AdminDtos.ResetPasswordResult resetPassword(Long staffId) {
        CurrentUser.Principal admin = requireAdmin();
        Staff staff = requireStaffInScope(staffId, admin);

        Account account = accountRepository.findByStaffIdAndDeletedAtIsNull(staff.getId())
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "该员工还没有登录账号"));

        String tempPassword = randomPassword();
        account.setPasswordHash(passwordEncoder.encode(tempPassword));
        account.setMustChangePassword(Boolean.TRUE);
        account.setFailedAttempts(0);
        account.setLockedUntil(null);
        if ("DISABLED".equals(account.getStatus())) {
            // 重置密码不自动启用账号，避免"停用的号被悄悄放回来"
            log.info("账号 {} 处于停用状态，重置密码后仍未启用", staff.getStaffNo());
        }
        accountRepository.save(account);

        audit(admin.staffId(), staff.getId(), "STAFF_RESET_PASSWORD", staff.getStaffNo(),
                "tempPasswordIssued=true");

        return new AdminDtos.ResetPasswordResult(staff.getId(), staff.getStaffNo(), staff.getName(),
                tempPassword, true,
                "密码已重置。新密码只显示这一次，请当场交给本人。原密码无法查看（系统只存不可逆哈希）。");
    }

    /** 启用 / 停用账号 */
    @Transactional
    public AdminDtos.StaffRow setStatus(Long staffId, String status) {
        CurrentUser.Principal admin = requireAdmin();
        Staff staff = requireStaffInScope(staffId, admin);

        String st = status.trim().toUpperCase();
        if (!st.equals("ACTIVE") && !st.equals("DISABLED")) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "状态只能是 ACTIVE 或 DISABLED");
        }
        if (staff.getId().equals(admin.staffId())) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "不能停用自己的账号");
        }
        if ("DISABLED".equals(st) && isSuperAdmin(staff.getId())) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "不能停用系统管理员账号");
        }

        Account account = accountRepository.findByStaffIdAndDeletedAtIsNull(staff.getId())
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "该员工还没有登录账号"));
        account.setStatus(st);
        if ("ACTIVE".equals(st)) {
            account.setFailedAttempts(0);
            account.setLockedUntil(null);
        }
        accountRepository.save(account);

        audit(admin.staffId(), staff.getId(), "STAFF_STATUS", staff.getStaffNo(), "status=" + st);
        return listStaff(staff.getStaffNo(), null, null).items().stream()
                .findFirst()
                .orElse(null);
    }

    private Staff requireStaffInScope(Long staffId, CurrentUser.Principal admin) {
        Staff staff = staffRepository.findById(staffId)
                .filter(s -> s.getDeletedAt() == null)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "员工不存在"));
        Long scope = scopeDeptId(admin);
        if (scope != null && !scope.equals(staff.getDeptId())) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "只能管理本科室人员");
        }
        return staff;
    }

    private Long roleIdOf(String code) {
        @SuppressWarnings("unchecked")
        List<Object> ids = em.createNativeQuery("select id from role where code = :code")
                .setParameter("code", code).getResultList();
        return ids.isEmpty() ? null : ((Number) ids.get(0)).longValue();
    }

    /** 生成 10 位随机密码 */
    private String randomPassword() {
        StringBuilder sb = new StringBuilder(10);
        for (int i = 0; i < 10; i++) {
            sb.append(PWD_CHARS[random.nextInt(PWD_CHARS.length)]);
        }
        return sb.toString();
    }

    private void audit(Long byStaffId, Long targetStaffId, String action, String resourceId, String detail) {
        // 统一走 AuditLogService：独立事务 + 自动带上 IP / User-Agent。
        // 建号、重置密码、停用是最需要留痕的管理动作，不能因为主事务回滚而丢失。
        String json = "{\"targetStaffId\":" + targetStaffId
                + ",\"note\":\"" + (detail == null ? "" : detail.replace("\"", "'")) + "\"}";
        auditLogService.record(null, byStaffId, null, action, "staff", resourceId, "SUCCESS", json);
    }

    private static OffsetDateTime toOffsetDateTime(Object o) {
        if (o == null) {
            return null;
        }
        if (o instanceof OffsetDateTime odt) {
            return odt;
        }
        if (o instanceof java.sql.Timestamp ts) {
            return ts.toInstant().atZone(ZONE).toOffsetDateTime();
        }
        if (o instanceof java.time.Instant i) {
            return i.atZone(ZONE).toOffsetDateTime();
        }
        return null;
    }
}
