# syntax=docker/dockerfile:1
# 사내 메신저 백엔드 이미지 (Red Hat UBI 9 / OpenJDK 21)
#
# 폐쇄망에서는 아래 ARG 로 사내 레지스트리 / Nexus 를 지정한다.
#   --build-arg BUILDER_IMAGE=registry.corp.local/ubi9/openjdk-21:latest
#   --build-arg RUNTIME_IMAGE=registry.corp.local/ubi9/openjdk-21-runtime:latest
#   --build-arg MAVEN_MIRROR_URL=https://nexus.corp.local/repository/maven-public/
ARG BUILDER_IMAGE=registry.access.redhat.com/ubi9/openjdk-21:latest
ARG RUNTIME_IMAGE=registry.access.redhat.com/ubi9/openjdk-21-runtime:latest

FROM ${BUILDER_IMAGE} AS build
ARG MAVEN_MIRROR_URL=
USER 185
WORKDIR /home/default/build

RUN mkdir -p /home/default/.m2 && \
    if [ -n "${MAVEN_MIRROR_URL}" ]; then \
      printf '<settings><mirrors><mirror><id>internal</id><mirrorOf>*</mirrorOf><url>%s</url></mirror></mirrors></settings>\n' \
        "${MAVEN_MIRROR_URL}" > /home/default/.m2/settings.xml; \
    fi

COPY --chown=185:0 pom.xml .
RUN mvn -B -q dependency:go-offline || true
COPY --chown=185:0 src ./src
RUN mvn -B -DskipTests package

FROM ${RUNTIME_IMAGE}
LABEL name="messenger-backend" \
      summary="사내 메신저 백엔드 (Spring Boot)"

COPY --from=build /home/default/build/target/messenger.jar /deployments/messenger.jar

ENV JAVA_OPTS="-XX:MaxRAMPercentage=75 -XX:+ExitOnOutOfMemoryError -Djava.security.egd=file:/dev/./urandom" \
    FILE_STORAGE_PATH=/data/files \
    TZ=Asia/Seoul

# OpenShift 는 임의 UID(그룹 0)로 실행하므로 root 그룹에 쓰기 권한 부여
USER 0
RUN mkdir -p /data/files && chgrp -R 0 /data && chmod -R g=u /data
USER 185

EXPOSE 8080
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /deployments/messenger.jar"]
