ARG BUILD_ENV=git
FROM docker.io/openresty/openresty:alpine-fat AS with_deps
RUN luarocks install lua-resty-http 0.17.1-0

FROM with_deps AS git
ARG BUILD_ENV=git
ARG LUA_LIB_VERSION=v1.0.11
RUN if [ "$BUILD_ENV" == "git" ]; then apk add --no-cache git; fi
RUN if [ "$BUILD_ENV" == "git" ]; then git clone -b "${LUA_LIB_VERSION}" https://github.com/crowdsecurity/lua-cs-bouncer.git ; fi

FROM with_deps AS local
RUN if [ "$BUILD_ENV" == "local" ]; then COPY ./lua-cs-bouncer/ lua-cs-bouncer; fi

FROM ${BUILD_ENV}
RUN mkdir -p /etc/crowdsec/bouncers/ /var/lib/crowdsec/lua/templates/
RUN cp -R lua-cs-bouncer/lib/* /usr/local/openresty/lualib/
RUN cp -R lua-cs-bouncer/templates/* /var/lib/crowdsec/lua/templates/
RUN cp lua-cs-bouncer/config_example.conf /etc/crowdsec/bouncers/crowdsec-openresty-bouncer.conf
RUN rm -rf ./lua-cs-bouncer/
COPY ./openresty /tmp
RUN mkdir -p /etc/nginx/stream.d /etc/nginx/crowdsec-conf.d /staging/etc/nginx/crowdsec-conf.d
RUN SSL_CERTS_PATH=/etc/ssl/certs/ca-certificates.crt envsubst '$SSL_CERTS_PATH' < /tmp/crowdsec_openresty.conf > /etc/nginx/crowdsec-conf.d/crowdsec_openresty.conf
RUN sed -i '1 i\resolver local=on ipv6=off;' /etc/nginx/crowdsec-conf.d/crowdsec_openresty.conf
RUN if ! grep -q "include /etc/nginx/stream.d/\*.conf" /usr/local/openresty/nginx/conf/nginx.conf; then \
        printf '\nstream {\n    include /etc/nginx/stream.d/*.conf;\n}\n' >> /usr/local/openresty/nginx/conf/nginx.conf; \
    fi
RUN sed -i 's#^\([[:space:]]*include[[:space:]]\)/etc/nginx/conf\.d/\*\.conf;#\1/etc/nginx/crowdsec-conf.d/*.conf;\n\1/etc/nginx/conf.d/*.conf;#' /usr/local/openresty/nginx/conf/nginx.conf
COPY ./docker/docker_start.sh /

ENTRYPOINT ["/bin/sh", "docker_start.sh"]
