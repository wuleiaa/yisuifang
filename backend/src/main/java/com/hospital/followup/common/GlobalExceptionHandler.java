package com.hospital.followup.common;

import jakarta.servlet.http.HttpServletRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.BindException;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.http.converter.HttpMessageNotReadableException;

import jakarta.validation.ConstraintViolationException;

/**
 * 全局异常处理。
 *
 * 原则：
 *  1. 业务异常返回明确的错误码，前端可以直接据此提示；
 *  2. 系统异常一律返回"系统繁忙"，不把堆栈/SQL 泄露给前端；
 *  3. 所有异常都记日志，方便排查。
 */
@RestControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    @ExceptionHandler(BusinessException.class)
    public ResponseEntity<ApiResponse<Void>> handleBusiness(BusinessException e, HttpServletRequest req) {
        log.warn("业务异常 [{}] {} -> {}", e.getErrorCode().name(), req.getRequestURI(), e.getMessage());
        HttpStatus status = switch (e.getErrorCode()) {
            case UNAUTHORIZED, TOKEN_EXPIRED -> HttpStatus.UNAUTHORIZED;
            case FORBIDDEN, REAUTH_REQUIRED -> HttpStatus.FORBIDDEN;
            case NOT_FOUND -> HttpStatus.NOT_FOUND;
            case CONFLICT -> HttpStatus.CONFLICT;
            case TOO_MANY_REQUESTS -> HttpStatus.TOO_MANY_REQUESTS;
            default -> HttpStatus.BAD_REQUEST;
        };
        return ResponseEntity.status(status).body(ApiResponse.fail(e.getErrorCode(), e.getMessage()));
    }

    @ExceptionHandler({MethodArgumentNotValidException.class, BindException.class})
    public ResponseEntity<ApiResponse<Void>> handleValidation(Exception e) {
        String msg = ErrorCode.BAD_REQUEST.getDefaultMessage();
        if (e instanceof MethodArgumentNotValidException manv && manv.getBindingResult().getFieldError() != null) {
            msg = manv.getBindingResult().getFieldError().getDefaultMessage();
        } else if (e instanceof BindException be && be.getBindingResult().getFieldError() != null) {
            msg = be.getBindingResult().getFieldError().getDefaultMessage();
        }
        return ResponseEntity.badRequest().body(ApiResponse.fail(ErrorCode.BAD_REQUEST, msg));
    }

    /**
     * 参数类型/格式错误。
     *
     * 【为什么单独处理】故障演练发现 `?days=abc` 会走 "系统异常" 分支返回 500，
     * 而它明明是调用方传错了参数。除了照着日志排查困难，扫描器随便扫一下
     * 就会在日志里刷出大量 ERROR 级堆栈。这类问题应该稳定返回 400。
     */
    @ExceptionHandler({
            MethodArgumentTypeMismatchException.class,
            HttpMessageNotReadableException.class,
            MissingServletRequestParameterException.class,
            ConstraintViolationException.class
    })
    public ResponseEntity<ApiResponse<Void>> handleBadRequest(Exception e, HttpServletRequest req) {
        log.warn("请求参数有误 {} -> {}", req.getRequestURI(), e.getMessage());
        return ResponseEntity.badRequest()
                .body(ApiResponse.fail(ErrorCode.BAD_REQUEST, "请求参数有误，请检查后重试"));
    }

    /** 请求方法不支持：返回 405，而不是 500 */
    @ExceptionHandler(HttpRequestMethodNotSupportedException.class)
    public ResponseEntity<ApiResponse<Void>> handleMethod(HttpRequestMethodNotSupportedException e,
                                                          HttpServletRequest req) {
        log.warn("请求方法不支持 {} {}", req.getMethod(), req.getRequestURI());
        return ResponseEntity.status(HttpStatus.METHOD_NOT_ALLOWED)
                .body(ApiResponse.fail(ErrorCode.BAD_REQUEST, "请求方法不支持"));
    }

    /**
     * 数据库约束冲突（唯一索引、CHECK 约束、触发器 RAISE EXCEPTION）。
     * 这里会带上数据库返回的原因，方便定位（不包含表结构细节）。
     */
    @ExceptionHandler(DataIntegrityViolationException.class)
    public ResponseEntity<ApiResponse<Void>> handleIntegrity(DataIntegrityViolationException e) {
        String cause = e.getMostSpecificCause().getMessage();
        log.warn("数据约束冲突: {}", cause);
        // 触发器里写的中文提示可以直接透出，方便医护理解
        String msg = (cause != null && cause.contains("必须")) ? cause : "数据校验未通过，请检查后重试";
        return ResponseEntity.status(HttpStatus.CONFLICT)
                .body(ApiResponse.fail(ErrorCode.CONFLICT, msg));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ApiResponse<Void>> handleOther(Exception e, HttpServletRequest req) {
        log.error("系统异常 {}", req.getRequestURI(), e);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(ApiResponse.fail(ErrorCode.INTERNAL_ERROR, null));
    }
}
