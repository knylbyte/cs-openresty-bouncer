BUILD_VERSION?="$(shell git for-each-ref --sort=-v:refname --count=1 --format '%(refname)'  | cut -d '/' -f3)"
OUTDIR="crowdsec-openresty-bouncer-${BUILD_VERSION}/"
LUA_DIR="${OUTDIR}lua"
CONFIG_DIR="${OUTDIR}config"
TEMPLATE_DIR="${OUTDIR}templates"
OUT_ARCHIVE="crowdsec-openresty-bouncer.tgz"
LUA_LIB_VERSION?=v1.0.18
LUA_LIB_COMMIT?=59f3521e3918377fc1eb97d59a4056b6e9f5782f
LUA_RESTY_HTTP_VERSION?=0.18.0
LUA_RESTY_HTTP_COMMIT?=03995ff9a08194d48d446ed2fa099cd6de38fbef
default: release
release:
	git clone --branch "${LUA_LIB_VERSION}" --depth 1 https://github.com/crowdsecurity/lua-cs-bouncer.git
	test "$$(git -C lua-cs-bouncer rev-parse HEAD)" = "${LUA_LIB_COMMIT}"
	git clone --branch "v${LUA_RESTY_HTTP_VERSION}" --depth 1 https://github.com/ledgetech/lua-resty-http.git
	test "$$(git -C lua-resty-http rev-parse HEAD)" = "${LUA_RESTY_HTTP_COMMIT}"
	mkdir -p "${OUTDIR}"
	mkdir -p "${LUA_DIR}"
	mkdir -p "${CONFIG_DIR}"
	mkdir -p "${TEMPLATE_DIR}"
	cp -r lua-cs-bouncer/lib "${LUA_DIR}"
	cp -r lua-resty-http/lib/resty "${LUA_DIR}/lib/"
	cp lua-cs-bouncer/templates/* "${TEMPLATE_DIR}"
	cp -r lua-cs-bouncer/config_example.conf ${CONFIG_DIR}
	cp -r ./openresty/ ${OUTDIR}
	release_version=${BUILD_VERSION}; \
	sed -i "s#\$${BOUNCER_VERSION}#$${release_version}#g" "${OUTDIR}openresty/crowdsec_openresty.conf"; \
	grep -qF "crowdsec-openresty-bouncer/$${release_version}\")" "${OUTDIR}openresty/crowdsec_openresty.conf"
	cp install.sh ${OUTDIR}
	cp uninstall.sh ${OUTDIR}
	chmod +x ${OUTDIR}install.sh
	chmod +x ${OUTDIR}uninstall.sh
	tar cvzf ${OUT_ARCHIVE} ${OUTDIR}
	rm -rf ${OUTDIR}
	rm -rf "lua-cs-bouncer/"
	rm -rf "lua-resty-http/"
clean:
	rm -rf "${OUTDIR}"
	rm -rf "${OUT_ARCHIVE}"
	rm -rf "lua-cs-bouncer/"
	rm -rf "lua-resty-http/"
