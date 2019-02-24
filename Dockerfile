
ARG fusiondirectory_version="1.2.3"

FROM debian:stable-slim
ARG fusiondirectory_version

# Install dependencies
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    wget ca-certificates \
    gettext javascript-common libarchive-extract-perl apache2 locales \
    libjs-prototype libjs-scriptaculous smarty3 libcrypt-cbc-perl \
    libdigest-sha-perl libfile-copy-recursive-perl libnet-ldap-perl \
    libpath-class-perl libterm-readkey-perl libxml-twig-perl \
    openssl php php-cas php-cli php-curl php-fpdf php-gd \
    php-imagick php-imap php-ldap php-mbstring php-recode \
    && apt-get clean autoclean && rm -rf /var/lib/apt/lists/*

# more locales !
RUN sed -i 's/^#\( fr_FR.*UTF-8\)/\1/g' /etc/locale.gen && \
    locale-gen
# download and install manually some extensions
RUN wget https://repos.fusiondirectory.org/sources/smarty3-i18n/smarty3-i18n-1.0.tar.gz -P /opt/ &&\
      tar -xzvf /opt/smarty3-i18n-1.0.tar.gz -C /opt &&\
      mv /opt/smarty3-i18n-1.0/block.t.php /usr/share/php/smarty3/plugins/block.t.php &&\
      rm -f  /opt/smarty3-i18n-1.0.tar.gz && rm -rf /opt/smarty3-i18n-1.0

RUN wget https://repos.fusiondirectory.org/sources/schema2ldif/schema2ldif-1.3.tar.gz -P /opt/ &&\
      tar -xzvf /opt/schema2ldif-1.3.tar.gz -C /opt &&\
      chmod +x /opt/schema2ldif-1.3/bin/* &&\
      mv /opt/schema2ldif-1.3/bin/* /usr/bin/ &&\
      rm -f /opt/schema2ldif-1.3.tar.gz && rm -rf /opt/schema2ldif-1.3

# download and install manually FusionDirectory
RUN mkdir -p /var/cache/fusiondirectory/template \
      /var/cache/fusiondirectory/tmp/ \
      /var/cache/fusiondirectory/locale/ \
      /var/spool/fusiondirectory/ &&\
      wget https://repos.fusiondirectory.org/sources/fusiondirectory/fusiondirectory-${fusiondirectory_version}.tar.gz -P /opt/ &&\
      tar -xvzf /opt/fusiondirectory-${fusiondirectory_version}.tar.gz -C /opt &&\
      mv /opt/fusiondirectory-${fusiondirectory_version} /var/www/fusiondirectory &&\
      rm /opt/fusiondirectory-${fusiondirectory_version}.tar.gz &&\
      chmod 750 /var/www/fusiondirectory/contrib/bin/* &&\
      mv /var/www/fusiondirectory/contrib/bin/* /usr/local/bin/ &&\
      mv /var/www/fusiondirectory/contrib/smarty/plugins/*.php /usr/share/php/smarty3/plugins/ &&\
      mkdir -p /etc/ldap/schema/fusiondirectory/ &&\
      mv /var/www/fusiondirectory/contrib/openldap/* /etc/ldap/schema/fusiondirectory/ &&\
      sed 's|mod_php5|mod_php7|g' /var/www/fusiondirectory/contrib/apache/fusiondirectory-apache.conf > /etc/apache2/sites-available/fusiondirectory.conf &&\
      mv /var/www/fusiondirectory/contrib /var/cache/fusiondirectory/template/fusiondirectory.conf &&\
      rm -rf /var/www/fusiondirectory/contrib/ && rm -f /opt/fusiondirectory-${fusiondirectory_version}.tar.gz &&\
      fusiondirectory-setup --yes --check-directories --update-cache --update-locales

#just download the fusiondirectory plugins
RUN wget https://repos.fusiondirectory.org/sources/fusiondirectory/fusiondirectory-plugins-${fusiondirectory_version}.tar.gz -P /opt/ &&\
      tar -xvzf /opt/fusiondirectory-plugins-${fusiondirectory_version}.tar.gz -C /opt &&\
      mv /opt/fusiondirectory-plugins-${fusiondirectory_version} /opt/fusiondirectory-plugins &&\
      rm -f /opt/fusiondirectory-plugins-${fusiondirectory_version}.tar.gz

# COPY docker-entrypoint/fd-repository.key fd-repository.key
# Apache Logging to stdout
# RUN ln -sf /proc/self/fd/1 /var/log/apache2/access.log && \
#     ln -sf /proc/self/fd/1 /var/log/apache2/error.log && \
#     ln -sf /proc/self/fd/1 /var/log/apache2/other_vhosts_access.log

# fix : apt-get doesn't install the fusiondirectory doc on container
# RUN cd /tmp && apt-get update && apt-get download fusiondirectory && dpkg-deb -x ./fusiondirectory*.deb /tmp && \
#     cp -R /tmp/usr/share/doc/fusiondirectory /usr/share/doc/ && \
#     rm -rf /tmp/* && apt-get clean autoclean && rm -rf /var/lib/apt/lists/*
# configure better security for Apache2. disable obsolete configs

RUN a2disconf other-vhosts-access-log && a2dissite 000-default && \
    chmod 644 /etc/apache2/sites-available/fusiondirectory.conf && a2ensite fusiondirectory

COPY docker-entrypoint/entrypoint.sh /sbin/fd-entrypoint
RUN chmod 750 /sbin/fd-entrypoint

EXPOSE 80 443
ENTRYPOINT ["/sbin/fd-entrypoint"]
