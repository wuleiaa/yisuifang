package com.hospital.followup.repository;

import com.hospital.followup.domain.Patient;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface PatientRepository extends JpaRepository<Patient, Long> {

    /** 按手机号哈希精确查找（走索引，不解密） */
    List<Patient> findByPhoneHashAndDeletedAtIsNull(String phoneHash);

    /** 按病案号查找（患者终身唯一，用于识别同一患者的多次住院） */
    Optional<Patient> findByMedicalRecordNoAndDeletedAtIsNull(String medicalRecordNo);

    Optional<Patient> findByIdAndDeletedAtIsNull(Long id);

    /**
     * 姓名 / 手机号脱敏值 模糊搜索。
     * 注意：这里加了 dept_id 过滤和 LIMIT，避免大表全扫描。
     */
    @Query(value = """
            SELECT p.id AS "id", p.name AS "name", p.gender AS "gender", p.age AS "age",
                   p.phone_mask AS "phoneMask", p.medical_record_no AS "medicalRecordNo",
                   p.status AS "status"
            FROM patient p
            WHERE p.deleted_at IS NULL
              AND p.dept_id = :deptId
              AND (:kw IS NULL OR p.name LIKE CONCAT('%', :kw, '%')
                                OR p.phone_mask LIKE CONCAT('%', :kw, '%')
                                OR p.medical_record_no LIKE CONCAT('%', :kw, '%'))
            ORDER BY p.id DESC
            LIMIT :limit
            """, nativeQuery = true)
    List<PatientRow> search(@Param("deptId") Long deptId,
                            @Param("kw") String keyword,
                            @Param("limit") int limit);

    interface PatientRow {
        Long getId();
        String getName();
        Short getGender();
        Integer getAge();
        String getPhoneMask();
        String getMedicalRecordNo();
        String getStatus();
    }
}

