#!/bin/bash

NGINX_CONF="crowdsec_openresty.conf"
NGINX_CONF_DIR="/usr/local/openresty/nginx/conf/conf.d/"
LIB_PATH="/usr/local/openresty/lualib"

uninstall() {
    rm -f -- "${LIB_PATH}/crowdsec.lua"
    rm -rf -- "${LIB_PATH}/plugins/crowdsec"
    rm -f -- \
        "${LIB_PATH}/resty/http.lua" \
        "${LIB_PATH}/resty/http_connect.lua" \
        "${LIB_PATH}/resty/http_headers.lua"
    rm -f -- "${NGINX_CONF_DIR}/${NGINX_CONF}"
}

if ! [ "$(id -u)" = 0 ]; then
    echo "Please run the uninstall script as root or with sudo" >&2
    exit 1
fi

uninstall
echo "crowdsec-openresty-bouncer uninstalled successfully"
echo ""
echo "Don't forget to remove 'include /usr/local/openresty/nginx/conf/conf.d/crowdsec_openresty.conf;' in your nginx configuration file to disable the bouncer and make openresty start again."
echo ""
echo "Run 'sudo systemctl restart openresty.service' to stop openresty-bouncer"
