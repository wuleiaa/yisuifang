package com.hospital.followup.controller;

import com.hospital.followup.common.ApiResponse;
import com.hospital.followup.dto.PatientDtos;
import com.hospital.followup.service.PatientService;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/patients")
public class PatientController {

    private final PatientService patientService;

    public PatientController(PatientService patientService) {
        this.patientService = patientService;
    }

    @GetMapping
    public ApiResponse<List<PatientDtos.PatientItem>> list(
            @RequestParam(required = false) String keyword,
            @RequestParam(defaultValue = "50") int limit) {
        return ApiResponse.ok(patientService.list(keyword, limit));
    }

    @GetMapping("/{id}")
    public ApiResponse<PatientDtos.PatientDetail> detail(@PathVariable Long id) {
        return ApiResponse.ok(patientService.detail(id));
    }
}
