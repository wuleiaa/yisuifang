package com.hospital.followup.repository;

import com.hospital.followup.domain.Staff;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface StaffRepository extends JpaRepository<Staff, Long> {

    Optional<Staff> findByStaffNoAndDeletedAtIsNull(String staffNo);

    List<Staff> findByDeptIdAndStatusAndDeletedAtIsNull(Long deptId, Short status);
}

