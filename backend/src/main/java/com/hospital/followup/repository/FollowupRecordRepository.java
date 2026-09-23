package com.hospital.followup.repository;

import com.hospital.followup.domain.FollowupRecord;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;

public interface FollowupRecordRepository extends JpaRepository<FollowupRecord, Long> {

    List<FollowupRecord> findByPatientIdAndDeletedAtIsNullOrderByExecutedAtDesc(Long patientId);

    List<FollowupRecord> findByTaskIdAndDeletedAtIsNull(Long taskId);

    /**
     * 历史回访（C9）：同一患者以前的记录，新的在前。
     *
     * 在数据库侧就带上 limit（Pageable），避免老患者几十条历史全捞进内存。
     * 不排除当前任务自己的记录：待办任务本来就没有记录（护士看到的最新一条
     * 就是上次的内容），而重复打开一条已完成任务时，能看到自己刚写的那条
     * 更符合直觉——排除掉反而像"我刚写的东西丢了"。
     */
    @Query("""
            select r from FollowupRecord r
             where r.patientId = :patientId
               and r.deletedAt is null
             order by r.executedAt desc
            """)
    List<FollowupRecord> findPatientHistory(@Param("patientId") Long patientId,
                                            Pageable pageable);
}
