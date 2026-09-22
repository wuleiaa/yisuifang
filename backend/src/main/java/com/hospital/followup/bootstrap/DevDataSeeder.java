package com.hospital.followup.bootstrap;

import com.hospital.followup.crypto.CryptoService;
import com.hospital.followup.domain.*;
import com.hospital.followup.repository.*;
import com.hospital.followup.security.RlsSession;
import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.Profile;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.util.List;

/**
 * 开发环境演示数据。
 *
 * 只在 dev profile 下运行，生产环境不会执行。
 * 目的是：装上就能登录、就能看到待办，不用手工造数据。
 *
 * 初始账号（密码统一 Followup@2026，首次登录应提示修改）：
 *   D0231  李医生   主治医师（主管医生）
 *   N0455  王护士   主管护师（主管护士）
 *   N0001  张护士长 护士长（科室管理者，可看全科）
 */
@Component
@Profile("dev")
public class DevDataSeeder implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(DevDataSeeder.class);
    private static final String DEMO_PASSWORD = "Followup@2026";
    private static final ZoneId ZONE = ZoneId.of("Asia/Shanghai");

    private final DepartmentRepository deptRepo;
    private final StaffRepository staffRepo;
    private final AccountRepository accountRepo;
    private final CareTeamRepository careTeamRepo;
    private final CareTeamMemberRepository memberRepo;
    private final PatientRepository patientRepo;
    private final EncounterRepository encounterRepo;
    private final DiagnosisRepository diagRepo;
    private final MedicalProcedureRepository procRepo;
    private final FollowupPlanRepository planRepo;
    private final FollowupTaskRepository taskRepo;
    private final PatientCareTeamRepository patientTeamRepo;
    private final PasswordEncoder encoder;
    private final CryptoService crypto;
    private final RlsSession rls;
    private final TransactionTemplate txTemplate;

    @PersistenceContext
    private EntityManager em;

    /**
     * 重置演示数据用。
     *
     * 只清业务数据，保留科室 / 人员 / 账号 / 字典 / 模板这类"配置类"数据，
     * 这样重置后账号密码不变，不用重新登录。
     *
     * 【为什么用 DELETE 而不是 TRUNCATE】
     * 应用连的是 app_rw，它只有 SELECT/INSERT/UPDATE/DELETE，没有 TRUNCATE ——
     * 这是"应用连接不得使用超级用户"这条铁律的直接体现。
     * 为了不在生产库上给应用放开 TRUNCATE，这里改用 DELETE，
     * 并按"子表先删、父表后删"的顺序执行，避免外键冲突。
     * 全程以 is_system 身份运行，因此行级安全策略不会拦（会和不会拦，都符合预期）。
     */
    private static final String[] RESET_STATEMENTS = {
            "delete from followup_task_log",
            "delete from questionnaire_answer",
            "delete from followup_record",
            "delete from notify_log",
            "delete from followup_task",
            "delete from pathology_notification",
            "delete from pathology_interpretation",
            "delete from pathology_pickup",
            "delete from pathology_report",
            "delete from medical_procedure",
            "delete from diagnosis",
            "delete from followup_plan",
            "delete from patient_care_team",
            "delete from encounter",
            "delete from patient_contact",
            "delete from audit_log",
            // 患者端账号挂在患者主档上（fk_account_patient），必须先删账号再删患者。
            // 医护账号（patient_id is null）保留，否则演示密码要重新种一遍。
            "delete from account where patient_id is not null",
            "delete from patient",
            "delete from care_team_member",
            "delete from care_team",
            // 管理后台测试建的临时账号（T8xxxx 界面走查 / T9xxxx 接口测试）不属于演示数据，重置时清掉
            "delete from staff_role where staff_id in (select id from staff where staff_no like 'T8%' or staff_no like 'T9%')",
            "delete from account where staff_id in (select id from staff where staff_no like 'T8%' or staff_no like 'T9%')",
            "delete from staff where staff_no like 'T8%' or staff_no like 'T9%'",
            "delete from login_log"
    };

    public DevDataSeeder(DepartmentRepository deptRepo, StaffRepository staffRepo,
                         AccountRepository accountRepo, CareTeamRepository careTeamRepo,
                         CareTeamMemberRepository memberRepo, PatientRepository patientRepo,
                         EncounterRepository encounterRepo, DiagnosisRepository diagRepo,
                         MedicalProcedureRepository procRepo, FollowupPlanRepository planRepo,
                         FollowupTaskRepository taskRepo, PatientCareTeamRepository patientTeamRepo,
                         PasswordEncoder encoder,
                         CryptoService crypto, RlsSession rls,
                         TransactionTemplate txTemplate) {
        this.deptRepo = deptRepo;
        this.staffRepo = staffRepo;
        this.accountRepo = accountRepo;
        this.careTeamRepo = careTeamRepo;
        this.memberRepo = memberRepo;
        this.patientRepo = patientRepo;
        this.encounterRepo = encounterRepo;
        this.diagRepo = diagRepo;
        this.procRepo = procRepo;
        this.planRepo = planRepo;
        this.taskRepo = taskRepo;
        this.patientTeamRepo = patientTeamRepo;
        this.encoder = encoder;
        this.crypto = crypto;
        this.rls = rls;
        this.txTemplate = txTemplate;
    }

    /**
     * 必须用 TransactionTemplate 而不是 @Transactional：
     * 因为 RlsSession 用的是 set_config(..., is_local=true)，
     * 该设置只在事务内有效；而 @Transactional 在自调用时不会生效，
     * 会导致行级安全策略把演示数据写入拦下来。
     */
    @Override
    public void run(org.springframework.boot.ApplicationArguments args) {
        try {
            txTemplate.executeWithoutResult(status -> seed());
        } catch (Exception e) {
            log.warn("演示数据初始化未完成（不影响服务启动）: {}", e.getMessage());
        }
    }

    /**
     * 清空业务数据并重新生成演示数据。
     *
     * 用途：反复跑联调 / 性能测试时不至于把演示任务消耗光，
     * 也方便演示前把数据恢复成干净状态。
     * 只在 dev profile 可用。
     *
     * @return 重置后各关键表的行数
     */
    public java.util.Map<String, Object> resetAndSeed() {
        return txTemplate.execute(status -> {
            rls.applyAsSystem();
            for (String sql : RESET_STATEMENTS) {
                em.createNativeQuery(sql).executeUpdate();
            }
            seed();
            return java.util.Map.of(
                    "patients", count("patient"),
                    "encounters", count("encounter"),
                    "plans", count("followup_plan"),
                    "tasks", count("followup_task"),
                    "careTeamLinks", count("patient_care_team"));
        });
    }

    private long count(String table) {
        return ((Number) em.createNativeQuery("select count(*) from " + table).getSingleResult()).longValue();
    }

    void seed() {

        // 【必须放在第一行】以系统身份运行，否则后续的"是否已存在"判断
        // 会被行级安全策略挡住（查不到已有数据），从而重复插入导致主键冲突。
        rls.applyAsSystem();

        Department dept = deptRepo.findByCodeAndDeletedAtIsNull("XHNK").orElse(null);
        if (dept == null) {
            log.warn("未找到科室 XHNK，跳过演示数据初始化");
            return;
        }
        Long deptId = dept.getId();

        // ---------- 医护账号 ----------
        Staff doctor = ensureStaff(staffRepo, accountRepo, encoder, crypto,
                deptId, "D0231", "李医生", (short) 1, "主治医师", false);
        Staff nurse = ensureStaff(staffRepo, accountRepo, encoder, crypto,
                deptId, "N0455", "王护士", (short) 2, "主管护师", false);
        Staff headNurse = ensureStaff(staffRepo, accountRepo, encoder, crypto,
                deptId, "N0001", "张护士长", (short) 2, "副主任护师", true);
        // 系统管理员：只有这个账号能进入管理后台管理全院账号
        Staff sysAdmin = ensureStaff(staffRepo, accountRepo, encoder, crypto,
                deptId, "A0001", "系统管理员", (short) 1, "信息科", true);

        // ---------- 角色绑定 ----------
        // role / staff_role 表在 V1 里就建好了，但一直没人写；
        // 管理后台要靠它判断"能不能管账号、能管哪些人"。
        bindRole(doctor.getId(), "DOCTOR");
        bindRole(nurse.getId(), "NURSE");
        bindRole(headNurse.getId(), "DEPT_MANAGER");
        bindRole(sysAdmin.getId(), "SUPER_ADMIN");

        // ---------- 搭档组 ----------
        CareTeam team = careTeamRepo.findByCodeAndDeletedAtIsNull("TEAM-A").orElseGet(() -> {
            CareTeam t = new CareTeam();
            t.setDeptId(deptId);
            t.setCode("TEAM-A");
            t.setName("李医生-王护士 组");
            t.setDoctorId(doctor.getId());
            t.setPrimaryNurseId(nurse.getId());
            t.setStatus((short) 1);
            return careTeamRepo.save(t);
        });

        ensureMember(memberRepo, team.getId(), doctor.getId(), "DOCTOR");
        ensureMember(memberRepo, team.getId(), nurse.getId(), "NURSE");

        // ---------- 演示患者 ----------
        LocalDate today = LocalDate.now();

        // 患者 1：张*春 —— 同时有两条路径（胆总管结石 ERCP + 胆囊结石）
        if (patientRepo.findByPhoneHashAndDeletedAtIsNull(crypto.hash("13800000001")).isEmpty()) {
            Patient p = createPatient(patientRepo, crypto, deptId, "张春", (short) 1, 58,
                    "13800000001", "0003721", "浙江省XX市XX区XX路12号");
            Encounter e = createEncounter(encounterRepo, p, deptId,
                    "2026003721", today.minusDays(9), today.minusDays(3), team.getId());
            addDiagnosis(diagRepo, e, "K80.5", "胆总管结石伴胆管炎");
            addDiagnosis(diagRepo, e, "K80.2", "胆囊结石");
            OffsetDateTime op = at(today.minusDays(5), 14, 0);
            addProcedure(procRepo, e, "ERCP 取石术", op, doctor.getId());
            addProcedure(procRepo, e, "腹腔镜胆囊切除术", at(today.minusDays(5), 16, 30), doctor.getId());

            FollowupPlan plan1 = createPlan(planRepo, deptId, p, e, team.getId(), doctor.getId(),
                    nurse.getId(), "胆总管结石（ERCP 取石术后）", op, e.getDischargeDate());
            FollowupPlan plan2 = createPlan(planRepo, deptId, p, e, team.getId(), doctor.getId(),
                    nurse.getId(), "胆囊结石（腹腔镜胆囊切除术后）", op, e.getDischargeDate());

            // 逾期 2 天的任务（对应原型里最上面那条红色待办）
            createTask(taskRepo, deptId, plan1, p, e, team.getId(), doctor.getId(),
                    "PHONE", "术后 3 天电话回访", at(today.minusDays(2), 9, 0), (short) 1, true);
            createTask(taskRepo, deptId, plan1, p, e, team.getId(), doctor.getId(),
                    "OUTPATIENT", "出院 1 个月门诊复查", at(today.plusDays(25), 9, 0), (short) 2, false);
            createTask(taskRepo, deptId, plan2, p, e, team.getId(), doctor.getId(),
                    "PHONE", "术后 3 天电话回访", at(today.minusDays(2), 9, 0), (short) 1, true);
            createTask(taskRepo, deptId, plan2, p, e, team.getId(), nurse.getId(),
                    "PHONE", "术后 7 天切口检查", at(today.plusDays(2), 9, 0), (short) 2, false);
            log.info("演示数据：已创建患者 张春（双路径）");
        }

        // 患者 2：刘*明 —— 上消化道出血，今日待办
        if (patientRepo.findByPhoneHashAndDeletedAtIsNull(crypto.hash("13800000002")).isEmpty()) {
            Patient p = createPatient(patientRepo, crypto, deptId, "刘明", (short) 1, 45,
                    "13800000002", "0004188", null);
            Encounter e = createEncounter(encounterRepo, p, deptId,
                    "2026004188", today.minusDays(6), today.minusDays(1), team.getId());
            addDiagnosis(diagRepo, e, "K25.4", "十二指肠球部溃疡伴出血");
            FollowupPlan plan = createPlan(planRepo, deptId, p, e, team.getId(), doctor.getId(),
                    nurse.getId(), "消化性溃疡随访路径", null, e.getDischargeDate());

            createTask(taskRepo, deptId, plan, p, e, team.getId(), nurse.getId(),
                    "PHONE", "出院 1 天症状观察", at(today, 9, 0), (short) 1, false);
            createTask(taskRepo, deptId, plan, p, e, team.getId(), doctor.getId(),
                    "OUTPATIENT", "出院 4 周门诊复诊", at(today.plusDays(27), 9, 0), (short) 2, false);
            createTask(taskRepo, deptId, plan, p, e, team.getId(), doctor.getId(),
                    "OUTPATIENT", "胃镜复查（确认愈合、排除恶性）",
                    at(today.plusDays(45), 9, 0), (short) 1, true);
            log.info("演示数据：已创建患者 刘明（上消化道出血）");
        }

        // 患者 3：陈*芳 —— 结肠息肉，今日待办
        if (patientRepo.findByPhoneHashAndDeletedAtIsNull(crypto.hash("13800000003")).isEmpty()) {
            Patient p = createPatient(patientRepo, crypto, deptId, "陈芳", (short) 2, 61,
                    "13800000003", "0005201", null);
            Encounter e = createEncounter(encounterRepo, p, deptId,
                    "2026005201", today.minusDays(5), today.minusDays(1), team.getId());
            addDiagnosis(diagRepo, e, "K57.3", "结肠息肉");
            OffsetDateTime op = at(today.minusDays(2), 10, 0);
            addProcedure(procRepo, e, "内镜下结肠息肉切除术（EMR）", op, doctor.getId());
            FollowupPlan plan = createPlan(planRepo, deptId, p, e, team.getId(), doctor.getId(),
                    nurse.getId(), "结肠息肉切除术后随访路径", op, e.getDischargeDate());

            createTask(taskRepo, deptId, plan, p, e, team.getId(), doctor.getId(),
                    "PHONE", "术后 3 天电话回访", at(today, 9, 0), (short) 1, false);
            createTask(taskRepo, deptId, plan, p, e, team.getId(), nurse.getId(),
                    "SYSTEM_NOTIFY", "病理报告出具后通知患者", at(today.plusDays(3), 9, 0), (short) 2, false);
            createTask(taskRepo, deptId, plan, p, e, team.getId(), doctor.getId(),
                    "OUTPATIENT", "术后 6-12 个月复查肠镜", at(today.plusDays(180), 9, 0), (short) 3, false);
            log.info("演示数据：已创建患者 陈芳（结肠息肉）");
        }

        log.info("""

                演示账号已就绪（密码统一为 {}）：
                  工号 A0001  系统管理员 超级管理员（可进入管理后台）
                  工号 D0231  李医生   主治医师
                  工号 N0455  王护士   主管护师
                  工号 N0001  张护士长 护士长（科室管理者）
                """, DEMO_PASSWORD);

        // ---------- 归属关系补齐 ----------
        // 【关键】必须为每一位患者建立"患者 ↔ 搭档组"的关系，
        // 否则数据库行级安全策略会让医护看得到任务、却看不到患者。
        // 这一步不放在患者创建分支里，是为了让历史数据也能补齐。
        int fixed = 0;
        for (var pct : patientRepo.findAll()) {
            for (var enc : encounterRepo.findByPatientIdAndDeletedAtIsNullOrderByDischargeDateDesc(pct.getId())) {
                if (patientTeamRepo.findByEncounterIdAndStatus(enc.getId(), "ACTIVE").isEmpty()) {
                    PatientCareTeam rel = new PatientCareTeam();
                    rel.setPatientId(pct.getId());
                    rel.setEncounterId(enc.getId());
                    rel.setTeamId(team.getId());
                    rel.setDoctorId(doctor.getId());
                    rel.setNurseId(nurse.getId());
                    rel.setAssignedBy(doctor.getId());
                    rel.setStatus("ACTIVE");
                    patientTeamRepo.save(rel);
                    fixed++;
                }
            }
        }
        if (fixed > 0) {
            log.info("演示数据：已补齐 {} 条患者-搭档组归属关系（行级权限依赖此关系）", fixed);
        }

        // ---------- 患者端账号 ----------
        // 患者用"手机号 + 短信验证码"登录，不需要密码。
        // 这里独立成一段（而不是写在患者创建分支里），是为了让已有数据的库也能补上账号。
        int accounts = ensurePatientAccounts(accountRepo, encoder, crypto);
        if (accounts > 0) {
            log.info("演示数据：已创建 {} 个患者端账号", accounts);
        }

        // ---------- 患者端要用的问卷与病理报告 ----------
        ensureQuestionnaire();
        ensurePathologyDemo();
    }

    // ------------------------------------------------------------ 患者端演示数据

    /** 演示患者的手机号（明文只在这里出现，库里存的是哈希与密文） */
    private static final List<String> DEMO_PATIENT_PHONES =
            List.of("13800000001", "13800000002", "13800000003");

    private int ensurePatientAccounts(AccountRepository repo, PasswordEncoder encoder, CryptoService crypto) {
        int created = 0;
        for (String phone : DEMO_PATIENT_PHONES) {
            for (Patient p : patientRepo.findByPhoneHashAndDeletedAtIsNull(crypto.hash(phone))) {
                if (repo.findByPatientIdAndDeletedAtIsNull(p.getId()).isPresent()) {
                    continue;
                }
                Account a = new Account();
                a.setAccountType("PATIENT");
                a.setPatientId(p.getId());
                a.setLoginHash(crypto.hash(phone));
                a.setLoginDisplay(p.getPhoneMask());
                // 患者没有密码：存一个随机 BCrypt 值，
                // 既满足"密码列非空"，又保证任何人都猜不到。
                a.setPasswordHash(encoder.encode(java.util.UUID.randomUUID().toString()));
                a.setStatus("ACTIVE");
                a.setFailedAttempts(0);
                a.setMustChangePassword(Boolean.FALSE);
                repo.save(a);
                created++;
            }
        }
        return created;
    }

    /** 术后基础随访问卷（患者端可以自己填） */
    private void ensureQuestionnaire() {
        Number existing = (Number) em.createNativeQuery(
                "select count(*) from questionnaire where code = 'POST_OP_BASIC'").getSingleResult();
        if (existing != null && existing.longValue() > 0) {
            return;
        }
        Object qid = em.createNativeQuery("""
                        insert into questionnaire (code, name, version, description, status)
                        values ('POST_OP_BASIC', '术后恢复情况问卷', 1,
                                '出院后患者自评：症状、饮食、用药', 'ACTIVE')
                        returning id
                        """).getSingleResult();

        String[][] questions = {
                {"SINGLE", "这两天有没有腹痛？", "[\"没有\",\"轻微\",\"明显\",\"很严重\"]", "true"},
                {"SINGLE", "饮食恢复情况？", "[\"正常饮食\",\"半流质\",\"只能喝粥\",\"吃不下\"]", "true"},
                {"SINGLE", "有没有按时吃药？", "[\"按时吃\",\"偶尔忘\",\"没吃\"]", "true"},
                {"TEXT", "其他想告诉医生的情况（可不填）", null, "false"}
        };
        for (int i = 0; i < questions.length; i++) {
            String[] q = questions[i];
            var query = em.createNativeQuery("""
                    insert into questionnaire_question
                        (questionnaire_id, seq_no, question_type, title, options, is_required)
                    values (:qid, :seq, :type, :title, cast(:options as jsonb), :required)
                    """)
                    .setParameter("qid", qid)
                    .setParameter("seq", i + 1)
                    .setParameter("type", q[0])
                    .setParameter("title", q[1])
                    .setParameter("required", Boolean.parseBoolean(q[3]));
            if (q[2] == null) {
                query.setParameter("options", null);
            } else {
                query.setParameter("options", q[2]);
            }
            query.executeUpdate();
        }
        log.info("演示数据：已创建术后随访问卷（4 道题）");
    }

    /**
     * 病理报告演示数据。
     *
     * 刻意造两条：
     *   - 陈芳：已发布（患者端应该看得到）
     *   - 张春：未发布（患者端**不应该**看得到）
     * 这样"患者端只能看已发布报告"这条规则才是被真实验证过的，
     * 而不是只写在需求文档里。
     */
    private void ensurePathologyDemo() {
        Number existing = (Number) em.createNativeQuery(
                "select count(*) from pathology_report").getSingleResult();
        if (existing != null && existing.longValue() > 0) {
            return;
        }

        Long chenFang = patientIdByPhone("13800000003");
        Long zhangChun = patientIdByPhone("13800000001");
        if (chenFang == null || zhangChun == null) {
            return;
        }

        // 主管医生，用于填 entered_by / reviewed_by
        // 【注意】数据库上有硬约束：报告必须经主管医生审核（reviewed_by）后才能置为 PUBLISHED。
        // 少了这两个字段，插入会被直接拒绝——这正是第 3 轮病理闭环要求的落地。
        Object doctorId = em.createNativeQuery(
                "select id from staff where staff_no = 'D0231' and deleted_at is null").getSingleResult();

        // 陈芳：结肠息肉病理
        // 【必须分三步】数据库的发布闸门（tg_pathology_publish_gate）要求：
        //   1. 已审核（reviewed_by 非空）
        //   2. 已填写医生解读（pathology_interpretation 有记录）
        //   3. 高风险还需先完成患者告知（pathology_notification）
        // 所以不能一条 insert 直接写 PUBLISHED，只能"录入 → 写解读 → 发布"。
        Object reportId = em.createNativeQuery("""
                        insert into pathology_report
                            (patient_id, encounter_id, report_no, specimen_site, report_date,
                             conclusion, risk_level, status, version_no, is_final,
                             entered_by, entered_at, reviewed_by, reviewed_at)
                        values (:pid,
                                (select id from encounter where patient_id = :pid
                                  and deleted_at is null order by discharge_date desc limit 1),
                                'BL20260915-001', '结肠息肉（乙状结肠）', current_date,
                                '管状腺瘤，低级别上皮内瘤变，切缘阴性。',
                                'ATTENTION', 'PENDING_REVIEW', 1, false,
                                :doc, now(), :doc, now())
                        returning id
                        """)
                .setParameter("pid", chenFang)
                .setParameter("doc", doctorId)
                .getSingleResult();

        // 第二步：填写医生解读（用大白话写，患者端直接看到的就是这段）
        em.createNativeQuery("""
                        insert into pathology_interpretation
                            (report_id, plain_text, followup_advice, recheck_months, written_by, written_at)
                        values (:rid, :text, :advice, 12, :doc, now())
                        """)
                .setParameter("rid", reportId)
                .setParameter("doc", doctorId)
                .setParameter("text", "这是良性病变，切干净了，不用紧张。")
                .setParameter("advice", "6-12 个月复查一次肠镜")
                .executeUpdate();

        // 第三步：发布（经过闸门校验）
        em.createNativeQuery("""
                        update pathology_report
                           set status = 'PUBLISHED', is_final = true, published_at = now()
                         where id = :rid
                        """).setParameter("rid", reportId).executeUpdate();

        // 张春：还在录入中，未发布 —— 患者端看不到
        em.createNativeQuery("""
                        insert into pathology_report
                            (patient_id, encounter_id, report_no, specimen_site, report_date,
                             conclusion, risk_level, status, version_no, is_final,
                             entered_by, entered_at)
                        values (:pid,
                                (select id from encounter where patient_id = :pid
                                  and deleted_at is null order by discharge_date desc limit 1),
                                'BL20260915-002', '胆囊', current_date,
                                '慢性胆囊炎，待医生审核。', 'LOW', 'DRAFT', 1, false,
                                :doc, now())
                        """).setParameter("pid", zhangChun).setParameter("doc", doctorId).executeUpdate();

        log.info("演示数据：已创建 2 条病理报告（1 条已发布 / 1 条未发布）");
    }

    private Long patientIdByPhone(String phone) {
        List<Patient> list = patientRepo.findByPhoneHashAndDeletedAtIsNull(crypto.hash(phone));
        return list.isEmpty() ? null : list.get(0).getId();
    }

    /** 绑定角色（幂等：重复执行不会重复插入） */
    private void bindRole(Long staffId, String roleCode) {
        em.createNativeQuery("""
                        insert into staff_role (staff_id, role_id, granted_by, granted_at)
                        select :sid, r.id, :sid, now() from role r where r.code = :code
                        on conflict (staff_id, role_id) do nothing
                        """)
                .setParameter("sid", staffId)
                .setParameter("code", roleCode)
                .executeUpdate();
    }

    // ------------------------------------------------------------------ 辅助方法

    private Staff ensureStaff(StaffRepository staffRepo, AccountRepository accountRepo,
                              PasswordEncoder encoder, CryptoService crypto,
                              Long deptId, String staffNo, String name, short gender,
                              String title, boolean manager) {
        Staff staff = staffRepo.findByStaffNoAndDeletedAtIsNull(staffNo).orElseGet(() -> {
            Staff s = new Staff();
            s.setDeptId(deptId);
            s.setStaffNo(staffNo);
            s.setName(name);
            s.setGender(gender);
            s.setTitle(title);
            s.setStatus((short) 1);
            s.setIsManager(manager);
            s.setPhoneMask("138****0000");
            s.setPhoneHash(crypto.hash("1390000" + staffNo));
            s.setPhoneCipher(crypto.encrypt("1390000" + staffNo));
            return staffRepo.save(s);
        });

        if (accountRepo.findByStaffIdAndDeletedAtIsNull(staff.getId()).isEmpty()) {
            Account a = new Account();
            a.setAccountType("STAFF");
            a.setLoginHash(crypto.hash(staffNo.toUpperCase()));
            a.setLoginDisplay(staffNo);
            a.setPasswordHash(encoder.encode(DEMO_PASSWORD));
            a.setStaffId(staff.getId());
            a.setStatus("ACTIVE");
            a.setFailedAttempts(0);
            // 【演示账号不强制改密】这些账号是 dev 环境专用的演示账号，
            // 密码是公开写在文档里的 Followup@2026，本来就是给人随便登的；
            // 若标记成"必须改密"，本地冒烟测试与演示流程每次都要先改一遍密码。
            // 真正的安全边界在"管理后台建号 / 重置密码"那条路：
            // 那里生成的是一次性初始密码，仍然强制本人首次登录后修改
            // （见 AdminService.createStaff / resetPassword）。
            a.setMustChangePassword(Boolean.FALSE);
            accountRepo.save(a);
        }
        return staff;
    }

    private void ensureMember(CareTeamMemberRepository repo, Long teamId, Long staffId, String role) {
        boolean exists = repo.findByStaffId(staffId).stream().anyMatch(m -> m.getTeamId().equals(teamId));
        if (!exists) {
            CareTeamMember m = new CareTeamMember();
            m.setTeamId(teamId);
            m.setStaffId(staffId);
            m.setMemberRole(role);
            m.setIsPrimary(true);
            repo.save(m);
        }
    }

    private Patient createPatient(PatientRepository repo, CryptoService crypto, Long deptId,
                                  String name, short gender, int age, String phone,
                                  String mrn, String address) {
        Patient p = new Patient();
        p.setDeptId(deptId);
        p.setName(name);
        p.setGender(gender);
        p.setAge(age);
        p.setMedicalRecordNo(mrn);
        p.setAddress(address);
        p.setPhoneHash(crypto.hash(phone));
        p.setPhoneCipher(crypto.encrypt(phone));
        p.setPhoneMask(crypto.maskPhone(phone));
        p.setStatus("ACTIVE");
        return repo.save(p);
    }

    private Encounter createEncounter(EncounterRepository repo, Patient p, Long deptId,
                                      String inpatientNo, LocalDate admit, LocalDate discharge,
                                      Long teamId) {
        Encounter e = new Encounter();
        e.setPatientId(p.getId());
        e.setDeptId(deptId);
        e.setInpatientNo(inpatientNo);
        e.setVisitSeq(1);
        e.setAdmitDate(admit);
        e.setDischargeDate(discharge);
        e.setStayDays((int) (discharge.toEpochDay() - admit.toEpochDay()));
        e.setDischargeType("1");
        e.setCareTeamId(teamId);
        return repo.save(e);
    }

    private void addDiagnosis(DiagnosisRepository repo, Encounter e, String icd, String name) {
        Diagnosis d = new Diagnosis();
        d.setEncounterId(e.getId());
        d.setPatientId(e.getPatientId());
        d.setDiagType("DISCHARGE");
        d.setSeqNo(1);
        d.setIsPrimary(true);
        d.setIcdCode(icd);
        d.setDiagnosisName(name);
        repo.save(d);
    }

    private void addProcedure(MedicalProcedureRepository repo, Encounter e, String name,
                              OffsetDateTime when, Long surgeonId) {
        MedicalProcedure m = new MedicalProcedure();
        m.setEncounterId(e.getId());
        m.setPatientId(e.getPatientId());
        m.setProcedureName(name);
        m.setProcedureDate(when);
        m.setIsPrimary(true);
        m.setSurgeonId(surgeonId);
        repo.save(m);
    }

    private FollowupPlan createPlan(FollowupPlanRepository repo, Long deptId, Patient p, Encounter e,
                                    Long teamId, Long doctorId, Long nurseId, String label,
                                    OffsetDateTime anchorProcedure, LocalDate anchorDischarge) {
        FollowupPlan pl = new FollowupPlan();
        pl.setDeptId(deptId);
        pl.setPatientId(p.getId());
        pl.setEncounterId(e.getId());
        pl.setCareTeamId(teamId);
        pl.setDoctorId(doctorId);
        pl.setNurseId(nurseId);
        pl.setPathwayLabel(label);
        pl.setAnchorProcedureAt(anchorProcedure);
        pl.setAnchorDischargeDate(anchorDischarge);
        pl.setTemplateVersion(1);
        pl.setStatus("ACTIVE");
        return repo.save(pl);
    }

    private void createTask(FollowupTaskRepository repo, Long deptId, FollowupPlan plan, Patient p,
                            Encounter e, Long teamId, Long assignee, String type, String title,
                            OffsetDateTime dueAt, short priority, boolean mandatory) {
        FollowupTask t = new FollowupTask();
        t.setDeptId(deptId);
        t.setPlanId(plan.getId());
        t.setPatientId(p.getId());
        t.setEncounterId(e.getId());
        t.setCareTeamId(teamId);
        t.setTaskType(type);
        t.setTitle(title);
        t.setDueAt(dueAt);
        t.setDueDate(dueAt.atZoneSameInstant(ZONE).toLocalDate());
        t.setRemindStartAt(dueAt.minusHours(2));
        t.setPriority(priority);
        t.setIsMandatory(mandatory);
        t.setStatus("PENDING");
        t.setAssigneeStaffId(assignee);
        t.setRemindCount(0);
        t.setOverdueDays(0);
        repo.save(t);
    }

    private static OffsetDateTime at(LocalDate date, int hour, int minute) {
        return date.atTime(LocalTime.of(hour, minute)).atZone(ZONE).toOffsetDateTime();
    }

    @SuppressWarnings("unused")
    private static String utf8(String s) {
        return new String(s.getBytes(StandardCharsets.UTF_8), StandardCharsets.UTF_8);
    }

    @SuppressWarnings("unused")
    private static List<String> noop() {
        return List.of();
    }
}
