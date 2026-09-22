package com.hospital.followup;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * 医院随访管理系统 —— 后端服务入口
 */
@SpringBootApplication
@ConfigurationPropertiesScan
@EnableScheduling
public class FollowupApplication {

    public static void main(String[] args) {
        SpringApplication.run(FollowupApplication.class, args);
    }
}
