package com.hospital.followup.service;

import com.hospital.followup.common.BusinessException;
import com.hospital.followup.common.ErrorCode;
import com.hospital.followup.dto.PortalDtos;
import com.hospital.followup.repository.PatientRepository;
import com.hospital.followup.security.CurrentUser;
import com.hospital.followup.security.RlsSession;
import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Timestamp;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * 患者端只读查询 + 问卷提交。
 *
 * 【两道防线，缺一不可】
 *   第一道：所有 SQL 都显式带上 patient_id = 当前登录患者，防止应用层写错条件；
 *   第二道：RlsSession.applyForPatient() 设置会话变量，数据库策略兜底。
 * 只做第二道，一旦有人写出不带条件的 SQL 就会越权；只做第一道，
 * 一旦有人漏写一个 where 就全泄露。所以两个都做。
 */
@Service
public class PortalService {

    private static final ZoneId ZONE = ZoneId.of("Asia/Shanghai");

    private final PatientRepository patientRepository;
    private final RlsSession rlsSession;

    @PersistenceContext
    private EntityManager em;

    public PortalService(PatientRepository patientRepository, RlsSession rlsSession) {
        this.patientRepository = patientRepository;
        this.rlsSession = rlsSession;
    }

    private Long currentPatientId() {
        Long pid = CurrentUser.patientId();
        if (pid == null) {
            throw new BusinessException(ErrorCode.UNAUTHORIZED, "请先登录");
        }
        return pid;
    }

    @Transactional(readOnly = true)
    public PortalDtos.PatientProfile me() {
        Long pid = currentPatientId();
        rlsSession.applyForPatient(pid);
        return patientRepository.findByIdAndDeletedAtIsNull(pid)
                .map(PortalAuthService::toProfile)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "患者信息不存在"));
    }

    /** 随访时间轴：我的每一次随访安排与结果 */
    @Transactional(readOnly = true)
    public PortalDtos.Timeline timeline() {
        Long pid = currentPatientId();
        rlsSession.applyForPatient(pid);

        var profile = patientRepository.findByIdAndDeletedAtIsNull(pid)
                .map(PortalAuthService::toProfile)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "患者信息不存在"));

        @SuppressWarnings("unchecked")
        List<Object[]> rows = em.createNativeQuery("""
                select t.id,
                       t.title,
                       t.task_type,
                       t.status,
                       t.due_date,
                       coalesce(t.is_mandatory, false),
                       coalesce(t.overdue_days, 0),
                       pl.pathway_label,
                       r.conclusion,
                       r.executed_at
                  from followup_task t
                  left join followup_plan pl on pl.id = t.plan_id
                  left join followup_record r on r.task_id = t.id and r.deleted_at is null
                 where t.patient_id = :pid
                   and t.deleted_at is null
                 order by t.due_date asc nulls last, t.id asc
                """).setParameter("pid", pid).getResultList();

        List<PortalDtos.TimelineItem> items = new ArrayList<>(rows.size());
        int done = 0, pending = 0, overdue = 0;
        for (Object[] r : rows) {
            String status = (String) r[3];
            int overdueDays = ((Number) r[6]).intValue();
            if ("DONE".equals(status)) {
                done++;
            } else if (!"CANCELLED".equals(status)) {
                pending++;
                if (overdueDays > 0) {
                    overdue++;
                }
            }
            items.add(new PortalDtos.TimelineItem(
                    ((Number) r[0]).longValue(),
                    (String) r[1],
                    (String) r[2],
                    taskTypeText((String) r[2]),
                    status,
                    statusText(status),
                    toLocalDate(r[4]),
                    Boolean.TRUE.equals(r[5]),
                    overdueDays,
                    (String) r[7],
                    (String) r[8],
                    toOffsetDateTime(r[9])));
        }
        return new PortalDtos.Timeline(profile, items, done, pending, overdue);
    }

    /** 我的病理报告：只返回已发布的 */
    @Transactional(readOnly = true)
    public List<PortalDtos.ReportItem> reports() {
        Long pid = currentPatientId();
        rlsSession.applyForPatient(pid);

        @SuppressWarnings("unchecked")
        List<Object[]> rows = em.createNativeQuery("""
                select r.id, r.report_no, r.specimen_site, r.report_date,
                       r.risk_level, r.conclusion, r.published_at,
                       i.plain_text, i.followup_advice, i.recheck_months
                  from pathology_report r
                  left join pathology_interpretation i on i.report_id = r.id
                 where r.patient_id = :pid
                   and r.deleted_at is null
                   and r.status = 'PUBLISHED'
                 order by r.report_date desc nulls last, r.id desc
                """).setParameter("pid", pid).getResultList();

        List<PortalDtos.ReportItem> list = new ArrayList<>(rows.size());
        for (Object[] r : rows) {
            String risk = (String) r[4];
            list.add(new PortalDtos.ReportItem(
                    ((Number) r[0]).longValue(),
                    (String) r[1],
                    (String) r[2],
                    toLocalDate(r[3]),
                    risk,
                    riskText(risk),
                    (String) r[5],
                    (String) r[7],
                    (String) r[8],
                    r[9] == null ? null : ((Number) r[9]).intValue(),
                    toOffsetDateTime(r[6])));
        }
        return list;
    }

    /** 任务详情（患者视角） */
    @Transactional(readOnly = true)
    public PortalDtos.TimelineItem taskDetail(Long taskId) {
        PortalDtos.Timeline timeline = timeline();
        return timeline.items().stream()
                .filter(i -> i.taskId().equals(taskId))
                .findFirst()
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "未找到该随访安排"));
    }

    /**
     * 提交随访问卷。
     *
     * 只允许对自己的任务提交；同一个任务重复提交会覆盖上一次
     * （幂等，符合铁律 5：可重复执行不产生重复数据）。
     */
    @Transactional
    public PortalDtos.SubmitResult submitQuestionnaire(Long taskId, Map<String, Object> answers) {
        Long pid = currentPatientId();
        rlsSession.applyForPatient(pid);

        Number count = (Number) em.createNativeQuery("""
                select count(*) from followup_task
                 where id = :tid and patient_id = :pid and deleted_at is null
                """).setParameter("tid", taskId).setParameter("pid", pid).getSingleResult();
        if (count == null || count.longValue() == 0) {
            throw new BusinessException(ErrorCode.NOT_FOUND, "未找到该随访安排");
        }

        String json = toJson(answers);

        em.createNativeQuery("""
                delete from questionnaire_answer where task_id = :tid and patient_id = :pid
                """).setParameter("tid", taskId).setParameter("pid", pid).executeUpdate();

        em.createNativeQuery("""
                insert into questionnaire_answer (questionnaire_id, patient_id, task_id, answers, submitted_at)
                values (:qid, :pid, :tid, cast(:answers as jsonb), now())
                """)
                .setParameter("qid", defaultQuestionnaireId())
                .setParameter("pid", pid)
                .setParameter("tid", taskId)
                .setParameter("answers", json)
                .executeUpdate();

        return new PortalDtos.SubmitResult(taskId, true, "问卷已提交，感谢您的配合");
    }

    private Object defaultQuestionnaireId() {
        Object id = em.createNativeQuery(
                        "select id from questionnaire where code = 'POST_OP_BASIC' and status = 'ACTIVE' limit 1")
                .getResultList().stream().findFirst().orElse(null);
        if (id == null) {
            throw new BusinessException(ErrorCode.NOT_FOUND, "随访问卷未配置");
        }
        return id;
    }

    /** 当前使用的随访问卷（题目从库里读） */
    @Transactional(readOnly = true)
    public PortalDtos.Questionnaire questionnaire() {
        Long pid = currentPatientId();
        rlsSession.applyForPatient(pid);

        @SuppressWarnings("unchecked")
        List<Object[]> head = em.createNativeQuery("""
                select id, code, name from questionnaire
                 where code = 'POST_OP_BASIC' and status = 'ACTIVE' limit 1
                """).getResultList();
        if (head.isEmpty()) {
            throw new BusinessException(ErrorCode.NOT_FOUND, "随访问卷未配置");
        }
        Long qid = ((Number) head.get(0)[0]).longValue();

        @SuppressWarnings("unchecked")
        List<Object[]> rows = em.createNativeQuery("""
                select seq_no, question_type, title, options, is_required
                  from questionnaire_question
                 where questionnaire_id = :qid
                 order by seq_no
                """).setParameter("qid", qid).getResultList();

        List<PortalDtos.QuestionItem> questions = new ArrayList<>(rows.size());
        for (Object[] r : rows) {
            questions.add(new PortalDtos.QuestionItem(
                    ((Number) r[0]).intValue(),
                    (String) r[1],
                    (String) r[2],
                    parseOptions((String) r[3]),
                    Boolean.TRUE.equals(r[4])));
        }
        return new PortalDtos.Questionnaire((String) head.get(0)[1], (String) head.get(0)[2], questions);
    }

    /** options 是 jsonb 数组，这里做一次极简解析（元素是短字符串，不引入 JSON 库） */
    private List<String> parseOptions(String json) {
        if (json == null || json.isBlank() || "null".equals(json)) {
            return List.of();
        }
        String body = json.trim();
        if (body.startsWith("[")) {
            body = body.substring(1);
        }
        if (body.endsWith("]")) {
            body = body.substring(0, body.length() - 1);
        }
        List<String> out = new ArrayList<>();
        for (String part : body.split(",")) {
            String v = part.trim();
            if (v.startsWith("\"")) {
                v = v.substring(1);
            }
            if (v.endsWith("\"")) {
                v = v.substring(0, v.length() - 1);
            }
            if (!v.isEmpty()) {
                out.add(v);
            }
        }
        return out;
    }

    /** 极简 JSON 序列化：问卷答案只有字符串与数字，不引入额外依赖 */
    private String toJson(Map<String, Object> answers) {
        StringBuilder sb = new StringBuilder("{");
        boolean first = true;
        for (Map.Entry<String, Object> e : answers.entrySet()) {
            if (!first) {
                sb.append(',');
            }
            first = false;
            sb.append('"').append(e.getKey().replace("\"", "'")).append("\":");
            Object v = e.getValue();
            if (v == null) {
                sb.append("null");
            } else if (v instanceof Number || v instanceof Boolean) {
                sb.append(v);
            } else {
                sb.append('"').append(String.valueOf(v).replace("\\", "/").replace("\"", "'")).append('"');
            }
        }
        return sb.append('}').toString();
    }

    private static LocalDate toLocalDate(Object o) {
        if (o == null) {
            return null;
        }
        if (o instanceof LocalDate ld) {
            return ld;
        }
        if (o instanceof java.sql.Date d) {
            return d.toLocalDate();
        }
        return LocalDate.parse(o.toString());
    }

    private static OffsetDateTime toOffsetDateTime(Object o) {
        if (o == null) {
            return null;
        }
        if (o instanceof OffsetDateTime odt) {
            return odt;
        }
        if (o instanceof Timestamp ts) {
            return ts.toInstant().atZone(ZONE).toOffsetDateTime();
        }
        if (o instanceof java.time.Instant i) {
            return i.atZone(ZONE).toOffsetDateTime();
        }
        return null;
    }

    private static String taskTypeText(String type) {
        if (type == null) {
            return "随访";
        }
        return switch (type) {
            case "PHONE" -> "电话回访";
            case "OUTPATIENT" -> "门诊复查";
            case "SYSTEM_NOTIFY" -> "报告通知";
            case "SMS" -> "短信提醒";
            case "WECHAT" -> "微信提醒";
            default -> "随访";
        };
    }

    private static String statusText(String status) {
        if (status == null) {
            return "";
        }
        return switch (status) {
            case "DONE" -> "已完成";
            case "DOING" -> "进行中";
            case "CANCELLED" -> "已取消";
            default -> "待进行";
        };
    }

    private static String riskText(String risk) {
        if (risk == null) {
            return "";
        }
        return switch (risk) {
            case "HIGH" -> "需尽快复诊";
            case "ATTENTION" -> "需按期复诊";
            default -> "常规";
        };
    }
}
