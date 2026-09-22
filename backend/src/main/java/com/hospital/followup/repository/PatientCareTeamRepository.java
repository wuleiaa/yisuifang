package com.hospital.followup.repository;

import com.hospital.followup.domain.PatientCareTeam;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface PatientCareTeamRepository extends JpaRepository<PatientCareTeam, Long> {

    Optional<PatientCareTeam> findByEncounterIdAndStatus(Long encounterId, String status);

    List<PatientCareTeam> findByPatientId(Long patientId);
}
