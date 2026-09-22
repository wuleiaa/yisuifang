package com.hospital.followup.repository;

import com.hospital.followup.domain.Diagnosis;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface DiagnosisRepository extends JpaRepository<Diagnosis, Long> {

    List<Diagnosis> findByEncounterIdOrderBySeqNo(Long encounterId);

    List<Diagnosis> findByPatientIdOrderByIdDesc(Long patientId);
}

