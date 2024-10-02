FROM            alpine as cloudpub

RUN             apk add --no-cache --virtual .bootstrap-deps ca-certificates && \
                wget -O /tmp/clo.tar.gz https://cloudpub.ru/download/linux/x86_64/clo.tar.gz && \
                tar xf /tmp/clo.tar.gz -C / && \
                apk del .bootstrap-deps && \
                rm -rf /tmp/* && \
                rm -rf /var/cache/apk/*

FROM            busybox:glibc

LABEL           maintainer="CloudPub <support@cloudpub.ru>"

COPY            --from=cloudpub /clo /bin/clo
COPY            entrypoint.sh /

RUN             mkdir -p /home/cloudpub /home/ngrok/.ngrok2 && \
                        addgroup -g 4551 -S cloudpub && \
                adduser -u 4551 -S cloudpub -G cloudpub -h /home/cloudpub -s /bin/ash && \
                        chown -R cloudpub:cloudpub /home/cloudpub && \
                chmod +x /entrypoint.sh

USER            cloudpub:cloudpub

EXPOSE          4551

ENTRYPOINT      ["/entrypoint.sh"]
