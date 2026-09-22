package com.hospital.followup.security;

import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * 数据库行级安全（RLS）会话变量设置。
 *
 * 【重要】本类的 apply() 必须在事务内调用。
 * 原因：这里用的是 set_config(name, value, true) —— 第三个参数 is_local=true，
 * 表示只在当前事务内生效。事务外的调用等于没设置。
 *
 * 各变量含义（与 V1__init_schema.sql 里的策略一一对应）：
 *   app.current_staff_id     当前登录医护 ID
 *   app.current_patient_id   当前登录患者 ID（患者端小程序用）
 *   app.is_manager           是否科室管理者（护士长/主任），可看全科室
 *   app.is_patient_portal    是否患者端请求
 *   app.is_system            是否后台任务（定时器、数据迁移），不受限
 */
@Component
public class RlsSession {

    private static final Logger log = LoggerFactory.getLogger(RlsSession.class);

    @PersistenceContext
    private EntityManager em;

    /**
     * 按当前登录用户设置会话变量。
     *
     * 医护端与患者端共用这一个入口：根据当前身份自动选择，
     * 这样任何 Service 只要调 apply() 就不会把患者错当成医护、
     * 也不会让患者端拿到医护视角的可见范围。
     */
    public void apply() {
        CurrentUser.Principal p = CurrentUser.get();

        if (p != null && p.patientPortal()) {
            applyForPatient(p.patientId());
            return;
        }

        set("app.current_staff_id", p == null || p.staffId() == null ? "" : p.staffId().toString());
        set("app.current_patient_id", "");
        set("app.is_manager", p != null && p.manager() ? "true" : "false");
        set("app.is_patient_portal", "false");
        set("app.is_system", "false");
    }

    /** 患者端请求 */
    public void applyForPatient(Long patientId) {
        set("app.current_staff_id", "");
        set("app.current_patient_id", patientId == null ? "" : patientId.toString());
        set("app.is_manager", "false");
        set("app.is_patient_portal", "true");
        set("app.is_system", "false");
    }

    /** 后台任务（定时提醒、数据迁移）使用，绕过行级限制 */
    public void applyAsSystem() {
        set("app.current_staff_id", "");
        set("app.current_patient_id", "");
        set("app.is_manager", "false");
        set("app.is_patient_portal", "false");
        set("app.is_system", "true");
    }

    private void set(String name, String value) {
        Object applied = em.createNativeQuery("select set_config(:n, :v, true)")
                .setParameter("n", name)
                .setParameter("v", value)
                .getSingleResult();
        if (log.isDebugEnabled()) {
            Object readBack = em.createNativeQuery("select current_setting(:n, true)")
                    .setParameter("n", name)
                    .getSingleResult();
            log.debug("RLS 设置 {}=[{}] 生效值=[{}] 事务激活={}",
                    name, value, readBack, TransactionSynchronizationManager.isActualTransactionActive());
        }
    }
}
