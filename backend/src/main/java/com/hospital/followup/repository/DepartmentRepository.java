package com.hospital.followup.repository;

import com.hospital.followup.domain.Department;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface DepartmentRepository extends JpaRepository<Department, Long> {

    Optional<Department> findByCodeAndDeletedAtIsNull(String code);
}

