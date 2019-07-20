FROM lsiobase/alpine:3.10 as buildstage

RUN \
 echo "**** install build deps ****" && \
 apk add --no-cache \
	curl \
	g++ \
	gcc \
	git \
	libc-dev \
	libffi-dev \
	make \
	musl-dev \
	openssl-dev \
	python3 \
	python3-dev \
	zlib-dev

RUN \
 echo "**** build pyinstaller ****" && \
 PYINSTALLER_VERSION=$(curl -sX GET "https://api.github.com/repos/pyinstaller/pyinstaller/releases/latest" \
        | awk '/tag_name/{print $4;exit}' FS='[""]') && \
 git clone --depth 1 \
	--single-branch \
	--branch ${PYINSTALLER_VERSION} \
	https://github.com/pyinstaller/pyinstaller.git \
	/tmp/pyinstaller && \
 cd /tmp/pyinstaller/bootloader && \
 CFLAGS="-Wno-stringop-overflow" python3 \
	./waf configure --no-lsb all && \
 pip3 install ..
 

RUN \
 echo "**** build compose ****" && \
 cd /tmp && \
 COMPOSE_VERSION=$(curl -sX GET "https://api.github.com/repos/docker/compose/releases/latest" \
	| awk '/tag_name/{print $4;exit}' FS='[""]') && \
 git clone https://github.com/docker/compose.git && \
 cd compose && \
 git checkout "${COMPOSE_VERSION}" && \
 pip3 install \
	-r requirements.txt && \
 ./script/build/write-git-sha && \
 pyinstaller docker-compose.spec && \
 mv dist/docker-compose /


# runtime stage
FROM lsiobase/alpine:3.10

# set version label
ARG BUILD_DATE
ARG VERSION
ARG TAISUN_RELEASE
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

RUN \
 echo "**** install build packages ****" && \
 apk add --no-cache --virtual=build-dependencies \
	curl \
	gcc \
	libffi-dev \
	make \
	musl-dev \
	nodejs-npm \
	openssl-dev && \
 echo "**** install runtime packages ****" && \
 apk add --no-cache \
	docker-cli \
	expect \
	libcap \
	nodejs \
	tcl && \
 npm config set unsafe-perm true && \
 npm i npm@latest -g && \
 echo "**** install Taisun ****" && \
 mkdir -p \
	/usr/src/Taisun && \
 if [ -z ${TAISUN_RELEASE+x} ]; then \
	TAISUN_RELEASE=$(curl -sX GET "https://api.github.com/repos/Taisun-Docker/taisun/releases/latest" \
	| awk '/tag_name/{print $4;exit}' FS='[""]'); \
 fi && \
 curl -o \
 /tmp/taisun.tar.gz -L \
	"https://github.com/Taisun-Docker/taisun/archive/${TAISUN_RELEASE}.tar.gz" && \
 tar -xzf \
 /tmp/taisun.tar.gz -C \
	/usr/src/Taisun/ --strip-components=1 && \
 echo ${TAISUN_RELEASE} > /usr/src/Taisun/version && \
 echo "**** install node modules ****" && \
 npm install --prefix /usr/src/Taisun && \
 echo "**** permissions ****" && \
 chown -R abc:abc /usr/src/Taisun && \
 addgroup -g 100 docker && \ 
 echo "**** cleanup ****" && \
 apk del --purge \
	build-dependencies && \
 rm -rf \
	/root \
	/tmp/* && \
 mkdir -p \
	/root

# Docker compose
COPY --from=buildstage /docker-compose /usr/local/bin/

# add local files
COPY root/ /

# ports
EXPOSE 3000
