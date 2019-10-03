#!/bin/bash
set -e
# environnement
[ "$TERM"  != 'xterm' ] && export DEBIAN_FRONTEND=noninteractive
# FD_PLUGINS=""
FD_CONFIG_FILE=${FD_CONFIG_FILE:-'/etc/fusiondirectory/fusiondirectory.conf'}
# FD_SECRET_CONFIG=""
FD_FORCE_SETUP=${FD_FORCE_SETUP:-true}
LDAP_CONFIGDN_ADMIN=${LDAP_CONFIGDN_ADMIN:-"cn=admin,cn=config"}
APACHE_SECURITY=${APACHE_SECURITY:-true}
# LDAP_CONFIGDN_PASS=""
# LDAP_ZONE
# LDAP_URI
# LDAP_DN
# LDAP_ADMINDN
# LDAP_ADMIN_PASS

logging() {
  local this_log_lvl=$1
  local this_log_msg=$2
  local global_log_lvl=${LOG_LEVEL:-255}
  if [ $this_log_lvl -le $global_log_lvl ]; then
    echo "$this_log_msg"
  fi
}
fd_config_find_value() {
  [ $# -ne 2 ] && return 2
  local fd_conf_file="$1"
  [ ! -r $fd_conf_file ] && return 2
  local read_this="$2"
  case $read_this in
    URI)this_result=$(grep URI $fd_conf_file |cut -d '"' -f2| cut -d '/' -f1-3);;
    adminDn)this_result=$(grep adminDn $fd_conf_file|cut -d '"' -f2);;
    adminPassword)this_result=$(grep adminPassword $fd_conf_file|cut -d '"' -f2);;
    rootDn)this_result=$(grep URI $fd_conf_file |cut -d '"' -f2| cut -d '/' -f4);;
    *) return 2;;
  esac
  [ -z "$this_result" ] && return 1
  echo "$this_result"
}

fd_config_read_secrets() {
  local this_secret_location=$1
  if [ -d $this_secret_location ]; then
    true
  fi
}
find_fd_plugin_deps() {
  echo true
}
fd_install_plugins() {
  local my_plugin=${1}
  local plugin_folder=${2:$FD_PLUGINS_REP}
  local fd_home=${3:$FD_HOME}
 find_fd_plugin_deps $my_plugin $plugin_folder
}
fd_install_ldap_schema() {
  local this_plugin=$1 ldap_uri
  if [ ! -f  $FD_CONFIG_FILE ]; then
    ldap_uri=${LDAP_URI:-'ldap:///'}
  else
    ldap_uri=$(fd_config_find_value $FD_CONFIG_FILE 'URI')
  fi
  # assume the schema package is already installed
  if [ $# -ne 0 ]; then
     my_schemas=(-i)
    # shellcheck disable=SC2044,SC2061
    for my_plugin_schemas in $(find /etc/ldap/schema/fusiondirectory -name "$this_plugin"*.schema); do
      my_schemas+=($my_plugin_schemas)
    done
  fi
  #echo fusiondirectory-insert-schema -o \"-H "$(fd_config_find_value $FD_CONFIG_FILE 'URI')" -x -D \'$LDAP_CONFIGDN_ADMIN\' -w $LDAP_CONFIGDN_PASS\" ${my_schemas[*]}
  while read logging; do
    # hide the password that might be shown by the command logs.
    if [ -n "$LDAP_CONFIGDN_PASS" ]; then
      echo $logging | sed "s/$LDAP_CONFIGDN_PASS/<HIDDEN>/g"
    else
      echo $logging
    fi
  done< <(fusiondirectory-insert-schema -o "-H $ldap_uri -x -D '$LDAP_CONFIGDN_ADMIN' -w $LDAP_CONFIGDN_PASS" ${my_schemas[*]})
}

run_fusiondirectory() {
  if [ $APACHE_SECURITY ]; then
    echo '<Directory />
   AllowOverride None
   Require all denied
</Directory>
ServerTokens Prod
ServerSignature Off
TraceEnable Off
Header set X-Frame-Options: "sameorigin"
' > /etc/apache2/conf-available/security.conf
  a2enconf security
fi
  fusiondirectory-setup --check-directories --update-cache --update-locales
  chmod 777 /tmp
  echo "Starting fusiondirectory >>>"
  exec apache2ctl -D FOREGROUND
  echo "FusionDirectory execution stopped"
}

create_fd_config() {
  local ldap_zone=$1
  local ldap_url=$2
  local ldap_dn=$3
  local ldap_admindn=$4
  local ldap_admin_pass=$5
echo "<?xml version=\"1.0\"?>
<conf>
  <main default=\"$ldap_zone\"
        logging=\"TRUE\"
        displayErrors=\"FALSE\"
        forceSSL=\"FALSE\"
        templateCompileDirectory=\"/var/spool/fusiondirectory/\"
        debugLevel=\"0\"
    >

    <!-- Location definition -->
    <location name=\"$ldap_zone\"
    >
        <referral URI=\"$ldap_url/$ldap_dn\"
                        adminDn=\"cn=$ldap_admindn\"
                        adminPassword=\"$ldap_admin_pass\" />
    </location>
  </main>
</conf>" > $FD_CONFIG_FILE
}
# load the n=config password from a eventual secret file.
[ -f $LDAP_CONFIGDN_PASS ] && LDAP_CONFIGDN_PASS="$(cat $LDAP_CONFIGDN_PASS)"

# in case the config file is not mounted in the container
if [ "$FD_FORCE_SETUP" = false ] ; then
  # if the secret file is mounted as a secret
  if [ -n "$FD_SECRET_CONFIG" ] && [ -f $FD_SECRET_CONFIG ]; then
    cp $FD_SECRET_CONFIG $FD_CONFIG_FILE
  else
    # shellcheck disable=SC2153
    create_fd_config $LDAP_ZONE $LDAP_URI $LDAP_DN $LDAP_ADMINDN $LDAP_ADMIN_PASS
  fi
  chown root:www-data $FD_CONFIG_FILE
  chmod 640 $FD_CONFIG_FILE
fi
fd_install_ldap_schema
[ -n "$FD_PLUGINS" ] && fd_install_plugins $FD_PLUGINS
if [ $# -eq 0 ]; then
  run_fusiondirectory
else
  case $1 in
    install) shift
      case $1 in
	      schema|schemas) shift; fd_install_ldap_schema ;;
        plugin|plugins) shift;  fd_install_plugins "$@" ;;
      esac
     ;;
    service) shift
      case $1 in
        start) shift; run_fusiondirectory;;
        reload|restart) shift; apache2ctl -k graceful ;;
      esac
  esac
fi
