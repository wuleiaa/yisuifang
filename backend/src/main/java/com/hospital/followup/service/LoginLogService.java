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
 * 登录日志。
 *
 * 【为什么必须独立事务】登录失败时主事务会回滚，
 * 如果日志写在主事务里，"连续有人用错密码试账号"这件事就一条都不会留下——
 * 而那恰恰是最需要留痕的场景。
 *
 * 登录名只记脱敏值：日志是给人排查问题用的，不是给脱库的人用的。
 * 同时记下来源 IP 与 User-Agent —— 只有"谁、什么时候、从哪来"齐了，
 * 事后才判断得出"这次登录是不是被盗用"，也才看得出"有人在扫号"。
 */
@Service
public class LoginLogService {

    private static final Logger log = LoggerFactory.getLogger(LoginLogService.class);

    private final TransactionTemplate txTemplate;

    @PersistenceContext
    private EntityManager em;

    public LoginLogService(PlatformTransactionManager txManager) {
        TransactionTemplate t = new TransactionTemplate(txManager);
        t.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
        this.txTemplate = t;
    }

    /** 登录名脱敏：D0231 → D0**1 */
    public static String maskLoginName(String name) {
        if (name == null || name.isEmpty()) {
            return null;
        }
        String s = name.trim();
        if (s.length() <= 2) {
            return s.charAt(0) + "**";
        }
        if (s.length() <= 4) {
            return s.charAt(0) + "**" + s.charAt(s.length() - 1);
        }
        return s.substring(0, 2) + "**" + s.substring(s.length() - 1);
    }

    public void record(Long accountId, String loginName, String accountType,
                       String loginType, boolean success, String failReason) {
        try {
            txTemplate.executeWithoutResult(status -> em.createNativeQuery("""
                            insert into login_log
                                (account_id, login_name_masked, account_type, login_type, success,
                                 fail_reason, ip, user_agent)
                            values (:aid, :name, :type, :ltype, :ok, :reason, :ip, :ua)
                            """)
                    .setParameter("aid", accountId)
                    .setParameter("name", maskLoginName(loginName))
                    .setParameter("type", accountType)
                    .setParameter("ltype", loginType)
                    .setParameter("ok", success)
                    .setParameter("reason", failReason)
                    .setParameter("ip", ClientInfo.ip())
                    .setParameter("ua", ClientInfo.userAgent())
                    .executeUpdate());
        } catch (Exception e) {
            log.error("写登录日志失败 loginName={}", maskLoginName(loginName), e);
        }
    }
}
