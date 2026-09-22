package com.hospital.followup.repository;

import com.hospital.followup.domain.Account;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface AccountRepository extends JpaRepository<Account, Long> {

    Optional<Account> findByLoginHashAndDeletedAtIsNull(String loginHash);

    Optional<Account> findByStaffIdAndDeletedAtIsNull(Long staffId);

    Optional<Account> findByPatientIdAndDeletedAtIsNull(Long patientId);
}
