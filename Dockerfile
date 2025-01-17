#
# baseimage-gui Dockerfile
#
# https://github.com/jlesage/docker-baseimage-gui
#

ARG BASEIMAGE=alpine:3.12

# Pull base image.
FROM ${BASEIMAGE} as gui

# Define software versions.
ARG LIBVNCSERVER_VERSION=9029b86
ARG X11VNC_VERSION=29597a9
ARG STUNNEL_VERSION=5.44
ARG NOVNC_VERSION=fa559b3
ARG BOOTSTRAP_VERSION=3.3.7
ARG FONTAWESOME_VERSION=4.7.0
ARG JQUERY_VERSION=3.2.1
ARG JQUERY_UI_TOUCH_PUNCH_VERSION=4bc0091

# Define software download URLs.
ARG LIBVNCSERVER_URL=https://github.com/jlesage/libvncserver/archive/${LIBVNCSERVER_VERSION}.tar.gz
ARG X11VNC_URL=https://github.com/jlesage/x11vnc/archive/${X11VNC_VERSION}.tar.gz
ARG STUNNEL_URL=https://www.usenix.org.uk/mirrors/stunnel/archive/5.x/stunnel-${STUNNEL_VERSION}.tar.gz
ARG NOVNC_URL=https://github.com/jlesage/novnc/archive/${NOVNC_VERSION}.tar.gz
ARG BOOTSTRAP_URL=https://github.com/twbs/bootstrap/releases/download/v${BOOTSTRAP_VERSION}/bootstrap-${BOOTSTRAP_VERSION}-dist.zip
ARG FONTAWESOME_URL=https://fontawesome.com/v${FONTAWESOME_VERSION}/assets/font-awesome-${FONTAWESOME_VERSION}.zip
ARG JQUERY_URL=https://code.jquery.com/jquery-${JQUERY_VERSION}.min.js
ARG JQUERY_UI_TOUCH_PUNCH_URL=https://raw.github.com/furf/jquery-ui-touch-punch/${JQUERY_UI_TOUCH_PUNCH_VERSION}/jquery.ui.touch-punch.min.js

# Define working directory.
WORKDIR /tmp

# Compile x11vnc.
RUN \
    add-pkg --virtual build-dependencies \
        curl \
        build-base \
        autoconf \
        automake \
        libtool \
        libx11-dev \
        libxtst-dev \
        libjpeg-turbo-dev \
        libpng-dev \
        libxinerama-dev \
        libxdamage-dev \
        libxcomposite-dev \
        libxcursor-dev \
        libxrandr-dev \
        libxfixes-dev \
        libice-dev \
        && \
    # Download sources
    mkdir libvncserver x11vnc && \
    curl -sS -L ${LIBVNCSERVER_URL} | tar -xz --strip 1 -C libvncserver && \
    curl -sS -L ${X11VNC_URL} | tar -xz --strip 1 -C x11vnc && \
    # Compile libvncserver
    cd libvncserver && \
    ./autogen.sh --prefix=/tmp/install && \
    make install && \
    cd .. && \
    # Compile x11vnc
    cd x11vnc && \
    autoreconf -v --install && \
    PKG_CONFIG_PATH=/tmp/install/lib/pkgconfig/ ./configure --prefix=/tmp/install --with-websockets && \
    make install && \
    cd .. && \
    # Install libraries
    strip install/lib/libvnc*.so && \
    cp -P install/lib/libvncserver.so* /usr/lib/ && \
    cp -P install/lib/libvncclient.so* /usr/lib/ && \
    # Install binaries
    strip install/bin/x11vnc && \
    cp install/bin/x11vnc /usr/bin/ && \
    # Cleanup
    del-pkg build-dependencies && \
    rm -rf /tmp/* /tmp/.[!.]*

# Compile stunnel
RUN \
    add-pkg --virtual build-dependencies \
        curl \
        build-base \
        openssl-dev && \
    # Download sources
    mkdir stunnel && \
    curl -# -L ${STUNNEL_URL} | tar -xz --strip 1 -C stunnel && \
    # Compile stunnel
    cd stunnel && \
    ./configure && \
    make && \
    find . && \
    cd .. && \
    # Install binaries
    strip stunnel/src/stunnel && \
    cp -v stunnel/src/stunnel /usr/bin/ && \
    # Cleanup
    del-pkg build-dependencies && \
    rm -rf /tmp/* /tmp/.[!.]*

# Install packages.
RUN \
    add-pkg \
        # X11 VNC server dependencies
        openssl \
        libxtst \
        libxi \
        libjpeg-turbo \
        libxcomposite \
        # X virtual framebuffer display server
        xvfb \
        xdpyinfo \
        # Openbox window manager
        openbox \
        xsetroot \
        # Font
        font-croscore && \
    # Remove some unneeded stuff.
    rm -rf /var/cache/fontconfig/*

# Install noVNC.
RUN \
    NODEJS_NPM=$(apk -q --no-cache search npm | head -n1) && \
    add-pkg --virtual build-dependencies curl ${NODEJS_NPM:-nodejs} && \
    mkdir noVNC && \
    curl -sS -L ${NOVNC_URL} | tar -xz --strip 1 -C noVNC && \
    mkdir -p /opt/novnc/include && \
    mkdir -p /opt/novnc/js && \
    mkdir -p /opt/novnc/css && \
    NOVNC_CORE="\
        noVNC/include/util.js \
        noVNC/include/webutil.js \
        noVNC/include/base64.js \
        noVNC/include/websock.js \
        noVNC/include/des.js \
        noVNC/include/keysymdef.js \
        noVNC/include/keyboard.js \
        noVNC/include/input.js \
        noVNC/include/display.js \
        noVNC/include/rfb.js \
        noVNC/include/keysym.js \
        noVNC/include/inflator.js \
    " && \
    cp -v $NOVNC_CORE /opt/novnc/include/ && \
    # Minify noVNC core JS files
    env HOME=/tmp npm install --cache /tmp/.npm uglify-js source-map && \
    ./node_modules/uglify-js/bin/uglifyjs \
        --compress --mangle --source-map \
        --output /opt/novnc/js/novnc-core.min.js -- $NOVNC_CORE && \
    env HOME=/tmp npm uninstall --cache /tmp/.npm uglify-js source-map && \
    sed-patch 's|"noVNC/|"/|g' /opt/novnc/js/novnc-core.min.js.map && \
    echo -e "\n//# sourceMappingURL=/js/novnc-core.min.js.map" >> /opt/novnc/js/novnc-core.min.js && \
    # Install Bootstrap
    curl -sS -L -O ${BOOTSTRAP_URL} && \
    unzip bootstrap-${BOOTSTRAP_VERSION}-dist.zip && \
    cp -v bootstrap-${BOOTSTRAP_VERSION}-dist/css/bootstrap.min.css /opt/novnc/css/ && \
    cp -v bootstrap-${BOOTSTRAP_VERSION}-dist/js/bootstrap.min.js /opt/novnc/js/ && \
    # Install Font Awesome
    curl -sS -L -O ${FONTAWESOME_URL} && \
    unzip font-awesome-${FONTAWESOME_VERSION}.zip && \
    cp -vr font-awesome-${FONTAWESOME_VERSION}/fonts /opt/novnc/ && \
    cp -v font-awesome-${FONTAWESOME_VERSION}/css/font-awesome.min.css /opt/novnc/css/ && \
    # Install JQuery
    curl -sS -L -o /opt/novnc/js/jquery.min.js ${JQUERY_URL} && \
    curl -sS -L -o /opt/novnc/js/jquery.ui.touch-punch.min.js ${JQUERY_UI_TOUCH_PUNCH_URL} && \
    # Cleanup
    del-pkg build-dependencies && \
    rm -rf /tmp/* /tmp/.[!.]*

# Install nginx.
RUN \
    add-pkg nginx && \
    rm /etc/nginx/nginx.conf \
       /etc/init.d/nginx \
       /etc/logrotate.d/nginx \
       && \
    rm -r /etc/nginx/conf.d \
          /etc/nginx/modules \
          /var/lib/nginx/* \
          /var/log/nginx \
          /var/www \
          && \
    ln -s /config/log/nginx /var/lib/nginx/logs && \
    if [ -d /var/tmp/nginx ]; then \
        # alpine 3.6
        rm -r /var/tmp/nginx && \
        ln -s /tmp/nginx /var/tmp/nginx; \
    else \
        # alpine 3.5
        ln -s /tmp/nginx /var/lib/nginx/tmp; \
    fi && \
    # Adjust user under which nginx will run.
    userdel nginx && \
    groupdel www-data && \
    useradd --system \
            --home-dir /dev/null \
            --no-create-home \
            --shell /sbin/nologin \
            nginx && \
    # Users/groups changed, save them.
    cp /etc/passwd /defaults/ && \
    cp /etc/group /defaults && \
    # Generate default DH params.
    echo "Generating default DH parameters (2048 bits)..." && \
    env HOME=/tmp openssl dhparam \
        -out "/defaults/dhparam.pem" \
        2048 \
        > /dev/null 2>&1 && \
    rm -rf /tmp/* /tmp/.[!.]*

# Add files.
COPY rootfs-gui/ /

# Set version to CSS and JavaScript file URLs.
RUN sed-patch "s/UNIQUE_VERSION/$(date | md5sum | cut -c1-10)/g" /opt/novnc/index.vnc

# Minify noVNC UI JS files
RUN \
    NODEJS_NPM=$(apk -q --no-cache search nodejs-npm) && \
    add-pkg --virtual build-dependencies ${NODEJS_NPM:-nodejs} && \
    NOVNC_UI="\
        /opt/novnc/app/modulemgr.js \
        /opt/novnc/app/ui.js \
        /opt/novnc/app/modules/hideablenavbar.js \
        /opt/novnc/app/modules/dynamicappname.js \
        /opt/novnc/app/modules/password.js \
        /opt/novnc/app/modules/clipboard.js \
        /opt/novnc/app/modules/autoscaling.js \
        /opt/novnc/app/modules/clipping.js \
        /opt/novnc/app/modules/viewportdrag.js \
        /opt/novnc/app/modules/fullscreen.js \
        /opt/novnc/app/modules/virtualkeyboard.js \
        /opt/novnc/app/modules/rightclick.js \
    " && \
    env HOME=/tmp npm install --cache /tmp/.npm uglify-js && \
    ./node_modules/uglify-js/bin/uglifyjs \
        --compress --mangle --source-map \
        --output /opt/novnc/js/novnc-ui.min.js -- $NOVNC_UI && \
    env HOME=/tmp npm uninstall --cache /tmp/.npm uglify-js && \
    echo -e "\n//# sourceMappingURL=/js/novnc-ui.min.js.map" >> /opt/novnc/js/novnc-ui.min.js && \
    sed-patch 's/\/opt\/novnc//g' /opt/novnc/js/novnc-ui.min.js.map && \
    # Cleanup
    del-pkg build-dependencies && \
    rm -rf /tmp/* /tmp/.[!.]*

# Generate and install favicons.
RUN \
    APP_ICON_URL=https://github.com/jlesage/docker-templates/raw/master/jlesage/images/generic-app-icon.png && \
    install_app_icon.sh "$APP_ICON_URL"

# Set environment variables.
ENV DISPLAY=:0 \
    DISPLAY_WIDTH=1280 \
    DISPLAY_HEIGHT=768

# Expose ports.
#   - 5800: VNC web interface
#   - 5900: VNC
EXPOSE 5800 5900

#
# makemkv Dockerfile
#
# https://github.com/jlesage/docker-makemkv
#

# Build MakeMKV.
FROM ubuntu:bionic as makemkv
COPY makemkv-builder /tmp/makemkv-builder
RUN /tmp/makemkv-builder/builder/build.sh /tmp/

# Build YAD.  The one from the Alpine repo doesn't support the multi-progress
# feature.
FROM ${BASEIMAGE} as yad
ARG YAD_VERSION=0.40.0
ARG YAD_URL=https://downloads.sourceforge.net/project/yad-dialog/yad-${YAD_VERSION}.tar.xz
RUN apk --no-cache add \
    build-base \
    curl \
    gtk+2.0-dev \
    intltool
RUN \
    # Set same default compilation flags as abuild.
    export CFLAGS="-Os -fomit-frame-pointer" && \
    export CXXFLAGS="$CFLAGS" && \
    export CPPFLAGS="$CFLAGS" && \
    export LDFLAGS="-Wl,--as-needed" && \
    # Download.
    mkdir /tmp/yad && \
    curl -# -L "${YAD_URL}" | tar xJ --strip 1 -C /tmp/yad && \
    # Compile.
    cd /tmp/yad && \
    ./configure && \
    make -j$(nproc) && \
    strip src/yad


# final image
FROM gui
# Install MakeMKV.
COPY --from=makemkv /tmp/makemkv-install /

# Install Java 8.
RUN \
    add-pkg openjdk8-jre-base && \
    # Removed uneeded stuff.
    rm -r \
        /usr/lib/jvm/java-1.8-openjdk/bin \
        /usr/lib/jvm/java-1.8-openjdk/lib \
        /usr/lib/jvm/java-1.8-openjdk/jre/lib/ext \
        && \
    # Cleanup.
    rm -rf /tmp/* /tmp/.[!.]*

# Install YAD.
COPY --from=yad /tmp/yad/src/yad /usr/bin/
RUN add-pkg gtk+2.0

# Install dependencies.
RUN \
    add-pkg \
        wget \
        sed \
        findutils \
        util-linux \
        lsscsi

# Adjust the openbox config.
RUN \
    # Maximize only the main window.
    sed-patch 's/<application type="normal">/<application type="normal" title="MakeMKV BETA">/' \
        /etc/xdg/openbox/rc.xml && \
    # Make sure the main window is always in the background.
    sed-patch '/<application type="normal" title="MakeMKV BETA">/a \    <layer>below</layer>' \
        /etc/xdg/openbox/rc.xml

# Generate and install favicons.
RUN \
    APP_ICON_URL=https://raw.githubusercontent.com/jlesage/docker-templates/master/jlesage/images/makemkv-icon.png && \
    install_app_icon.sh "$APP_ICON_URL"

# Add files.
COPY rootfs/ /

# Update the default configuration file with the latest beta key.
RUN /opt/makemkv/bin/makemkv-update-beta-key /defaults/settings.conf

# Set environment variables.
ENV APP_NAME="MakeMKV" \
    MAKEMKV_KEY="BETA"

# Define mountable directories.
VOLUME ["/config"]
VOLUME ["/storage"]
VOLUME ["/output"]