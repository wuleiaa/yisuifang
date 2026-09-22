package com.hospital.followup.repository;

import com.hospital.followup.domain.CareTeamMember;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface CareTeamMemberRepository extends JpaRepository<CareTeamMember, Long> {

    List<CareTeamMember> findByStaffId(Long staffId);
}
