package com.hospital.followup.repository;

import com.hospital.followup.domain.FollowupPlan;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface FollowupPlanRepository extends JpaRepository<FollowupPlan, Long> {

    List<FollowupPlan> findByPatientIdAndDeletedAtIsNullOrderByIdAsc(Long patientId);

    List<FollowupPlan> findByEncounterIdAndDeletedAtIsNull(Long encounterId);
}

