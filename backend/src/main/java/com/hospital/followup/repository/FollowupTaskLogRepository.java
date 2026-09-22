package com.hospital.followup.repository;

import com.hospital.followup.domain.FollowupTaskLog;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface FollowupTaskLogRepository extends JpaRepository<FollowupTaskLog, Long> {

    List<FollowupTaskLog> findByTaskIdOrderByActionAtDesc(Long taskId);
}
