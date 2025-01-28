# syntax=docker.io/docker/dockerfile:1.4
ARG CM_VERSION=0.18.1-rc7
ARG CM_SNAPSHOT_VERSION=0.19-preview2
ARG NONODO_VERSION=2.17.2-beta
ARG S6_OVERLAY_VERSION=3.2.0.2
ARG TELEGRAF_VERSION=1.32.1
ARG CM_CALLER_VERSION=0.2.0-rc.1

# =============================================================================
# STAGE: base
#
# =============================================================================

FROM debian:11-slim AS base

RUN <<EOF
set -e
apt-get update
apt-get install -y --no-install-recommends wget ca-certificates xz-utils lua5.4 libslirp0 nginx
rm -rf /var/lib/apt/lists/* /var/log/* /var/cache/*
EOF

ARG NONODO_VERSION
RUN wget -qO- https://github.com/Calindra/nonodo/releases/download/v${NONODO_VERSION}/nonodo-v${NONODO_VERSION}-linux-$(dpkg --print-architecture).tar.gz | \
    tar xzf - -C /usr/local/bin nonodo

ARG S6_OVERLAY_VERSION
RUN wget -qO- https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz | \
    tar xJf - -C / 
RUN wget -qO- https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-$(uname -m).tar.xz | \
    tar xJf - -C / 

# install telegraf
ARG TELEGRAF_VERSION
RUN wget -qO- https://dl.influxdata.com/telegraf/releases/telegraf-${TELEGRAF_VERSION}_linux_$(dpkg --print-architecture).tar.gz | \
    tar xzf - --strip-components 2 -C / ./telegraf-${TELEGRAF_VERSION}

RUN useradd --user-group app

RUN chown -R app:app /run

# configure telegraf
RUN <<EOF
mkdir -p /etc/telegraf
echo "
[agent]
    interval = '60s'
    round_interval = true
    metric_batch_size = 1000
    metric_buffer_limit = 10000
    collection_jitter = '0s'
    flush_interval = '60s'
    flush_jitter = '0s'
    precision = '1ms'
    omit_hostname = true

[[inputs.procstat]]

[[outputs.health]]
    service_address = 'http://:9274'

[[inputs.procstat.filter]]
    name = 'rollups-node'
    process_names = ['nonodo', 'cartesi-machine', 'jsonrpc-remote-cartesi-machine', 'telegraf', 'nginx']

[[outputs.prometheus_client]]
    listen = ':9000'
    collectors_exclude = ['gocollector', 'process']
" > /etc/telegraf/telegraf.conf
EOF

# Configure s6 telegraf
RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/telegraf
echo "longrun" > /etc/s6-overlay/s6-rc.d/telegraf/type
mkdir -p /etc/s6-overlay/s6-rc.d/telegraf/data
echo "#!/command/execlineb -P
wget -qO /dev/null 127.0.0.1:9274/
" > /etc/s6-overlay/s6-rc.d/telegraf/data/check
echo "#!/command/execlineb -P
pipeline -w { sed --unbuffered \"s/^/telegraf: /\" }
fdmove -c 2 1
/usr/bin/telegraf
" > /etc/s6-overlay/s6-rc.d/telegraf/run
EOF

# Configure nginx
RUN <<EOF
mkdir -p /var/log/nginx/
chown -R app:app /var/log/nginx/
mkdir -p /var/cache
chown -R app:app /var/cache
chown -R app:app /var/lib/nginx
echo "
user app;
worker_processes  auto;

error_log  /var/log/nginx/error.log notice;
pid        /var/run/nginx.pid;

events {
    worker_connections  1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '$remote_addr - $upstream_cache_status rt=$request_time [$time_local] \"$request\" '
                      '$status $body_bytes_sent \"$http_referer\" '
                      '\"$http_user_agent\" \"$http_x_forwarded_for\" '
                      'uct=\"$upstream_connect_time\" uht=\"$upstream_header_time\" urt=\"$upstream_response_time\"';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    #tcp_nopush     on;

    keepalive_timeout  65;

    #gzip  on;

    map \$request_method \$purge_method {
        PURGE 1;
        default 0;
    }

    proxy_cache_path /var/cache keys_zone=mycache:200m;

    include /etc/nginx/sites-enabled/*;
}
" > /etc/nginx/nginx.conf
rm /etc/nginx/sites-enabled/*
EOF

# Configure s6 nginx
RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/nginx
echo "longrun" > /etc/s6-overlay/s6-rc.d/nginx/type
echo "#!/command/execlineb -P
pipeline -w { sed --unbuffered \"s/^/nginx: /\" }
fdmove -c 2 1
/usr/sbin/nginx -g \"daemon off;\"
" > /etc/s6-overlay/s6-rc.d/nginx/run
touch /etc/s6-overlay/s6-rc.d/user/contents.d/nginx
EOF

ARG BASE_PATH=/mnt
ENV BASE_PATH ${BASE_PATH}

ARG DATA_PATH=${BASE_PATH}/node
ENV DATA_PATH ${DATA_PATH}

RUN chown -R app:app ${BASE_PATH}

# =============================================================================
# STAGE: nonode-base
#
# =============================================================================

FROM base AS nonode-base

# ARG CM_VERSION
# RUN <<EOF
# set -e
# wget -qO /tmp/cartesi-machine.deb https://github.com/cartesi/machine-emulator/releases/download/v${CM_VERSION}/cartesi-machine-v${CM_VERSION}_$(dpkg --print-architecture).deb
# dpkg -i /tmp/cartesi-machine.deb
# rm /tmp/cartesi-machine.deb
# EOF

ARG CM_VERSION
RUN wget -qO- https://github.com/edubart/cartesi-machine-everywhere/releases/download/v${CM_VERSION}/cartesi-machine-linux-musl-$(dpkg --print-architecture).tar.xz | \
    tar xJf - --strip-components 1 -C / cartesi-machine-linux-musl-$(dpkg --print-architecture)/bin cartesi-machine-linux-musl-$(dpkg --print-architecture)/share

ARG APP_PATH=/opt/cartesi/app
ENV APP_PATH ${APP_PATH}

ARG IMAGE_PATH=/opt/cartesi/image
ENV IMAGE_PATH ${IMAGE_PATH}

# Configure s6 services
RUN <<EOF
mkdir -p ${APP_PATH}
chown -R app:app ${APP_PATH}
mkdir -p /etc/s6-overlay/s6-rc.d/prepare-dirs
echo "oneshot" > /etc/s6-overlay/s6-rc.d/prepare-dirs/type
echo "#!/command/with-contenv sh
mkdir -p \${DATA_PATH}/db
" > /etc/s6-overlay/s6-rc.d/prepare-dirs/run.sh
chmod +x /etc/s6-overlay/s6-rc.d/prepare-dirs/run.sh
echo "/etc/s6-overlay/s6-rc.d/prepare-dirs/run.sh" \
> /etc/s6-overlay/s6-rc.d/prepare-dirs/up
mkdir -p /etc/s6-overlay/s6-rc.d/nonodo/dependencies.d
touch /etc/s6-overlay/s6-rc.d/nonodo/dependencies.d/prepare-dirs
echo "longrun" > /etc/s6-overlay/s6-rc.d/nonodo/type
echo "#!/bin/sh
nonodo_chain_args='--anvil-port=8545 --anvil-address=0.0.0.0'
nonodo_sequencer_args=''
inputbox_args=''
extra_args=''
if [ ! -z \"\${FROM_BLOCK}\" ] && [ ! -z \"\${RPC_URL}\" ] && [ ! -z \"\${APP_ADDRESS}\" ]; then
  nonodo_chain_args=\"--from-l1-block=\${FROM_BLOCK} --rpc-url=\${RPC_URL} --contracts-application-address=\${APP_ADDRESS}\"
  inputbox_args=\"--contracts-input-box-block=\${FROM_BLOCK}\"
fi
if [ ! -z \"\${ESPRESSO_STARTING_BLOCK}\" ] && [ ! -z \"\${ESPRESSO_BASE_URL}\" ] && [ ! -z \"\${ESPRESSO_NAMESPACE}\" ]; then
  nonodo_sequencer_args=\"--sequencer=espresso --espresso-url=\${ESPRESSO_BASE_URL} --from-block=\${ESPRESSO_STARTING_BLOCK} --namespace=\${ESPRESSO_NAMESPACE}\"
fi
if [ ! -z \"\${CARTESI_CONTRACTS_INPUT_BOX_DEPLOYMENT_BLOCK_NUMBER}\" ]; then
  inputbox_args=\"--contracts-input-box-block=\${CARTESI_CONTRACTS_INPUT_BOX_DEPLOYMENT_BLOCK_NUMBER}\"
fi
if [ ! -z \"\${CARTESI_CONTRACTS_INPUT_BOX_ADDRESS}\" ]; then
  inputbox_args=\"\${inputbox_args} --contracts-input-box-address=\${CARTESI_CONTRACTS_INPUT_BOX_ADDRESS}\"
fi
if [ ! -z \"\${DEBUG}\" ]; then
  extra_args=\"\${extra_args} --enable-debug\"
fi
if [ ! -z \"\${EXTRA_ARGS}\" ]; then
  extra_args=\"\${extra_args} \${EXTRA_ARGS}\"
fi
exec nonodo \
  --http-rollups-port=5004 --http-port=8080 \
  --sqlite-file=\${DATA_PATH}/db/database.sqlite \
  \${nonodo_chain_args} \
  \${nonodo_sequencer_args} \
  \${inputbox_args} \
  \${extra_args} \
  -- cartesi-machine \
    --network \
    --env=ROLLUP_HTTP_SERVER_URL=http://10.0.2.2:5004 \
    --flash-drive=label:root,filename:\${IMAGE_PATH}/root.ext2 \
    --volume=\${APP_PATH}:/mnt \
    --workdir=/mnt \
    \${CM_FLAGS} \
    -- bash /mnt/entrypoint.sh
" > /etc/s6-overlay/s6-rc.d/nonodo/start.sh
echo "#!/command/execlineb -P
with-contenv
pipeline -w { sed --unbuffered \"s/^/nonodo: /\" }
fdmove -c 2 1
/bin/sh /etc/s6-overlay/s6-rc.d/nonodo/start.sh
" > /etc/s6-overlay/s6-rc.d/nonodo/run
mkdir -p /etc/s6-overlay/s6-rc.d/user/contents.d
touch /etc/s6-overlay/s6-rc.d/user/contents.d/prepare-dirs \
    /etc/s6-overlay/s6-rc.d/user/contents.d/nonodo
EOF

# =============================================================================
# STAGE: nonode-snapshot-base
#
# =============================================================================

FROM base AS nonode-snapshot-base

ARG CM_SNAPSHOT_VERSION
RUN wget -qO- https://github.com/edubart/cartesi-machine-everywhere/releases/download/v${CM_SNAPSHOT_VERSION}/cartesi-machine-linux-musl-$(dpkg --print-architecture).tar.xz | \
    tar xJf - --strip-components 1 -C / cartesi-machine-linux-musl-$(dpkg --print-architecture)/bin cartesi-machine-linux-musl-$(dpkg --print-architecture)/share

ARG CM_CALLER_VERSION
RUN wget -qO- https://github.com/lynoferraz/cm-caller/releases/download/v${CM_CALLER_VERSION}/cm-caller-v${CM_CALLER_VERSION}-linux-$(dpkg --print-architecture).tar.gz | \
    tar xzf - -C /usr/local/bin cm-caller
    
ARG IMAGE_SNAPSHOT_PATH=/opt/cartesi/snapshots/0
ENV IMAGE_SNAPSHOT_PATH ${IMAGE_SNAPSHOT_PATH}

# Configure s6 services
RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/prepare-dirs
echo "oneshot" > /etc/s6-overlay/s6-rc.d/prepare-dirs/type
echo "#!/command/with-contenv sh
mkdir -p \${DATA_PATH}/db
mkdir -p \${DATA_PATH}/advance
mkdir -p \${DATA_PATH}/inspect
" > /etc/s6-overlay/s6-rc.d/prepare-dirs/run.sh
chmod +x /etc/s6-overlay/s6-rc.d/prepare-dirs/run.sh
echo "/etc/s6-overlay/s6-rc.d/prepare-dirs/run.sh" \
> /etc/s6-overlay/s6-rc.d/prepare-dirs/up
mkdir -p /etc/s6-overlay/s6-rc.d/advance/dependencies.d
touch /etc/s6-overlay/s6-rc.d/advance/dependencies.d/prepare-dirs
echo "longrun" > /etc/s6-overlay/s6-rc.d/advance/type
echo "#!/bin/sh
nonodo_chain_args='--anvil-port=8545 --anvil-address=0.0.0.0'
nonodo_sequencer_args=''
inputbox_args=''
extra_args=''
if [ ! -z \"\${FROM_BLOCK}\" ] && [ ! -z \"\${RPC_URL}\" ] && [ ! -z \"\${APP_ADDRESS}\" ]; then
  nonodo_chain_args=\"--from-l1-block=\${FROM_BLOCK} --rpc-url=\${RPC_URL} --contracts-application-address=\${APP_ADDRESS}\"
  inputbox_args=\"--contracts-input-box-block=\${FROM_BLOCK}\"
fi
if [ ! -z \"\${ESPRESSO_STARTING_BLOCK}\" ] && [ ! -z \"\${ESPRESSO_BASE_URL}\" ] && [ ! -z \"\${ESPRESSO_NAMESPACE}\" ]; then
  nonodo_sequencer_args=\"--sequencer=espresso --espresso-url=\${ESPRESSO_BASE_URL} --from-block=\${ESPRESSO_STARTING_BLOCK} --namespace=\${ESPRESSO_NAMESPACE}\"
fi
if [ ! -z \"\${CARTESI_CONTRACTS_INPUT_BOX_DEPLOYMENT_BLOCK_NUMBER}\" ]; then
  inputbox_args=\"--contracts-input-box-block=\${CARTESI_CONTRACTS_INPUT_BOX_DEPLOYMENT_BLOCK_NUMBER}\"
fi
if [ ! -z \"\${CARTESI_CONTRACTS_INPUT_BOX_ADDRESS}\" ]; then
  inputbox_args=\"\${inputbox_args} --contracts-input-box-address=\${CARTESI_CONTRACTS_INPUT_BOX_ADDRESS}\"
fi
if [ ! -z \"\${DEBUG}\" ]; then
  extra_args=\"\${extra_args} --enable-debug\"
fi
if [ ! -z \"\${EXTRA_ARGS}\" ]; then
  extra_args=\"\${extra_args} \${EXTRA_ARGS}\"
fi
exec nonodo \
  --http-rollups-port=5004 --http-port=8081 \
  --sqlite-file=\${DATA_PATH}/db/database.sqlite \
  \${nonodo_chain_args} \
  \${nonodo_sequencer_args} \
  \${inputbox_args} \
  \${extra_args} \
  --disable-inspect \
  -- cm-caller \
    -image=\${IMAGE_SNAPSHOT_PATH} \
    -store-path=\${DATA_PATH}/advance \
    -disable-inspect -disable-consistency-checks -disable-remote
" > /etc/s6-overlay/s6-rc.d/advance/start.sh
echo "#!/command/execlineb -P
with-contenv
pipeline -w { sed --unbuffered \"s/^/advance: /\" }
fdmove -c 2 1
/bin/sh /etc/s6-overlay/s6-rc.d/advance/start.sh
" > /etc/s6-overlay/s6-rc.d/advance/run
mkdir -p /etc/s6-overlay/s6-rc.d/inspect/dependencies.d
touch /etc/s6-overlay/s6-rc.d/inspect/dependencies.d/advance
touch /etc/s6-overlay/s6-rc.d/inspect/dependencies.d/prepare-dirs
echo "longrun" > /etc/s6-overlay/s6-rc.d/inspect/type
echo "#!/bin/sh
exec nonodo \
  --http-rollups-port=5005 \
  --http-port=8082 \
  --disable-devnet --disable-advance -- \
  cm-caller \
    -image=\${IMAGE_SNAPSHOT_PATH} \
    -store-path=\${DATA_PATH}/inspect \
    -enable-watcher -watcher-path=\${DATA_PATH}/advance/local_image \
    -disable-advance -disable-consistency-checks -disable-remote
" > /etc/s6-overlay/s6-rc.d/inspect/start.sh
echo "#!/command/execlineb -P
with-contenv
pipeline -w { sed --unbuffered \"s/^/inspect: /\" }
fdmove -c 2 1
/bin/sh /etc/s6-overlay/s6-rc.d/inspect/start.sh
" > /etc/s6-overlay/s6-rc.d/inspect/run
mkdir -p /etc/s6-overlay/s6-rc.d/user/contents.d
touch /etc/s6-overlay/s6-rc.d/user/contents.d/prepare-dirs \
    /etc/s6-overlay/s6-rc.d/user/contents.d/advance \
    /etc/s6-overlay/s6-rc.d/user/contents.d/inspect
EOF

# =============================================================================
# STAGE: cloud config
#
# =============================================================================

FROM debian:11-slim AS cloud-config

# Create init wrapper
RUN <<EOF
echo '#!/bin/sh
# run /init with PID 1, creating a new PID namespace if necessary
if [ "$$" -eq 1 ]; then
    # we already have PID 1
    exec /init "$@"
else
    # create a new PID namespace
    exec unshare --pid sh -c '"'"'
        # set up /proc and start the real init in the background
        unshare --mount-proc /init "$@" &
        child="$!"
        # forward signals to the real init
        trap "kill -INT \$child" INT
        trap "kill -TERM \$child" TERM
        # wait until the real init exits
        # ("wait" returns early on signals; "kill -0" checks if the process exists)
        until wait "$child" || ! kill -0 "$child" 2>/dev/null; do :; done
    '"'"' sh "$@"
fi
' > /init-wrapper
chmod +x /init-wrapper
EOF

# =============================================================================
# STAGE: nonode-cloud-snapshot
#
# =============================================================================

FROM nonode-snapshot-base as nonode-snapshot-cloud

# Configure nginx server with cache
RUN <<EOF
echo "
server {
    listen       80;
    listen  [::]:80;

    proxy_cache mycache;

    location /graphql {
        proxy_pass   http://localhost:8081/graphql;
    }

    location /nonce {
        proxy_pass   http://localhost:8081/nonce;
    }

    location /submit {
        proxy_pass   http://localhost:8081/submit;
    }

    location /inspect {
        proxy_pass   http://localhost:8082/inspect;
        proxy_cache_valid 200 5s;
        proxy_cache_background_update on;
        proxy_cache_use_stale error timeout updating http_500 http_502
                              http_503 http_504;
        proxy_cache_lock on;

        proxy_read_timeout 300s;
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
    }

    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
        root   /usr/share/nginx/html;
    }
}
" > /etc/nginx/sites-available/cloud.conf
ln -sr /etc/nginx/sites-available/cloud.conf /etc/nginx/sites-enabled/cloud.conf
EOF

RUN touch /etc/s6-overlay/s6-rc.d/user/contents.d/telegraf

COPY --from=cloud-config /init-wrapper /init-wrapper

CMD ["/init-wrapper"]

# =============================================================================
# STAGE: node-snapshot
#
# =============================================================================

FROM nonode-snapshot-base as nonode-snapshot

# Configure nginx server with cache
RUN <<EOF
echo "
server {
    listen       80;
    listen  [::]:80;

    location /graphql {
        proxy_pass   http://localhost:8081/graphql;
    }

    location /nonce {
        proxy_pass   http://localhost:8081/nonce;
    }

    location /submit {
        proxy_pass   http://localhost:8081/submit;
    }

    location /inspect {
        proxy_pass   http://localhost:8082/inspect;
    }

    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
        root   /usr/share/nginx/html;
    }
}
" > /etc/nginx/sites-available/node.conf
ln -sr /etc/nginx/sites-available/node.conf /etc/nginx/sites-enabled/node.conf
EOF

USER app

CMD ["/init"]

# =============================================================================
# STAGE: nonode-cloud
#
# =============================================================================

FROM nonode-base as nonode-cloud

# Configure nginx server with cache
RUN <<EOF
echo "
server {
    listen       80;
    listen  [::]:80;

    proxy_cache mycache;

    location /graphql {
        proxy_pass   http://localhost:8080/graphql;
    }

    location /nonce {
        proxy_pass   http://localhost:8080/nonce;
    }

    location /submit {
        proxy_pass   http://localhost:8080/submit;
    }

    location /inspect {
        proxy_pass   http://localhost:8080/inspect;
        proxy_cache_valid 200 5s;
        proxy_cache_background_update on;
        proxy_cache_use_stale error timeout updating http_500 http_502
                              http_503 http_504;
        proxy_cache_lock on;

        proxy_read_timeout 300s;
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
    }

    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
        root   /usr/share/nginx/html;
    }
}
" > /etc/nginx/sites-available/cloud.conf
ln -sr /etc/nginx/sites-available/cloud.conf /etc/nginx/sites-enabled/cloud.conf
EOF

RUN touch /etc/s6-overlay/s6-rc.d/user/contents.d/telegraf

COPY --from=cloud-config /init-wrapper /init-wrapper

CMD ["/init-wrapper"]

# =============================================================================
# STAGE: node
#
# =============================================================================

FROM nonode-base as nonode

# Configure nginx server with cache
RUN <<EOF
echo "
server {
    listen       80;
    listen  [::]:80;

    location / {
        proxy_pass   http://localhost:8080/;
    }

    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
        root   /usr/share/nginx/html;
    }
}
" > /etc/nginx/sites-available/node.conf
ln -sr /etc/nginx/sites-available/node.conf /etc/nginx/sites-enabled/node.conf
EOF

USER app

CMD ["/init"]
