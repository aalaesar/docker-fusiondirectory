from debian:stable-slim

WORKDIR /root
COPY docker-entrypoint/fd-repository.key fd-repository.key
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y gnupg2 && \
    apt-key add fd-repository.key && \
    echo "deb [arch=i386] http://repos.fusiondirectory.org/fusiondirectory-current/debian-stretch stretch main" >> /etc/apt/sources.list && \
    echo "deb [arch=i386] http://repos.fusiondirectory.org/fusiondirectory-extra/debian-stretch stretch main" >> /etc/apt/sources.list && \
    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    fusiondirectory-schema fusiondirectory && \
    apt-get clean

# Apache Logging to stdout
RUN ln -sf /proc/self/fd/1 /var/log/apache2/access.log && \
    ln -sf /proc/self/fd/1 /var/log/apache2/error.log && \
    ln -sf /proc/self/fd/1 /var/log/apache2/other_vhosts_access.log


# fix : apt-get doesn't install the fusiondirectory doc on container
RUN apt-get download fusiondirectory && dpkg-deb -x ./fusiondirectory*.deb /tmp && \
    cp -R /tmp/usr/share/doc/fusiondirectory /usr/share/doc/ && \
    rm -rf /tmp/* && rm fusiondirectory*.deb

COPY docker-entrypoint/entrypoint.sh /opt/fd/entrypoint.sh

EXPOSE 80 443
ENTRYPOINT ["/opt/fd/entrypoint.sh"]
