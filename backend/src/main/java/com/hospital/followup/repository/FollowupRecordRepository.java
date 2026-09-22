package com.hospital.followup.repository;

import com.hospital.followup.domain.FollowupRecord;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface FollowupRecordRepository extends JpaRepository<FollowupRecord, Long> {

    List<FollowupRecord> findByPatientIdAndDeletedAtIsNullOrderByExecutedAtDesc(Long patientId);

    List<FollowupRecord> findByTaskIdAndDeletedAtIsNull(Long taskId);
}

