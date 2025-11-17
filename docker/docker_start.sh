#!/bin/sh
set -e

CROWDSEC_BOUNCER_CONFIG="${BOUNCER_CONFIG:-/etc/crowdsec/bouncers/crowdsec-openresty-bouncer.conf}"
STAGING_NGINX_CONF_DIR="/staging/etc/nginx/conf.d"
TARGET_NGINX_CONF_DIR="/etc/nginx/conf.d"
TRACKING_DIR="$TARGET_NGINX_CONF_DIR/.crowdsec-defaults"

sync_nginx_confd() {
    if [ -e "${TARGET_NGINX_CONF_DIR}/nginx.conf" ]; then
        echo "Error: Found nginx.conf in ${TARGET_NGINX_CONF_DIR}. Please remove it before starting the container." >&2
        exit 1
    fi

    if [ ! -d "$STAGING_NGINX_CONF_DIR" ]; then
        return
    fi

    mkdir -p "$TARGET_NGINX_CONF_DIR" "$TRACKING_DIR"

    for src in "$STAGING_NGINX_CONF_DIR"/*; do
        [ -e "$src" ] || continue

        base=$(basename "$src")
        dest="$TARGET_NGINX_CONF_DIR/$base"
        record="$TRACKING_DIR/$base"

        if [ -e "$dest" ]; then
            if [ ! -e "$record" ]; then
                echo "Warning: Cannot verify $dest because tracking information is missing. Keeping the current file." >&2
                continue
            fi

            if cmp -s "$dest" "$record"; then
                if ! cmp -s "$dest" "$src"; then
                    cp -a "$src" "$dest"
                    cp -a "$src" "$record"
                    echo "Updated default Nginx configuration $base because the image provides a newer version."
                fi
                continue
            fi

            if cmp -s "$dest" "$src"; then
                cp -a "$src" "$record"
                continue
            fi

            echo "Warning: Existing $dest differs from the locally recorded default. Keeping the user-provided file." >&2
            continue
        fi

        cp -a "$src" "$dest"
        cp -a "$src" "$record"
        echo "Copied default Nginx configuration $base to $TARGET_NGINX_CONF_DIR."
    done
}

sync_nginx_confd

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

lower=$(echo "$IS_LUALIB_IMAGE" | tr '[:upper:]' '[:lower:]')
if [ "$lower" != "true" ]; then
    exec /usr/local/openresty/bin/openresty -g "daemon off;"
fi
