# =============================================================================
#  后端镜像（多阶段构建）
#
#  构建上下文必须是【项目根目录】，因为 pom.xml 里把 ../db/migration 打进了 jar：
#      docker build -f backend/Dockerfile -t followup/app:latest .
#  用 docker compose 时由 compose 文件指定 context。
#
#  为什么分两阶段：编译需要 JDK + Maven（约 700MB），运行只要 JRE（约 200MB）。
#  最终镜像不带编译工具链，攻击面更小、拉取更快。
# =============================================================================

# ---------------------------------------------------------------- 构建阶段
FROM maven:3.9-eclipse-temurin-21 AS build

WORKDIR /src

# 先只拷 pom，把依赖拉下来并缓存；源码改动时不必重下依赖
COPY backend/pom.xml  /src/backend/pom.xml
COPY backend/settings.xml /src/backend/settings.xml
RUN mvn -s /src/backend/settings.xml -f /src/backend/pom.xml -B -DskipTests dependency:go-offline

# 再拷源码与建表脚本（pom 里引用了 ../db/migration）
COPY backend/src /src/backend/src
COPY db          /src/db

RUN mvn -s /src/backend/settings.xml -f /src/backend/pom.xml -B -DskipTests clean package

# ---------------------------------------------------------------- 运行阶段
FROM eclipse-temurin:21-jre-alpine

# 时区必须是东八区：随访时间、逾期天数判定全依赖它
RUN apk add --no-cache tzdata curl \
 && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
 && echo "Asia/Shanghai" > /etc/timezone \
 && addgroup -S app && adduser -S app -G app

WORKDIR /app
COPY --from=build /src/backend/target/followup.jar /app/app.jar

# 不用 root 跑应用
USER app

EXPOSE 8080

# 内存按低配服务器收紧；生产可在这里按机器规格调整
ENV JAVA_OPTS="-Xms256m -Xmx512m -XX:MaxMetaspaceSize=192m -Duser.timezone=Asia/Shanghai -Dfile.encoding=UTF-8"

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8080/actuator/health || exit 1

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
