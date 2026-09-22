package com.hospital.followup.repository;

import com.hospital.followup.domain.MedicalProcedure;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface MedicalProcedureRepository extends JpaRepository<MedicalProcedure, Long> {

    List<MedicalProcedure> findByEncounterIdAndDeletedAtIsNullOrderByProcedureDateDesc(Long encounterId);

    List<MedicalProcedure> findByPatientIdAndDeletedAtIsNullOrderByProcedureDateDesc(Long patientId);
}

