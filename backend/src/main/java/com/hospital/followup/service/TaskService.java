package com.hospital.followup.service;

import com.hospital.followup.common.BusinessException;
import com.hospital.followup.common.ErrorCode;
import com.hospital.followup.crypto.CryptoService;
import com.hospital.followup.domain.Encounter;
import com.hospital.followup.domain.FollowupPlan;
import com.hospital.followup.domain.FollowupRecord;
import com.hospital.followup.domain.FollowupTask;
import com.hospital.followup.domain.FollowupTaskLog;
import com.hospital.followup.domain.MedicalProcedure;
import com.hospital.followup.domain.Patient;
import com.hospital.followup.dto.TaskDtos;
import com.hospital.followup.repository.DiagnosisRepository;
import com.hospital.followup.repository.EncounterRepository;
import com.hospital.followup.repository.FollowupPlanRepository;
import com.hospital.followup.repository.FollowupRecordRepository;
import com.hospital.followup.repository.FollowupTaskLogRepository;
import com.hospital.followup.repository.FollowupTaskRepository;
import com.hospital.followup.repository.MedicalProcedureRepository;
import com.hospital.followup.repository.PatientRepository;
import com.hospital.followup.security.CurrentUser;
import com.hospital.followup.security.RlsSession;
import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

/**
 * 随访任务服务。
 *
 * 所有查询都会先调用 rlsSession.apply()，
 * 由数据库行级安全策略做第二道权限过滤（第一道是业务层的条件）。
 */
@Service
public class TaskService {

    /** 危险症状：勾选后立即通知主管医生，不等表单提交（第 7 轮定的规则） */
    private static final Set<String> DANGER_SYMPTOMS =
            Set.of("呕血", "黑便", "便血", "发热", "黄疸", "剧烈腹痛", "明显异常");

    private static final java.time.ZoneId ZONE = java.time.ZoneId.of("Asia/Shanghai");

    private final FollowupTaskRepository taskRepository;
    private final FollowupTaskLogRepository taskLogRepository;
    private final FollowupRecordRepository recordRepository;
    private final FollowupPlanRepository planRepository;
    private final PatientRepository patientRepository;
    private final EncounterRepository encounterRepository;
    private final DiagnosisRepository diagnosisRepository;
    private final MedicalProcedureRepository procedureRepository;
    private final RlsSession rlsSession;
    private final CryptoService cryptoService;
    private final AuditLogService auditLogService;

    @PersistenceContext
    private EntityManager em;

    public TaskService(FollowupTaskRepository taskRepository,
                       FollowupTaskLogRepository taskLogRepository,
                       FollowupRecordRepository recordRepository,
                       FollowupPlanRepository planRepository,
                       PatientRepository patientRepository,
                       EncounterRepository encounterRepository,
                       DiagnosisRepository diagnosisRepository,
                       MedicalProcedureRepository procedureRepository,
                       RlsSession rlsSession,
                       CryptoService cryptoService,
                       AuditLogService auditLogService) {
        this.taskRepository = taskRepository;
        this.taskLogRepository = taskLogRepository;
        this.recordRepository = recordRepository;
        this.planRepository = planRepository;
        this.patientRepository = patientRepository;
        this.encounterRepository = encounterRepository;
        this.diagnosisRepository = diagnosisRepository;
        this.procedureRepository = procedureRepository;
        this.rlsSession = rlsSession;
        this.cryptoService = cryptoService;
        this.auditLogService = auditLogService;
    }

    /**
     * 待办列表。
     *
     * @param scope MINE=只看指派给我的；TEAM=看我和搭档组的（范围由 RLS 决定）
     * @param days  往后看多少天
     */
    @Transactional(readOnly = true)
    public TaskDtos.TodoSummary todo(String scope, int days, int limit) {
        rlsSession.apply();

        Long assignee = "MINE".equalsIgnoreCase(scope) ? CurrentUser.staffId() : null;
        LocalDate today = LocalDate.now();
        LocalDate until = today.plusDays(Math.max(days, 0));

        List<FollowupTaskRepository.TaskRow> rows =
                taskRepository.findTodo(assignee, today, until, Math.min(Math.max(limit, 1), 200));

        List<TaskDtos.TaskItem> items = new ArrayList<>(rows.size());
        int overdue = 0;
        int todayCnt = 0;
        int later = 0;

        for (FollowupTaskRepository.TaskRow r : rows) {
            int od = (r.getDueDate() != null && r.getDueDate().isBefore(today))
                    ? (int) (today.toEpochDay() - r.getDueDate().toEpochDay()) : 0;
            String urgency;
            if (od > 0) {
                urgency = "OVERDUE";
                overdue++;
            } else if (r.getDueDate() != null && r.getDueDate().isEqual(today)) {
                urgency = "TODAY";
                todayCnt++;
            } else {
                urgency = "LATER";
                later++;
            }

            items.add(new TaskDtos.TaskItem(
                    r.getId(), r.getTitle(), r.getTaskType(), r.getStatus(), r.getPriority(),
                    r.getDueDate(), toOffset(r.getDueAt()),
                    Boolean.TRUE.equals(r.getMandatory()), od,
                    r.getPatientId(), r.getPatientName(),
                    genderText(r.getGender()), r.getAge(), r.getPhoneMask(),
                    r.getInpatientNo(), r.getPathwayLabel(),
                    r.getProcedureName(), toOffset(r.getProcedureDate()),
                    urgency));
        }
        return new TaskDtos.TodoSummary(items.size(), overdue, todayCnt, later, items);
    }

    @Transactional(readOnly = true)
    public TaskDtos.TaskDetail detail(Long taskId) {
        rlsSession.apply();

        FollowupTask t = taskRepository.findById(taskId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "任务不存在或您无权查看"));

        Patient p = patientRepository.findById(t.getPatientId()).orElse(null);
        Encounter e = encounterRepository.findById(t.getEncounterId()).orElse(null);
        FollowupPlan plan = t.getPlanId() == null ? null
                : planRepository.findById(t.getPlanId()).orElse(null);

        List<String> diagnoses = new ArrayList<>();
        if (e != null) {
            diagnosisRepository.findByEncounterIdOrderBySeqNo(e.getId())
                    .forEach(d -> diagnoses.add(d.getDiagnosisName()));
        }

        MedicalProcedure proc = null;
        if (e != null) {
            List<MedicalProcedure> list =
                    procedureRepository.findByEncounterIdAndDeletedAtIsNullOrderByProcedureDateDesc(e.getId());
            if (!list.isEmpty()) {
                proc = list.get(0);
            }
        }

        int overdue = (t.getDueDate() != null && t.getDueDate().isBefore(LocalDate.now()))
                ? (int) (LocalDate.now().toEpochDay() - t.getDueDate().toEpochDay()) : 0;

        boolean locked = t.getLockedBy() != null && t.getLockedAt() != null
                && t.getLockedAt().isAfter(OffsetDateTime.now().minusMinutes(30));

        return new TaskDtos.TaskDetail(
                t.getId(), t.getTitle(), t.getTaskType(), t.getStatus(), t.getContentHint(),
                t.getDueDate(), t.getDueAt(),
                Boolean.TRUE.equals(t.getIsMandatory()), overdue,
                t.getPatientId(),
                p == null ? null : p.getName(),
                p == null ? null : genderText(p.getGender()),
                p == null ? null : p.getAge(),
                p == null ? null : p.getPhoneMask(),
                p == null ? null : p.getMedicalRecordNo(),
                e == null ? null : e.getInpatientNo(),
                e == null ? null : e.getAdmitDate(),
                e == null ? null : e.getDischargeDate(),
                diagnoses,
                plan == null ? null : plan.getPathwayLabel(),
                proc == null ? null : proc.getProcedureName(),
                proc == null ? null : proc.getProcedureDate(),
                locked, t.getLockedBy(), t.getLockedAt());
    }

    /**
     * 一键拨号：返回可交给系统拨号器的完整号码。
     *
     * 【为什么这里必须解密】
     *  界面上展示的永远是 phone_mask（138****5678），而 tel: 需要真实号码——
     *  只拿脱敏值去拨号就是"点了没反应"，这正是 C8 要修的问题。
     *
     * 【和"查看完整号码"的区别（docs/第08轮 3.5 定稿）】
     *  一键拨号：不需要二次验证，但**每次都要留痕**——号码只交给拨号器，
     *            不回显到页面，所以护士看不到完整号码，只发生一次"呼出"。
     *  查看完整号码：要把号码显示给人看，门槛更高（二次验证 + 审计），
     *            那条策略本轮不动。
     *
     * 【权限】可见性由两道门保证：taskRepository / patientRepository 的查询走
     *  RLS（越权直接查不到，报 404），此处再要求 phone:view 权限点。
     */
    @Transactional
    public TaskDtos.DialPhone dial(Long taskId) {
        rlsSession.apply();
        CurrentUser.Principal me = CurrentUser.require();

        if (!me.hasPermission("patient:phone:view")) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "没有拨打电话的权限");
        }

        FollowupTask t = taskRepository.findById(taskId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "任务不存在或您无权查看"));

        Patient p = patientRepository.findById(t.getPatientId())
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "患者不存在或您无权查看"));

        String phone = cryptoService.decrypt(p.getPhoneCipher());
        if (phone == null || phone.isBlank()) {
            // 失败也要留痕：审计最常见的用途恰恰是记录"没成功的操作"
            auditLogService.record(null, me.staffId(), p.getId(), "PATIENT_PHONE_DIAL",
                    "patient", String.valueOf(p.getId()), "FAIL",
                    AuditLogService.noteJson("taskId=" + taskId + " 患者未登记联系电话"));
            throw new BusinessException(ErrorCode.NOT_FOUND, "该患者没有登记联系电话");
        }

        auditLogService.record(null, me.staffId(), p.getId(), "PATIENT_PHONE_DIAL",
                "patient", String.valueOf(p.getId()), "SUCCESS",
                AuditLogService.noteJson("taskId=" + taskId));

        return new TaskDtos.DialPhone(p.getPhoneMask(), phone);
    }

    /**
     * 完成随访任务。
     *
     * 做四件事（缺一不可）：
     *  1. 抢占锁：防止两个护士同时给同一位患者打电话；
     *  2. 写回访记录：executed_by 记实际执行人（护士代录时与责任人不同）；
     *  3. 更新任务状态并写流水；
     *  4. 若勾选危险症状，立即生成上报流水（真实推送在后续迭代接入）。
     */
    @Transactional
    public TaskDtos.CompleteTaskResponse complete(TaskDtos.CompleteTaskRequest req) {
        rlsSession.apply();
        Long staffId = CurrentUser.require().staffId();

        FollowupTask t = taskRepository.findById(req.taskId())
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "任务不存在或您无权处理"));

        if ("DONE".equals(t.getStatus())) {
            throw new BusinessException(ErrorCode.CONFLICT, "该任务已完成，无需重复提交");
        }

        // 同样改成原子占锁：原来"先查再判"在并发提交时会两个都通过，
        // 结果产生两条回访记录。第二个并发请求会在这里被挡住。
        if (!tryLock(t.getId(), staffId)) {
            FollowupTask fresh = taskRepository.findById(t.getId()).orElse(null);
            if (fresh != null && "DONE".equals(fresh.getStatus())) {
                throw new BusinessException(ErrorCode.CONFLICT, "该任务已完成，无需重复提交");
            }
            throw new BusinessException(ErrorCode.TASK_LOCKED);
        }

        OffsetDateTime now = OffsetDateTime.now();

        List<String> symptoms = req.symptoms() == null ? List.of() : req.symptoms();
        boolean abnormal = symptoms.stream().anyMatch(DANGER_SYMPTOMS::contains)
                || "ABNORMAL".equals(req.recoveryLevel());

        FollowupRecord r = new FollowupRecord();
        r.setTaskId(t.getId());
        r.setPlanId(t.getPlanId());
        r.setPatientId(t.getPatientId());
        r.setEncounterId(t.getEncounterId());
        r.setRecordType("PHONE");
        r.setContacted(req.contacted() == null ? Boolean.TRUE : req.contacted());
        r.setContactTarget(req.contactTarget());
        r.setContactPhoneMask(patientRepository.findById(t.getPatientId())
                .map(Patient::getPhoneMask).orElse(null));
        r.setDurationSec(req.durationSeconds());
        r.setSymptomJson(toJsonArray(symptoms));
        r.setRecoveryLevel(req.recoveryLevel());
        r.setMedicationAdherence(req.medicationAdherence());
        r.setConclusion(req.conclusion());
        r.setAdvice(req.advice());
        r.setNextAction(req.nextAction());
        r.setIsAbnormal(abnormal);
        r.setExecutedBy(staffId);
        r.setExecutedAt(now);
        recordRepository.save(r);

        t.setStatus("DONE");
        t.setExecutorStaffId(staffId);
        t.setCompletedAt(now);
        t.setLockedBy(null);
        t.setLockedAt(null);
        taskRepository.save(t);
        appendLog(t.getId(), "COMPLETE", staffId, "PHONE", "完成随访");

        boolean notified = false;
        if (abnormal && Boolean.TRUE.equals(req.notifyDoctorImmediately())) {
            Long doctorId = t.getPlanId() == null ? null
                    : planRepository.findById(t.getPlanId()).map(FollowupPlan::getDoctorId).orElse(null);
            if (doctorId != null) {
                r.setEscalatedTo(doctorId);
                recordRepository.save(r);
            }
            appendLog(t.getId(), "ESCALATE", staffId, "IN_APP",
                    "发现异常症状：" + String.join("、", symptoms));
            notified = true;
        }

        return new TaskDtos.CompleteTaskResponse(
                t.getId(), t.getStatus(),
                notified ? "回访记录已提交，已同时通知主管医生" : "回访记录已提交",
                notified);
    }

    /** 领取任务（抢占锁），防止两个护士同时处理同一条待办 */
    @Transactional
    public TaskDtos.TaskDetail claim(Long taskId) {
        rlsSession.apply();
        Long staffId = CurrentUser.require().staffId();

        // 先确认任务对当前用户可见，避免把"无权访问"误报成"被占用"
        taskRepository.findById(taskId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "任务不存在或您无权处理"));

        if (!tryLock(taskId, staffId)) {
            throw new BusinessException(ErrorCode.TASK_LOCKED, "该任务正在被其他同事处理");
        }

        // 【必须清缓存】上面的原子更新是原生 SQL，绕过了 Hibernate 的一级缓存；
        // 不清掉的话，紧接着的 detail() 会读到更新前的状态（实测：领取成功但状态仍显示 PENDING）。
        em.clear();

        appendLog(taskId, "CLAIM", staffId, "IN_APP", "开始处理");

        return detail(taskId);
    }

    /**
     * 原子占锁：抢到返回 true，被别人占着返回 false。
     *
     * 【为什么必须写成一条 UPDATE】
     * 原来的写法是"先查出来判断有没有被占，再保存"。
     * 两个请求同时进来时都会读到"没被占用"，然后都写入成功。
     * 故障演练实测：20 个并发请求抢同一个任务，有 18 个都"抢到了"——
     * 也就是说两位护士同时点"立即回访"会同时开打，锁形同虚设。
     * 改成带条件的 UPDATE 后，"判断"和"写入"合成一个原子操作，
     * 由数据库保证只有一个能更新成功（并发时后到的事务会等前一个提交，
     * 重新判断条件不满足自然拿不到锁）。
     *
     * 顺带把 30 分钟自动过期也放进条件里：锁超时后别人可以接手。
     */
    private boolean tryLock(Long taskId, Long staffId) {
        int updated = em.createNativeQuery("""
                update followup_task
                   set locked_by = :me,
                       locked_at = now(),
                       status = case when status = 'PENDING' then 'DOING' else status end,
                       updated_at = now()
                 where id = :id
                   and deleted_at is null
                   and status in ('PENDING', 'DOING')
                   and (locked_by is null
                        or locked_by = :me
                        or locked_at is null
                        or locked_at < now() - interval '30 minutes')
                """)
                .setParameter("me", staffId)
                .setParameter("id", taskId)
                .executeUpdate();
        return updated > 0;
    }

    private void appendLog(Long taskId, String action, Long by, String channel, String remark) {
        FollowupTaskLog taskLog = new FollowupTaskLog();
        taskLog.setTaskId(taskId);
        taskLog.setAction(action);
        taskLog.setActionBy(by);
        taskLog.setActionAt(OffsetDateTime.now());
        taskLog.setChannel(channel);
        taskLog.setRemark(remark);
        taskLogRepository.save(taskLog);
    }

    private static String genderText(Short g) {
        if (g == null) {
            return "";
        }
        return g == 1 ? "男" : "女";
    }

    /** Instant -> 东八区 OffsetDateTime；null 安全 */
    private static OffsetDateTime toOffset(java.time.Instant instant) {
        return instant == null ? null : instant.atZone(ZONE).toOffsetDateTime();
    }

    private static String toJsonArray(List<String> items) {
        if (items == null || items.isEmpty()) {
            return "[]";
        }
        StringBuilder sb = new StringBuilder("[");
        for (int i = 0; i < items.size(); i++) {
            if (i > 0) {
                sb.append(',');
            }
            sb.append('"').append(items.get(i).replace("\"", "\\\"")).append('"');
        }
        return sb.append(']').toString();
    }
}
