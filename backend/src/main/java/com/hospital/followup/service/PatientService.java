package com.hospital.followup.service;

import com.hospital.followup.common.BusinessException;
import com.hospital.followup.common.ErrorCode;
import com.hospital.followup.domain.Encounter;
import com.hospital.followup.domain.FollowupPlan;
import com.hospital.followup.domain.FollowupTask;
import com.hospital.followup.domain.Patient;
import com.hospital.followup.dto.PatientDtos;
import com.hospital.followup.repository.EncounterRepository;
import com.hospital.followup.repository.FollowupPlanRepository;
import com.hospital.followup.repository.FollowupTaskRepository;
import com.hospital.followup.repository.PatientRepository;
import com.hospital.followup.security.CurrentUser;
import com.hospital.followup.security.RlsSession;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

/**
 * 患者服务。
 *
 * 列表接口只返回脱敏手机号（phone_mask），
 * 完整号码必须走单独的接口并做二次验证 + 审计。
 */
@Service
public class PatientService {

    private final PatientRepository patientRepository;
    private final EncounterRepository encounterRepository;
    private final FollowupPlanRepository planRepository;
    private final FollowupTaskRepository taskRepository;
    private final RlsSession rlsSession;

    public PatientService(PatientRepository patientRepository,
                          EncounterRepository encounterRepository,
                          FollowupPlanRepository planRepository,
                          FollowupTaskRepository taskRepository,
                          RlsSession rlsSession) {
        this.patientRepository = patientRepository;
        this.encounterRepository = encounterRepository;
        this.planRepository = planRepository;
        this.taskRepository = taskRepository;
        this.rlsSession = rlsSession;
    }

    @Transactional(readOnly = true)
    public List<PatientDtos.PatientItem> list(String keyword, int limit) {
        rlsSession.apply();
        Long deptId = CurrentUser.deptId();
        String kw = (keyword == null || keyword.isBlank()) ? null : keyword.trim();

        List<PatientRepository.PatientRow> rows =
                patientRepository.search(deptId, kw, Math.min(Math.max(limit, 1), 100));

        List<PatientDtos.PatientItem> out = new ArrayList<>(rows.size());
        LocalDate today = LocalDate.now();

        for (PatientRepository.PatientRow r : rows) {
            List<FollowupTask> tasks =
                    taskRepository.findByPatientIdAndDeletedAtIsNullOrderByDueDateDesc(r.getId());
            int pending = 0;
            int overdue = 0;
            for (FollowupTask t : tasks) {
                if ("PENDING".equals(t.getStatus()) || "DOING".equals(t.getStatus())) {
                    pending++;
                    if (t.getDueDate() != null && t.getDueDate().isBefore(today)) {
                        overdue++;
                    }
                }
            }
            out.add(new PatientDtos.PatientItem(
                    r.getId(), r.getName(), genderText(r.getGender()), r.getAge(),
                    r.getPhoneMask(), r.getMedicalRecordNo(), r.getStatus(),
                    pending, overdue));
        }
        return out;
    }

    /** 患者详情：含多次住院历史 + 并行随访路径时间轴 */
    @Transactional(readOnly = true)
    public PatientDtos.PatientDetail detail(Long patientId) {
        rlsSession.apply();

        Patient p = patientRepository.findByIdAndDeletedAtIsNull(patientId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "患者不存在或您无权查看"));

        List<Encounter> encounters =
                encounterRepository.findByPatientIdAndDeletedAtIsNullOrderByDischargeDateDesc(patientId);

        List<PatientDtos.EncounterItem> encItems = encounters.stream()
                .map(e -> new PatientDtos.EncounterItem(
                        e.getId(), e.getInpatientNo(), e.getAdmitDate(), e.getDischargeDate(),
                        e.getStayDays() != null ? e.getStayDays()
                                : (e.getAdmitDate() != null && e.getDischargeDate() != null
                                   ? (int) (e.getDischargeDate().toEpochDay() - e.getAdmitDate().toEpochDay())
                                   : null),
                        e.getDischargeSummary()))
                .toList();

        List<FollowupPlan> plans = planRepository.findByPatientIdAndDeletedAtIsNullOrderByIdAsc(patientId);
        LocalDate today = LocalDate.now();
        List<PatientDtos.PathwayView> pathways = new ArrayList<>(plans.size());

        for (FollowupPlan pl : plans) {
            List<FollowupTask> tasks =
                    taskRepository.findByPlanIdAndDeletedAtIsNull(pl.getId());
            tasks.sort((a, b) -> {
                if (a.getDueDate() == null) {
                    return 1;
                }
                if (b.getDueDate() == null) {
                    return -1;
                }
                return a.getDueDate().compareTo(b.getDueDate());
            });

            List<PatientDtos.PathwayStep> steps = new ArrayList<>(tasks.size());
            for (FollowupTask t : tasks) {
                int od = (t.getDueDate() != null && t.getDueDate().isBefore(today)
                          && !"DONE".equals(t.getStatus()))
                        ? (int) (today.toEpochDay() - t.getDueDate().toEpochDay()) : 0;
                steps.add(new PatientDtos.PathwayStep(
                        t.getId(), t.getTitle(), t.getDueDate(), t.getStatus(),
                        Boolean.TRUE.equals(t.getIsMandatory()), od, t.getTaskType()));
            }

            pathways.add(new PatientDtos.PathwayView(
                    pl.getId(), pl.getPathwayLabel(), pl.getStatus(),
                    pl.getAnchorProcedureAt(), pl.getAnchorDischargeDate(), steps));
        }

        return new PatientDtos.PatientDetail(
                p.getId(), p.getName(), genderText(p.getGender()), p.getAge(),
                p.getPhoneMask(), p.getMedicalRecordNo(), p.getAddress(), p.getRemark(),
                List.of(),
                encItems, pathways);
    }

    private static String genderText(Short g) {
        if (g == null) {
            return "";
        }
        return g == 1 ? "男" : "女";
    }
}

