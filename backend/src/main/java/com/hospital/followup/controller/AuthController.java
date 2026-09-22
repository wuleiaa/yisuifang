package com.hospital.followup.controller;

import com.hospital.followup.common.ApiResponse;
import com.hospital.followup.crypto.CryptoService;
import com.hospital.followup.dto.AuthDtos;
import com.hospital.followup.service.AuthService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api/auth")
public class AuthController {

    private final AuthService authService;
    private final CryptoService cryptoService;

    public AuthController(AuthService authService, CryptoService cryptoService) {
        this.authService = authService;
        this.cryptoService = cryptoService;
    }

    @PostMapping("/login")
    public ApiResponse<AuthDtos.LoginResponse> login(@Valid @RequestBody AuthDtos.LoginRequest req) {
        return ApiResponse.ok(authService.login(req));
    }

    @GetMapping("/me")
    public ApiResponse<AuthDtos.StaffProfile> me() {
        return ApiResponse.ok(authService.currentProfile());
    }

    /** 加密子系统自检：验证密钥装载正确、加解密可往返、哈希长度正确 */
    @GetMapping("/crypto-check")
    public ApiResponse<Map<String, Object>> cryptoCheck() {
        boolean ok = cryptoService.selfCheck();
        String sample = "13812345678";
        return ApiResponse.ok(Map.of(
                "ok", ok,
                "masked", cryptoService.maskPhone(sample),
                "hashLength", cryptoService.hash(sample).length(),
                "message", ok ? "加密子系统正常" : "加密子系统异常，请检查密钥配置"));
    }

    /**
     * 修改自己的密码。
     * 需要正确的原密码；新密码至少 8 位且含字母和数字。
     */
    @PostMapping("/change-password")
    public ApiResponse<Void> changePassword(@Valid @RequestBody AuthDtos.ChangePasswordRequest req) {
        authService.changePassword(req);
        return ApiResponse.ok();
    }
}
