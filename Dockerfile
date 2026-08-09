# syntax=docker/dockerfile:1.7

ARG BUILD_ENV=git
ARG ALPINE_VERSION=3.23.5
ARG ALPINE_DIGEST=sha256:fd791d74b68913cbb027c6546007b3f0d3bc45125f797758156952bc2d6daf40
ARG RESTY_VERSION=1.31.1.1-2
ARG RESTY_RUNTIME_DIGEST=sha256:f05c593f0afbb916361496a2d21aa22edc5d5e54e15160f88d12b62f3918bf22
ARG LUA_RESTY_HTTP_VERSION=0.17.2
ARG LUA_RESTY_HTTP_COMMIT=183310324026120ab7eaf5dd82b9be90ae63aadf
ARG LUA_LIB_VERSION=v1.0.16
ARG LUA_LIB_COMMIT=35455a64e11368b3df73a381b09c056a3ee77e24
ARG BOUNCER_VERSION=v1.2.1

FROM docker.io/library/alpine:${ALPINE_VERSION}@${ALPINE_DIGEST} AS http
ARG LUA_RESTY_HTTP_VERSION
ARG LUA_RESTY_HTTP_COMMIT
RUN set -eux; \
    apk add --no-cache ca-certificates=20260611-r0 git=2.52.0-r0; \
    git init /sources/lua-resty-http; \
    git -C /sources/lua-resty-http remote add origin https://github.com/ledgetech/lua-resty-http.git; \
    git -C /sources/lua-resty-http fetch --depth=1 origin \
      "refs/tags/v${LUA_RESTY_HTTP_VERSION}:refs/tags/v${LUA_RESTY_HTTP_VERSION}"; \
    git -C /sources/lua-resty-http checkout --detach "v${LUA_RESTY_HTTP_VERSION}"; \
    test "$(git -C /sources/lua-resty-http rev-parse HEAD)" = "${LUA_RESTY_HTTP_COMMIT}"; \
    grep -F "version = \"${LUA_RESTY_HTTP_VERSION}-0\"" \
      "/sources/lua-resty-http/lua-resty-http-${LUA_RESTY_HTTP_VERSION}-0.rockspec"

FROM http AS git
ARG LUA_LIB_VERSION
ARG LUA_LIB_COMMIT
RUN set -eux; \
    git init /sources/lua-cs-bouncer; \
    git -C /sources/lua-cs-bouncer remote add origin https://github.com/crowdsecurity/lua-cs-bouncer.git; \
    git -C /sources/lua-cs-bouncer fetch --depth=1 origin \
      "refs/tags/${LUA_LIB_VERSION}:refs/tags/${LUA_LIB_VERSION}"; \
    git -C /sources/lua-cs-bouncer checkout --detach "${LUA_LIB_VERSION}"; \
    test "$(git -C /sources/lua-cs-bouncer rev-parse HEAD)" = "${LUA_LIB_COMMIT}"

FROM http AS local
COPY lua-cs-bouncer/ /sources/lua-cs-bouncer/

# hadolint ignore=DL3006
FROM ${BUILD_ENV} AS sources

FROM docker.io/openresty/openresty:${RESTY_VERSION}-alpine-slim@${RESTY_RUNTIME_DIGEST} AS final
ARG BOUNCER_VERSION
ARG LUA_LIB_VERSION
ARG LUA_LIB_COMMIT
ARG LUA_RESTY_HTTP_VERSION
ARG LUA_RESTY_HTTP_COMMIT

LABEL org.opencontainers.image.title="CrowdSec OpenResty Bouncer" \
      org.opencontainers.image.description="OpenResty with the CrowdSec Lua bouncer" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://github.com/crowdsecurity/cs-openresty-bouncer" \
      org.opencontainers.image.version="${BOUNCER_VERSION}" \
      org.crowdsecurity.lua-cs-bouncer.version="${LUA_LIB_VERSION}" \
      org.crowdsecurity.lua-cs-bouncer.revision="${LUA_LIB_COMMIT}" \
      org.crowdsecurity.lua-resty-http.version="${LUA_RESTY_HTTP_VERSION}" \
      org.crowdsecurity.lua-resty-http.revision="${LUA_RESTY_HTTP_COMMIT}"

COPY --from=sources /sources/lua-resty-http/lib/resty/ /usr/local/openresty/lualib/resty/
COPY --from=sources /sources/lua-cs-bouncer/lib/ /usr/local/openresty/lualib/
COPY --from=sources /sources/lua-cs-bouncer/templates/ /var/lib/crowdsec/lua/templates/
COPY --chmod=0600 --from=sources \
    /sources/lua-cs-bouncer/config_example.conf \
    /etc/crowdsec/bouncers/crowdsec-openresty-bouncer.conf

COPY openresty/crowdsec_openresty.conf /etc/nginx/bouncer.d/crowdsec_openresty.conf
# hadolint ignore=SC2016
RUN set -eux; \
    sed -i \
      -e '1iresolver local=on ipv6=off;' \
      -e 's#${SSL_CERTS_PATH}#/etc/ssl/certs/ca-certificates.crt#g' \
      -e 's#/etc/crowdsec/bouncers/crowdsec-openresty-bouncer.conf#/var/run/crowdsec/crowdsec-openresty-bouncer.conf#g' \
      -e "s#crowdsec-openresty-bouncer/v[0-9][0-9.]*#crowdsec-openresty-bouncer/${BOUNCER_VERSION}#g" \
      /etc/nginx/bouncer.d/crowdsec_openresty.conf; \
    grep -qF 'include       mime.types;' /usr/local/openresty/nginx/conf/nginx.conf; \
    sed -i \
      's#include[[:space:]]\+mime\.types;#include       /usr/local/openresty/nginx/conf/mime.types;#' \
      /usr/local/openresty/nginx/conf/nginx.conf; \
    grep -qE '^[[:space:]]*#pid[[:space:]]+logs/nginx\.pid;' /usr/local/openresty/nginx/conf/nginx.conf; \
    sed -i \
      's|^[[:space:]]*#pid[[:space:]]\+logs/nginx\.pid;|pid /var/run/openresty/nginx.pid;|' \
      /usr/local/openresty/nginx/conf/nginx.conf; \
    grep -qF 'include /etc/nginx/conf.d/*.conf;' /usr/local/openresty/nginx/conf/nginx.conf; \
    sed -i \
      's#^\([[:space:]]*include[[:space:]]\+\)/etc/nginx/conf\.d/\*\.conf;#\1/etc/nginx/bouncer.d/*.conf;\n\1/etc/nginx/conf.d/*.conf;#' \
      /usr/local/openresty/nginx/conf/nginx.conf; \
    test "$(grep -cF 'include /etc/nginx/bouncer.d/*.conf;' /usr/local/openresty/nginx/conf/nginx.conf)" -eq 1; \
    mkdir -p /var/run/crowdsec

COPY --chmod=0755 docker/docker_start.sh /usr/local/bin/docker-entrypoint.sh

EXPOSE 80
STOPSIGNAL SIGQUIT
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]
