package com.hospital.followup.repository;

import com.hospital.followup.domain.CareTeam;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface CareTeamRepository extends JpaRepository<CareTeam, Long> {

    Optional<CareTeam> findByCodeAndDeletedAtIsNull(String code);

    List<CareTeam> findByDeptIdAndStatusAndDeletedAtIsNull(Long deptId, Short status);
}
