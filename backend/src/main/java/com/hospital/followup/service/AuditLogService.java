package com.hospital.followup.service;

import com.hospital.followup.common.ClientInfo;
import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 审计日志的唯一写入口。
 *
 * 【为什么必须独立事务（REQUIRES_NEW）】
 *  审计最常见的用途恰恰是记录"失败的操作"：有人拿错密码试改密、
 *  有人越权想停用别人账号。这些场景主事务最后一定会回滚，
 *  如果审计写在主事务里，它会被一起回滚掉——"最该留下的痕迹恰好留不下来"。
 *  所以这里固定用独立事务：主事务成不成功，审计都要落地。
 *
 * 【为什么只有一个入口】
 *  以前改密、管理后台、患者端各写一份 insert，各自的字段与事务行为都不一样，
 *  结果就是"登录日志没有 IP、改密失败没有记录"。集中到一处以后，
 *  IP、User-Agent、独立事务这三件事对全部审计自动生效。
 */
@Service
public class AuditLogService {

    private static final Logger log = LoggerFactory.getLogger(AuditLogService.class);

    private final TransactionTemplate txTemplate;

    @PersistenceContext
    private EntityManager em;

    public AuditLogService(PlatformTransactionManager txManager) {
        TransactionTemplate t = new TransactionTemplate(txManager);
        t.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
        this.txTemplate = t;
    }

    /**
     * 写一条审计日志。
     *
     * @param accountId  操作者账号 id，可为 null
     * @param staffId    操作者员工 id，可为 null
     * @param patientId  相关患者 id，可为 null
     * @param action     动作名，如 STAFF_STATUS / STAFF_CHANGE_PASSWORD
     * @param result     SUCCESS / FAIL
     * @param detailJson 额外说明，格式化成 jsonb；不需要就传 null
     */
    public void record(Long accountId, Long staffId, Long patientId, String action,
                       String resourceType, String resourceId, String result, String detailJson) {
        try {
            txTemplate.executeWithoutResult(status -> em.createNativeQuery("""
                            insert into audit_log (account_id, staff_id, patient_id, action,
                                                   resource_type, resource_id, result, detail,
                                                   ip, user_agent)
                            values (cast(:aid as bigint), cast(:sid as bigint), cast(:pid as bigint),
                                    :action, :rtype, cast(:rid as text), :result,
                                    cast(:detail as jsonb), cast(:ip as text), cast(:ua as text))
                            """)
                    .setParameter("aid", accountId)
                    .setParameter("sid", staffId)
                    .setParameter("pid", patientId)
                    .setParameter("action", action)
                    .setParameter("rtype", resourceType)
                    .setParameter("rid", resourceId)
                    .setParameter("result", result)
                    .setParameter("detail", detailJson)
                    .setParameter("ip", ClientInfo.ip())
                    .setParameter("ua", ClientInfo.userAgent())
                    .executeUpdate());
        } catch (Exception e) {
            // 审计失败不能影响主流程，但必须自己去日志里留痕
            log.error("写审计日志失败 action={} resourceId={}", action, resourceId, e);
        }
    }

    /** 便捷写法：detail 只有一个说明文字 */
    public void record(Long accountId, Long staffId, String action, String resourceType,
                       String resourceId, String result, String note) {
        record(accountId, staffId, null, action, resourceType, resourceId, result, noteJson(note));
    }

    /** 把说明文字包成 jsonb，并转义引号，避免拼出非法 JSON */
    public static String noteJson(String note) {
        if (note == null) {
            return null;
        }
        return "{\"note\":\"" + note.replace("\\", "").replace("\"", "'") + "\"}";
    }
}
