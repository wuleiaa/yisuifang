# 医院回访管理系统 —— 项目工作区

> 最后更新：2026-09-18

## 当前阶段

**开发阶段 · 阶段一（医护端与患者端两端已打通，管理后台进行中）**

11 轮设计论证全部完成。后端可运行版本、医护端 H5、患者端 H5 都已实测通过，
四个自动化套件（两套接口 + 两套真实浏览器走查）合计 50 项检查全绿。

| 部分 | 状态 |
|---|---|
| 设计文档（第 1–11 轮 + 话术库） | 已交付 |
| 数据库结构与迁移（43 张表） | 已实测通过 |
| 后端 API（医护 9 个 + 患者 8 个 + 管理 7 个） | 已实测通过 |
| 医护端 H5（6 个页面） | 已可用，已联调 + 浏览器走查通过 |
| 患者端 H5（5 个页面） | 已可用，已联调 + 浏览器走查通过 |
| 管理后台（账号管理 / 登录记录 / 概览） | 已可用，已联调 + 浏览器走查通过 |
| 患者端打包成微信小程序 | **未开始**（接口已按小程序场景设计） |
| 管理后台的模板配置与质控看板 | **未开始** |

界面风格已按"端庄大气、简约"重做（v2）：墨蓝主色、细线 SVG 图标（去 emoji）、
细边框分层，只用真实摄影。方案页见 [prototype/style-v2.html](prototype/style-v2.html)，
照片在 `frontend/public/photos/`（Unsplash，免费商用，已本地化）。

> 中断后想接着干，直接看 [开发进度-断点记录](docs/开发进度-断点记录.md)——
> 里面有当前环境状态、已验证的证据、下一步清单和恢复命令。

**已确认的方向（2026-09-17）**

1. 两端并行开发（医护端 + 患者端）；
2. 管理后台纳入本轮范围；
3. 第一版随访路径先用预置的 5 条消化内科路径，模板管理后台后续接上。

## 快速启动

五条命令，按顺序执行（每个命令一个窗口）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\db-start.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\backend-run.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\frontend-run.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\patient-run.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\admin-run.ps1
```

| 服务 | 地址 |
|---|---|
| 医护端界面 | <http://127.0.0.1:5173> |
| 患者端界面 | <http://127.0.0.1:5174> |
| 管理后台 | <http://127.0.0.1:5175> |
| 后端接口 | <http://127.0.0.1:8080> |
| 数据库 | `127.0.0.1:55432/followup_dev` |

停服务：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\backend-stop.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\db-stop.ps1
```

## 演示账号

密码统一 `Followup@2026`，**仅在 dev 环境创建**，生产环境不会执行种子脚本。

| 工号 | 姓名 | 角色 | 权限范围 |
|---|---|---|---|
| D0231 | 李医生 | 主治医师（主管医生） | 自己主管的患者 |
| N0455 | 王护士 | 主管护师（主管护士） | 自己主管的患者 |
| N0001 | 张护士长 | 护士长（科室管理者） | 全科室 |
| A0001 | 系统管理员 | 超级管理员（信息科） | 全院账号管理（管理后台） |

> 医护端登录页有"医护登录 / 管理员登录"两个模式；管理员登录成功后进入管理后台。
> 密码一律 BCrypt 哈希存储，**系统里查不到原密码**：新建账号或重置密码时给出一次性密码，
> 本人首次登录后强制修改。

## 自检与测试

```powershell
# 接口联调冒烟测试：认证 / 待办 / 任务详情 / 领取 / 完成 / 患者 / 行级权限 / 审计
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\api-smoke-test.ps1

# 患者端联调冒烟测试：验证码登录 / 时间轴 / 报告可见性 / 越权防护
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\portal-smoke-test.ps1

# 管理后台接口冒烟测试：建号 / 查号 / 重置密码 / 停用启用 / 越权防护
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\admin-smoke-test.ps1

# 重置演示数据（反复测试不会把演示任务消耗光；账号密码不受影响）
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\demo-reset.ps1

# 真实浏览器走查（需要两个前端都在跑，截图输出到 output/playwright/）
node tools\ui-check-patient.mjs
node tools\ui-check-staff.mjs
node tools\ui-check-admin.mjs
```

最近一次实测结果（2026-09-17，本机）：

| 项目 | 结果 |
|---|---|
| 医护端接口 / 患者端接口 / 管理后台接口 | 16 / 12 / 20 项，全部通过 |
| 浏览器走查 | 医护端 12 项、患者端 10 项、管理后台 11 项，全部通过 |
| 六套合计 | **81 项检查全绿** |
| 接口延迟 | p50 20 ms / p95 164 ms |
| 行级权限 | 医生 4 条 / 护士 3 条 / 护士长 7 条待办（同一批数据，结果不同） |
| 演示数据 | 3 位患者 / 4 条随访路径 / 10 个任务 |

## 开发工具位置（不占 C 盘）

全部开发工具放在 **D 盘**，C 盘只保留系统本身：

| 组件 | 位置 |
|---|---|
| JDK 21 LTS | `D:\devtools\jdk-21.0.12.1+1` |
| Maven | `D:\devtools\apache-maven-3.9.9` |
| Maven 本地仓库 | `D:\devtools\m2repo` |
| PostgreSQL 16（便携版） | `D:\devtools\pgtool` |

内存占用已按低配机器调低：JVM `-Xmx512m`、PostgreSQL `shared_buffers=64MB` 且
`max_connections=30`、Maven `-Xmx512m`。实测整套开发环境常驻内存约 **800 MB**。

**核心提醒机制遵循"零依赖原则"**：待办列表 + 安卓本地通知 + 开屏强制提醒，
三层完全不依赖任何外部审批，独自开发即可跑通。

## 文档索引

| 轮次 | 主题 | 文件 | 状态 |
|---|---|---|---|
| 第 1 轮 | 业务边界界定、角色模型、合规红线、技术基线 | [第01轮](docs/第01轮-业务边界与技术基线.md) | 完成 |
| 第 2 轮 | 数据规模论证、留存合规、触达能力真相、真实随访路径 | [第02轮](docs/第02轮-数据规模-留存合规-触达能力-真实随访路径.md) | 完成 |
| 第 3 轮 | 病理报告闭环、催办升级链路、多端提醒方案、医护搭档模型 | [第03轮](docs/第03轮-病理闭环-催办升级-多端提醒方案.md) | 完成 |
| 第 4 轮 | 无企业微信的提醒方案、提醒节奏定版、存储重算 | [第04轮](docs/第04轮-提醒机制定版与可行性验证.md) | 完成 |
| 第 5 轮 | 订阅号影响、消化内科五大病种随访路径、记录本字段定稿 | [第05轮](docs/第05轮-消化内科随访路径与字段定稿.md) | 完成 |
| 第 6 轮 | 完整数据模型、加密方案、行级权限、建表 SQL（43 张表） | [第06轮](docs/第06轮-数据模型与建表SQL.md) | 完成 |
| 第 7 轮 | 随访规则引擎详细设计（多路径并行修正 + 幂等） | [第07轮](docs/第07轮-随访规则引擎详细设计.md) | 完成 |
| 第 8 轮 | 界面与交互定稿（原型 v2，覆盖全部主流程） | [第08轮](docs/第08轮-界面与交互定稿.md) | 完成 |
| 第 9 轮 | 部署方案、服务器选购、安装手册与部署检查清单 | [第09轮](docs/第09轮-部署方案与服务器选购.md) | 完成 |
| 第 10 轮 | 测试策略与实测报告（性能 / 压力 / 功能 / 安全） | [第10轮](docs/第10轮-测试策略与实测报告.md) | 完成 |
| 第 11 轮 | 项目计划、里程碑、验收标准，附第一版可运行代码 | [第11轮](docs/第11轮-项目计划与开发启动.md) | 完成 |
| 附件 | 消化内科随访电话话术库（32 条场景话术） | [话术库](docs/附-回访话术库.md) | 待护士长审核 |
| — | **交互原型（可点击，v2）** | [prototype/index.html](prototype/index.html) | 可随时打开 |

## 铁律（贯穿全程，不可协商）

1. 患者与医护账号**不做**开放式自助注册，工作人员账号必须由管理员创建/审核。
2. 病历、诊断、联系方式等敏感数据**不存储于境外服务器**（《人口健康信息管理办法》硬性要求）。
3. 任何涉及患者隐私的读取操作必须留可追溯的审计日志。
4. 数据库结构变更必须通过版本化迁移脚本，禁止手工改线上库。
5. 所有定时/批量任务必须幂等，可重复执行不产生重复数据。
6. 应用连接数据库**必须**使用非超级用户 `app_rw`；超级用户会绕过行级安全策略。

> 第 6 条不是纸面规定：开发"演示数据重置"功能时，`app_rw` 因**没有 TRUNCATE 权限**
> 直接报 `permission denied for table patient`。最终改为按外键顺序 DELETE，
> 而不是给应用放开 TRUNCATE 权限——权限最小化优先于实现方便。

## 目录结构

```
医院回访小程序/
├── README.md                     本文件：项目索引与进度
├── docs/                         各轮设计文档（第 01–11 轮 + 话术库）
├── db/migration/
│   └── V1__init_schema.sql       建表脚本（43 张表，已实测通过）
├── backend/                      Spring Boot 后端（Java 21）
│   ├── pom.xml
│   └── src/main/
│       ├── java/com/hospital/followup/
│       │   ├── bootstrap/        演示数据种子（仅 dev）
│       │   ├── common/           统一响应 / 错误码 / 全局异常
│       │   ├── controller/       Auth / Task / Patient / Dev
│       │   ├── crypto/           AES-256-GCM 加解密与脱敏
│       │   ├── domain/           JPA 实体
│       │   ├── dto/              接口出入参
│       │   ├── repository/       数据访问
│       │   ├── security/         JWT / 行级安全会话变量 / 安全配置
│       │   └── service/          业务逻辑
│       └── resources/            application.yml / application-dev.yml
├── frontend/                     医护端 H5（Vue 3 + Vite）
│   ├── src/views/                登录 / 待办 / 任务详情 / 患者 / 患者详情 / 我的
│   ├── src/api.js                统一接口客户端（含 401 自动跳登录）
│   ├── src/router.js             hash 路由（便于日后打包成 App）
│   ├── vite.config.js            /api 代理到 8080
│   ├── vite.patient.config.js    患者端构建配置（共用同一套依赖）
│   ├── patient/                  患者端 H5（登录 / 随访安排 / 详情+问卷 / 报告 / 我的）
│   ├── vite.admin.config.js      管理后台构建配置
│   └── admin/                    管理后台（概览 / 账号管理 / 登录记录）
├── output/playwright/            浏览器走查截图（自动生成）
├── frontend/public/photos/       真实摄影素材（Unsplash，免费商用，两个前端共用）
├── prototype/
│   └── index.html                可点击的交互原型
├── deploy/                       部署配置（Docker Compose / Nginx / 初始化脚本）
└── tools/                        开发与测试脚本
    ├── dev-env.ps1               环境变量（JDK / Maven / PostgreSQL 路径与端口）
    ├── db-start.ps1 / db-stop.ps1
    ├── backend-run.ps1 / backend-build.ps1 / backend-stop.ps1
    ├── frontend-run.ps1
    ├── patient-run.ps1           启动患者端 H5（5174）
    ├── admin-run.ps1             启动管理后台（5175）
    ├── demo-reset.ps1            一键重置演示数据
    ├── api-smoke-test.ps1        接口联调冒烟测试
    ├── portal-smoke-test.ps1     患者端接口冒烟测试
    ├── admin-smoke-test.ps1      管理后台接口冒烟测试
    ├── ui-check-staff.mjs        医护端真实浏览器走查
    ├── ui-check-patient.mjs      患者端真实浏览器走查
    ├── ui-check-admin.mjs        管理后台真实浏览器走查
    ├── backend-stop.ps1          停后端（mvn 会留下 java 进程占端口）
    ├── sql_lint.py               SQL 语法校验（PostgreSQL 官方解析器）
    ├── db_smoke_test.sql         数据库冒烟测试（闸门 + 行级权限 + 分区）
    └── perf_*.sql                性能基准与执行计划
```

> 脚本一律只用 ASCII 字符：Windows PowerShell 5.1 读取无 BOM 的 `.ps1` 时按 GBK 解码，
> 中文注释会被破坏并导致解析失败。
