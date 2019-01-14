from debian:stable-slim
WORKDIR /root
COPY docker-entrypoint/fd-repository.key fd-repository.key
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y gnupg2 apt-transport-https locales && \
    apt-key add fd-repository.key && rm fd-repository.key && \
    echo "deb [arch=i386] https://repos.fusiondirectory.org/fusiondirectory-current/debian-stretch stretch main" >> /etc/apt/sources.list && \
    echo "deb [arch=i386] https://repos.fusiondirectory.org/fusiondirectory-extra/debian-stretch stretch main" >> /etc/apt/sources.list && \
    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    fusiondirectory-schema fusiondirectory && apt-get clean autoclean && rm -rf /var/lib/apt/lists/*

# Apache Logging to stdout
RUN ln -sf /proc/self/fd/1 /var/log/apache2/access.log && \
    ln -sf /proc/self/fd/1 /var/log/apache2/error.log && \
    ln -sf /proc/self/fd/1 /var/log/apache2/other_vhosts_access.log


# fix : apt-get doesn't install the fusiondirectory doc on container
RUN cd /tmp && apt-get update && apt-get download fusiondirectory && dpkg-deb -x ./fusiondirectory*.deb /tmp && \
    cp -R /tmp/usr/share/doc/fusiondirectory /usr/share/doc/ && \
    rm -rf /tmp/* && apt-get clean autoclean && rm -rf /var/lib/apt/lists/*
# configure better security for Apache2. disable obsolete configs
COPY fusiondirectory.conf /etc/apache2/sites-available/fusiondirectory.conf
RUN a2disconf fusiondirectory other-vhosts-access-log && a2dissite 000-default && \
    chmod 644 /etc/apache2/sites-available/fusiondirectory.conf && a2ensite fusiondirectory

COPY docker-entrypoint/entrypoint.sh /sbin/fd-entrypoint
RUN chmod 750 /sbin/fd-entrypoint && sed -i 's/^#\( fr_FR.*UTF-8\)/\1/g' /etc/locale.gen && \
    locale-gen

EXPOSE 80 443
ENTRYPOINT ["/sbin/fd-entrypoint"]
