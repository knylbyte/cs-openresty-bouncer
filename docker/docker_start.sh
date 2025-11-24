#!/bin/sh
set -e

CROWDSEC_BOUNCER_CONFIG="${BOUNCER_CONFIG:-/etc/crowdsec/bouncers/crowdsec-openresty-bouncer.conf}"
NGINX_CONF_DIR="/etc/nginx/conf.d"

check_nginx_confd() {
    if [ -e "${NGINX_CONF_DIR}/nginx.conf" ]; then
        echo "Error: Found nginx.conf in ${NGINX_CONF_DIR}. Please remove it before starting the container." >&2
        exit 1
    fi

    if [ -e "${NGINX_CONF_DIR}/crowdsec_openresty.conf" ]; then
        echo "Error: Found crowdsec_openresty.conf in ${NGINX_CONF_DIR}. Please remove it before starting the container." >&2
        exit 1
    fi
}

params='
ALWAYS_SEND_TO_APPSEC
API_KEY
API_URL
APPSEC_CONNECT_TIMEOUT
APPSEC_FAILURE_ACTION
APPSEC_PROCESS_TIMEOUT
APPSEC_SEND_TIMEOUT
APPSEC_URL
BAN_TEMPLATE_PATH
BOUNCING_ON_TYPE
CACHE_EXPIRATION
CAPTCHA_EXPIRATION
CAPTCHA_PROVIDER
CAPTCHA_TEMPLATE_PATH
EXCLUDE_LOCATION
FALLBACK_REMEDIATION
MODE
REDIRECT_LOCATION
REQUEST_TIMEOUT
RET_CODE
SECRET_KEY
SITE_KEY
SSL_VERIFY
UPDATE_FREQUENCY
'

for var in $params; do
    eval "value=\$$var"
    if [ -n "$value" ]; then
        sed -i "s,${var}.*,${var}=${value}," "$CROWDSEC_BOUNCER_CONFIG"
    fi
done

check_nginx_confd

lower=$(echo "$IS_LUALIB_IMAGE" | tr '[:upper:]' '[:lower:]')
if [ "$lower" != "true" ]; then
    exec /usr/local/openresty/bin/openresty -g "daemon off;"
fi
