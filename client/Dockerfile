FROM            alpine AS cloudpub

LABEL           maintainer="CloudPub <support@cloudpub.ru>"

COPY            ./target/x86_64-unknown-linux-musl/minimal/client /clo
COPY            client/entrypoint.sh /

RUN             mkdir -p /home/cloudpub && \
                addgroup -g 4551 -S cloudpub && \
                adduser -u 4551 -S cloudpub -G cloudpub -h /home/cloudpub -s /bin/ash && \
                chown -R cloudpub:cloudpub /home/cloudpub && \
                chmod +x /entrypoint.sh

USER            cloudpub:cloudpub

EXPOSE          4551

ENTRYPOINT      ["/entrypoint.sh"]
