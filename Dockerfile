
ARG fd_version="1.3"

FROM debian:stable-slim
ARG fd_version
ENV FD_HOME /usr/share/fusiondirectory
ENV FD_VERSION ${fd_version}
ENV FD_PLUGINS_DIR /opt/fd_${FD_VERSION}_plugins

# Install dependencies
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    wget ca-certificates curl ldap-utils\
    gettext javascript-common libarchive-extract-perl apache2 locales \
    libjs-prototype libjs-scriptaculous smarty3 smarty-gettext libcrypt-cbc-perl \
    libdigest-sha-perl libfile-copy-recursive-perl libnet-ldap-perl \
    libpath-class-perl libterm-readkey-perl libxml-twig-perl \
    openssl php php-xml php-cas php-cli php-curl php-fpdf php-gd \
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
      wget https://repos.fusiondirectory.org/sources/fusiondirectory/fusiondirectory-${FD_VERSION}.tar.gz -P /opt/ &&\
      tar -xvzf /opt/fusiondirectory-${FD_VERSION}.tar.gz -C /opt &&\
      mv /opt/fusiondirectory-${FD_VERSION} ${FD_HOME} &&\
      rm /opt/fusiondirectory-${FD_VERSION}.tar.gz &&\
      chmod 750 ${FD_HOME}/contrib/bin/* &&\
      sed -i "s|/var/www/fusiondirectory|${FD_HOME}|g" $(find ${FD_HOME}/contrib/bin/ -type f -maxdepth 1) &&\
      mv ${FD_HOME}/contrib/bin/* /usr/local/bin/ &&\
      mv ${FD_HOME}/contrib/smarty/plugins/*.php /usr/share/php/smarty3/plugins/ &&\
      mkdir -p /etc/ldap/schema/fusiondirectory/ &&\
      mv ${FD_HOME}/contrib/openldap/* /etc/ldap/schema/fusiondirectory/ &&\
      mv ${FD_HOME}/contrib/fusiondirectory.conf /var/cache/fusiondirectory/template/fusiondirectory.conf &&\
      rm -f /opt/fusiondirectory-${FD_VERSION}.tar.gz &&\
      mkdir -p ${FD_HOME}/html/javascript &&\
      ln -s /usr/share/javascript/scriptaculous ${FD_HOME}/html/javascript/scriptaculous &&\
      ln -s /usr/share/javascript/prototype ${FD_HOME}/html/javascript/prototype &&\
      fusiondirectory-setup --yes --check-directories --update-cache --update-locales

# FIX the breezy theme, wrong include path for most of scriptaculous & prototype javascripts
RUN  sed -i 's|include/prototype.js|javascript/prototype/prototype.js|g' ${FD_HOME}/ihtml/themes/breezy/headers.tpl &&\
     sed -i -E 's#include/(scriptaculous|builder|effects|dragdrop|controls\.js)#javascript/scriptaculous/\1#g' ${FD_HOME}/ihtml/themes/breezy/headers.tpl


COPY generate_plugins_archives.sh /bin/
COPY fusiondirectory.conf /etc/apache2/sites-available/fusiondirectory.conf
#download the fusiondirectory plugins and create the installation archives
RUN wget https://repos.fusiondirectory.org/sources/fusiondirectory/fusiondirectory-plugins-${FD_VERSION}.tar.gz -P /opt/ &&\
      tar -xvzf /opt/fusiondirectory-plugins-${FD_VERSION}.tar.gz -C /opt &&\
      chmod +x /bin/generate_plugins_archives.sh && /bin/generate_plugins_archives.sh &&\
      rm -f /opt/fusiondirectory-plugins-${FD_VERSION}.tar.gz &&\
      rm -r /opt/fusiondirectory-plugins-${FD_VERSION} &&\
      chmod -R +r ${FD_PLUGINS_DIR}

# Apache Logging to stdout
# RUN ln -sf /proc/self/fd/1 /var/log/apache2/access.log && \
#     ln -sf /proc/self/fd/1 /var/log/apache2/error.log && \
#     ln -sf /proc/self/fd/1 /var/log/apache2/other_vhosts_access.log

# configure better security for Apache2. disable obsolete configs
RUN a2disconf other-vhosts-access-log && a2dissite 000-default && a2disconf security &&\
    mv /etc/apache2/conf-available/security.conf /etc/apache2/conf-available/security_default.conf && \
    chmod 640 /etc/apache2/sites-available/fusiondirectory.conf && a2ensite fusiondirectory
COPY docker-entrypoint/entrypoint.sh /sbin/fd-entrypoint
COPY security_hardened.conf /etc/apache2/conf-available/
RUN chmod 750 /sbin/fd-entrypoint

EXPOSE 80
ENTRYPOINT ["/sbin/fd-entrypoint"]
CMD ["run"] 
