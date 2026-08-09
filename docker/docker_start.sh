#!/bin/sh
set -eu

DEFAULT_BOUNCER_CONFIG="/etc/crowdsec/bouncers/crowdsec-openresty-bouncer.conf"
RUNTIME_BOUNCER_CONFIG="/var/run/crowdsec/crowdsec-openresty-bouncer.conf"
RUNTIME_NGINX_DIR="/var/run/openresty"
RUNTIME_NGINX_EVENTS_CONFIG="${RUNTIME_NGINX_DIR}/events.conf"
RUNTIME_NGINX_HTTP_CONFIG="${RUNTIME_NGINX_DIR}/http.conf"

log() {
    printf '[docker-entrypoint] %s\n' "$*"
}

fail() {
    printf '[docker-entrypoint] ERROR: %s\n' "$*" >&2
    exit 1
}

set_config_from_env() {
    config_key="$1"
    config_file="$2"
    temp_file="${config_file}.tmp"

    if ! CONFIG_KEY="$config_key" awk '
        BEGIN {
            key = ENVIRON["CONFIG_KEY"]
            value = ENVIRON[key]
            exit(value ~ /[\r\n]/ ? 1 : 0)
        }
    ' </dev/null; then
        fail "$config_key must not contain carriage returns or newlines"
    fi

    CONFIG_KEY="$config_key" awk '
        BEGIN {
            key = ENVIRON["CONFIG_KEY"]
            value = ENVIRON[key]
            found = 0
        }
        {
            line = $0
            separator = index(line, "=")
            candidate = separator > 0 ? substr(line, 1, separator - 1) : ""
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", candidate)

            if (line !~ /^[[:space:]]*#/ && candidate == key) {
                print key "=" value
                found = 1
                next
            }

            print line
        }
        END {
            if (!found) {
                print key "=" value
            }
        }
    ' "$config_file" > "$temp_file"

    mv "$temp_file" "$config_file"
}

prepare_bouncer_config() {
    config_source="${BOUNCER_CONFIG:-$DEFAULT_BOUNCER_CONFIG}"
    [ -r "$config_source" ] || fail "Bouncer config is not readable: $config_source"

    mkdir -p "$(dirname "$RUNTIME_BOUNCER_CONFIG")"
    umask 077

    if [ "$config_source" != "$RUNTIME_BOUNCER_CONFIG" ]; then
        cp "$config_source" "$RUNTIME_BOUNCER_CONFIG"
    fi
    chmod 0600 "$RUNTIME_BOUNCER_CONFIG"

    if [ -n "${API_KEY_FILE:-}" ]; then
        [ -r "$API_KEY_FILE" ] || fail "API_KEY_FILE is not readable: $API_KEY_FILE"
        API_KEY="$(sed -n '1p' "$API_KEY_FILE")"
        [ -n "$API_KEY" ] || fail "API_KEY_FILE is empty: $API_KEY_FILE"
        export API_KEY
    fi

    if ! printenv API_URL >/dev/null 2>&1 && printenv CROWDSEC_LAPI_URL >/dev/null 2>&1; then
        API_URL="$CROWDSEC_LAPI_URL"
        export API_URL
    fi

    config_params='
ALWAYS_SEND_TO_APPSEC
API_KEY
API_URL
APPSEC_CONNECT_TIMEOUT
APPSEC_DROP_UNREADABLE_BODY
APPSEC_FAILURE_ACTION
APPSEC_PROCESS_TIMEOUT
APPSEC_SEND_TIMEOUT
APPSEC_URL
BAN_TEMPLATE_PATH
BOUNCING_ON_TYPE
CACHE_EXPIRATION
CACHE_SIZE
CAPTCHA_EXPIRATION
CAPTCHA_PROVIDER
CAPTCHA_RET_CODE
CAPTCHA_TEMPLATE_PATH
ENABLED
ENABLE_INTERNAL
EXCLUDE_LOCATION
FALLBACK_REMEDIATION
MODE
REDIRECT_LOCATION
REQUEST_TIMEOUT
RET_CODE
SCENARIOS_CONTAINING
SCENARIOS_NOT_CONTAINING
SECRET_KEY
SITE_KEY
SSL_VERIFY
STREAM_REQUEST_TIMEOUT
TLS_CLIENT_CERT
TLS_CLIENT_KEY
UPDATE_FREQUENCY
USE_TLS_AUTH
'

    for var in $config_params; do
        if printenv "$var" >/dev/null 2>&1; then
            set_config_from_env "$var" "$RUNTIME_BOUNCER_CONFIG"
        fi
    done
}

prepare_nginx_runtime_config() {
    : "${SERVER_TOKENS:=on}"
    : "${WORKER_CONNECTIONS:=1024}"

    case "$WORKER_CONNECTIONS" in
        ''|*[!0-9]*|0)
            fail "Invalid WORKER_CONNECTIONS=$WORKER_CONNECTIONS. Use a positive integer."
            ;;
        *)
            log "Setting worker_connections to $WORKER_CONNECTIONS"
            ;;
    esac

    case "$(printf '%s' "$SERVER_TOKENS" | tr '[:upper:]' '[:lower:]')" in
        off|false|0|no)
            log "Disabling server_tokens"
            server_tokens=off
            ;;
        on|true|1|yes)
            log "Leaving server_tokens enabled"
            server_tokens=on
            ;;
        *)
            fail "Invalid SERVER_TOKENS=$SERVER_TOKENS. Use on/off."
            ;;
    esac

    mkdir -p "$RUNTIME_NGINX_DIR"
    printf 'worker_connections %s;\n' "$WORKER_CONNECTIONS" > "$RUNTIME_NGINX_EVENTS_CONFIG"
    printf 'server_tokens %s;\n' "$server_tokens" > "$RUNTIME_NGINX_HTTP_CONFIG"
    chmod 0644 "$RUNTIME_NGINX_EVENTS_CONFIG" "$RUNTIME_NGINX_HTTP_CONFIG"
}

if [ "$#" -eq 0 ]; then
    set -- /usr/local/openresty/bin/openresty -g "daemon off;"
elif [ "${1#-}" != "$1" ]; then
    set -- /usr/local/openresty/bin/openresty "$@"
fi

case "$1" in
    openresty|nginx|/usr/local/openresty/bin/openresty|/usr/local/openresty/nginx/sbin/nginx)
        prepare_bouncer_config
        prepare_nginx_runtime_config
        ;;
esac

exec "$@"
