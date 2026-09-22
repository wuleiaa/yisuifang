package com.hospital.followup.domain;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;

/** 医护搭档组成员 */
@Entity
@Table(name = "care_team_member")
@Getter
@Setter
public class CareTeamMember {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "team_id", nullable = false)
    private Long teamId;

    @Column(name = "staff_id", nullable = false)
    private Long staffId;

    @Column(name = "member_role", nullable = false)
    private String memberRole;   // DOCTOR / NURSE

    @Column(name = "is_primary", nullable = false)
    private Boolean isPrimary = Boolean.FALSE;
}

