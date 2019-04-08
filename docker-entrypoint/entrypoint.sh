#!/bin/bash
# expected env variables :
echo testexport APACHE_SECURITY=$(tr '[:upper:]' '[:lower:]' <<<${APACHE_SECURITY:-'default'})
set -i
run_fusiondirectory() {
  fusiondirectory-setup --check-directories --update-cache --update-locales
  # chmod 777 /tmp
  echo "Starting fusiondirectory ..."
  exec apache2ctl -D FOREGROUND
  echo "FusionDirectory execution stopped"
}

enable_a2_security() {
  case $APACHE_SECURITY in
   hard|hardened) a2enconf security_hardened;;
   default) a2enconf security_default ;;
   *) echo -e "ERROR: Invalid value for APACHE_SECURITY ! (Was $APACHE_SECURITY)\n  Allowed: 'default'|'hardened'"
      return 1 ;;
  esac
}

