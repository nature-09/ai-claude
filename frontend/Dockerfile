# syntax=docker/dockerfile:1
# 사내 메신저 프론트엔드 이미지 (Red Hat UBI 9 / Node.js 22 빌드 → nginx 1.24 서빙)
#
# 폐쇄망에서는 아래 ARG 로 사내 레지스트리 / Nexus npm 프록시를 지정한다.
#   --build-arg BUILDER_IMAGE=registry.corp.local/ubi9/nodejs-22:latest
#   --build-arg RUNTIME_IMAGE=registry.corp.local/ubi9/nginx-124:latest
#   --build-arg NPM_REGISTRY=https://nexus.corp.local/repository/npm-public/
ARG BUILDER_IMAGE=registry.access.redhat.com/ubi9/nodejs-22:latest
ARG RUNTIME_IMAGE=registry.access.redhat.com/ubi9/nginx-124:latest

FROM ${BUILDER_IMAGE} AS build
ARG NPM_REGISTRY=
USER 1001
WORKDIR /opt/app-root/src
COPY --chown=1001:0 package.json package-lock.json ./
RUN if [ -n "${NPM_REGISTRY}" ]; then npm config set registry "${NPM_REGISTRY}"; fi && \
    npm ci --no-audit --no-fund
COPY --chown=1001:0 . .
RUN npm run build

FROM ${RUNTIME_IMAGE}
LABEL name="messenger-frontend" \
      summary="사내 메신저 웹 클라이언트 (nginx)"

USER 0
COPY nginx/nginx.conf /opt/app-root/etc/messenger/nginx.conf
COPY nginx/backend.conf /opt/app-root/etc/messenger/backend.conf
COPY --from=build /opt/app-root/src/dist /opt/app-root/src
RUN chgrp -R 0 /opt/app-root/src /opt/app-root/etc/messenger && chmod -R g=u /opt/app-root/src /opt/app-root/etc/messenger
USER 1001

EXPOSE 8080
CMD ["nginx", "-c", "/opt/app-root/etc/messenger/nginx.conf", "-g", "daemon off;"]
