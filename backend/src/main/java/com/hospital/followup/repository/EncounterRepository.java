package com.hospital.followup.repository;

import com.hospital.followup.domain.Encounter;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface EncounterRepository extends JpaRepository<Encounter, Long> {

    Optional<Encounter> findByInpatientNoAndDeletedAtIsNull(String inpatientNo);

    /** 某患者的全部住院记录，按出院日期倒序 */
    List<Encounter> findByPatientIdAndDeletedAtIsNullOrderByDischargeDateDesc(Long patientId);
}

