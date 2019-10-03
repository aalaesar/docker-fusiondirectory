#!/bin/bash
##### expected env variables #####
### provided by image ###
# FD_HOME /usr/share/fusiondirectory
# FD_VERSION ${fd_version}
# FD_PLUGINS_DIR /opt/fd_${FD_VERSION}_plugins

### provided by user ###
# shellcheck disable=SC2155
export FD_SERVICE=$(tr '[:upper:]' '[:lower:]' <<<"${FD_SERVICE:-yes}")
export APACHE_SECURITY=$(tr '[:upper:]' '[:lower:]' <<<"${APACHE_SECURITY:-default}") 
export INSTALL_SCHEMAS=$(tr '[:upper:]' '[:lower:]' <<<"${INSTALL_SCHEMAS:-no}")
export OPENLDAP_URL="${OPENLDAP_URL:-ldap://localhost:389}"
export LDAP_CONFIG_USER=${LDAP_CONFIG_USER:-cn=admin,cn=config}
if  [ -f "$LDAP_CONFIG_PWD" ]; then
  export LDAP_CONFIG_PWD=$(cat "$LDAP_CONFIG_PWD")
fi
export FD_PLUGINS=$(tr '[:upper:]' '[:lower:]' <<<"${FD_PLUGINS:-}")

### internal usage ###
export FD_CONFIG_FILE=${FD_CONFIG_FILE:-"/etc/fusiondirectory/fusiondirectory.conf"}
export FD_CONFIG_SECRET_FILE=${FD_CONFIG_SECRET_FILE:-"/etc/fusiondirectory/fusiondirectory.secrets"}
set -e
run_fusiondirectory() {
  if [ -f "$FD_CONFIG_SECRET_FILE" ]; then
    sed -i -E "s|(^\s*)#(\s*include)(.*fusiondirectory.secrets)|\1 \2 $FD_CONFIG_SECRET_FILE|" "$FD_CONFIG_FILE"
  fi
  fusiondirectory-setup --check-directories --update-cache --update-locales
  # chmod 777 /tmp
  # ulimit -n 8182
  echo "Starting fusiondirectory ..."
  exec apache2ctl -D FOREGROUND
  echo "FusionDirectory execution stopped"
}

enable_a2_security() {
  # allow selection of 2 security profiles
  case $APACHE_SECURITY in
   hard|hardened) a2enconf security_hardened;;
   default) a2enconf security_default ;;
   *) echo -e "ERROR: Invalid value for APACHE_SECURITY ! (was $APACHE_SECURITY)\n  Allowed: 'default'|'hardened'"
      return 1 ;;
  esac
}

fd_config_find_ldap_url() {
  [ $# -ne 1 ] && return 2
  local fd_conf_file="$1"
  this_result=$(grep URI "$fd_conf_file" |cut -d '"' -f2| cut -d '/' -f1-3)
  echo "$this_result"
}

install_ldap_schema() {
  # Install ONE ldap schema at a TIME in the LDAP database
  local this_schema=$1
  # try to find the server URL if not given in the environment
  if [ -f  "$FD_CONFIG_FILE" ] && [ "$OPENLDAP_URL" == 'ldap://localhost:389' ]; then
    OPENLDAP_URL=$(fd_config_find_ldap_url "$FD_CONFIG_FILE")
  elif [ "$OPENLDAP_URL" == 'ldap://localhost:389' ]; then
    echo -e "ERROR: Unable to find the remote LDAP server !\nPlease Provide a Configuration file ($FD_CONFIG_FILE) or a value for 'OPENLDAP_URL' !"
    return 1
  fi
  #requires credentials to be able to connect to cn=config on the ldap database
  if [[ ( -z "$LDAP_CONFIG_USER" ) || ( -z "$LDAP_CONFIG_PWD" ) ]]; then
    echo -e "ERROR: Unable connect to the remote LDAP server configuration zone !\nPlease Provide cn=config credentials (LDAP_CONFIG_PWD & LDAP_CONFIG_USER) !"
    return 1
  fi
  #echo fusiondirectory-insert-schema -o \"-H "$(fd_config_find_value $FD_CONFIG_FILE 'URI')" -x -D \'$LDAP_CONFIG_USER\' -w $LDAP_CONFIG_PWD\" ${my_schemas[*]}
  while read -r logging; do
    # hide the password that might be shown by the command logs.
    if [ -n "$LDAP_CONFIG_PWD" ]; then
  #  shellcheck disable=SC2001
      echo "$logging" | sed "s/$LDAP_CONFIG_PWD/<HIDDEN>/g"
    else
      echo "$logging"
    fi
  done < <(fusiondirectory-insert-schema -o "-H $OPENLDAP_URL -x -D $LDAP_CONFIG_USER -w $LDAP_CONFIG_PWD"  -i "$this_schema")
}

install_plugin_schemas() {
  # expect a folder
  local my_plugin_folder=$1 guess_my_name
  guess_my_name=${my_plugin_folder##*/}
  local log_file=/tmp/installed_plugins_schemas.log
  [ ! -f "$log_file" ] && touch $log_file
  # skip an already installed schema (plugin by plugin)
  if grep -q "$guess_my_name" "$log_file"; then
    return 0
  fi
  # check the plugin's folder is here
  [ ! -d "$my_plugin_folder" ] && echo "ERROR: $my_plugin_folder doesn't exist." && return 1
  schemas_list=($(find "$my_plugin_folder" -type f -name '*.schema' ))
  # check if any schema has to be installed
  if [ -z "${schemas_list[*]}" ] ; then
    echo -e "No schema found for package $guess_my_name.\ncontinuing..."
  else
    # given the legacy fusion directory wiki, schemas are kinda installed this way:
    # non FD schema are installed first
    # then come FD-CONF schemas
    # then come FD schemas
    local non_fd=($(find "$my_plugin_folder" -type f -name '*.schema' | grep -v '\-fd' ))
    local fd_conf=($(find "$my_plugin_folder" -type f -name '*.schema' | grep '\-fd-conf' ))
    local fd=($(find "$my_plugin_folder" -type f -name '*.schema' | grep '\-fd' ))
    for this_schema in ${non_fd[*]}; do
      install_ldap_schema "$this_schema"
    done
    for this_schema in ${fd_conf[*]}; do
      install_ldap_schema "$this_schema"
    done
    for this_schema in ${fd[*]}; do
      install_ldap_schema "$this_schema"
    done
  fi
  # finalising
  echo "$guess_my_name" >> "$log_file"
  return 0
}

install_fd_plugin_tar() {
  # install ONE plugin archive by provided to the fusiondirectory-setup command
  # (as the tar gz archive main contain more than one plugin )
  local my_plugin=$1
  local my_plugin_archive
  my_plugin_archive=$(find "$FD_PLUGINS_DIR" -name "${my_plugin}.tar.gz")
  # check for error: user may have added a wrong plugin name
  if [ -z "$my_plugin_archive" ]; then
    echo "ERROR : requested Fusion Directory plugin '$my_plugin' not found in list of available plugins."
    return 2
  fi
  echo "INFO: Installing Fusion Directory plugin '$my_plugin'..."
  if [ "$FD_SERVICE" == 'yes' ]; then
    fusiondirectory-setup --install-plugins <<<"$my_plugin_archive"
    # Note: le function leave all temporary files in /tmp. this can be reused
  else
    tar -xzf "${my_plugin_archive}" -C /tmp/
  fi
  # check if the user requires schema installation
  if [ "$INSTALL_SCHEMAS" == "yes" ]; then
    # at this stage schema file are expected to be in $FD_HOME/contrib/openldap/
    # BUT we still rely on the archive to list all provided schemas 
    # first: get the list of plugins stored in the archive
    archive_plugin_list=($(tar tf "$my_plugin_archive" | cut -d / -f2 | sort -u))
    # remove the "main" plugin from the list as its name is known and will be installed last
    archive_plugin_list=(${archive_plugin_list[*]/$my_plugin/})
    # install the systems plugin first if present as it is a very common dependency for all other plugins
    if [[ "${archive_plugin_list[*]}" == *"systems"* ]] ; then
      install_plugin_schemas "/tmp/$my_plugin/systems"
    fi
    # remove systems from the list as it is done
    archive_plugin_list=(${archive_plugin_list[*]/systems/})
    # install the rest of dependant plugins (hopefully this works...)
    for depend_plugin in ${archive_plugin_list[*]}; do
      install_plugin_schemas "/tmp/$my_plugin/$depend_plugin"
    done
    # finally install the main plugin
    install_plugin_schemas "/tmp/$my_plugin/$my_plugin"
  else 
    echo "INFO: Plugin $my_plugin is now installed. You may want to install the ldap schemas in your Ldap database."
  fi
  rm -rf "/tmp/${my_plugin:-fake}"
}

# # # # # # # # #
# MAIN  ROUTINE #
# # # # # # # # #

# if [ "$INSTALL_SCHEMAS" == "yes" ]; then
#   for coreSchema in "core-fd.schema" "core-fd-conf.schema" "ldapns.schema" "template-fd.schema"; do
#     install_ldap_schema "/etc/ldap/schema/fusiondirectory/$coreSchema"
#   done
# fi
# if [ -n "$FD_PLUGINS" ];then
# for item in $FD_PLUGINS; do
#   install_fd_plugin_tar "$item"
# done
# fi

while  [ "$#" -ne 0 ]; do
  case $1 in
  run)  for item in $FD_PLUGINS; do
          install_fd_plugin_tar "$item"
        done
        enable_a2_security
        run_fusiondirectory
        break;;
  init) shift;
        export INSTALL_SCHEMAS='yes'
        export FD_SERVICE='no'
        if [ -z "$LDAP_CONFIG_PWD" ] || [ -z "$LDAP_CONFIG_USER" ] || [ -z "$OPENLDAP_URL" ] ; then
        echo -e "ERROR: You have asked to install ldap schemas from Fusion Directory plugins to your ldap database
        But haven't provided the full credentials of the cn=config admin user
        You can provide environment variables or secrets:
        OPENLDAP_URL
        LDAP_CONFIG_USER
        LDAP_CONFIG_PWD (can be a path to a file)
        "
        fi
        for coreSchema in "core-fd.schema" "core-fd-conf.schema" "ldapns.schema" "template-fd.schema"; do
          install_ldap_schema "/etc/ldap/schema/fusiondirectory/$coreSchema"
        done;;
  plugins) shift;
           for item in $FD_PLUGINS; do
             install_fd_plugin_tar "$item"
           done;;
  list_plugins) listOfPlugins=$(find "$FD_PLUGINS_DIR" -name "*.tar.gz" |sed "s|$FD_PLUGINS_DIR/\(.*\)\.tar\.gz$|\1, |g" | sort)
              echo "Available plugins in the image:"
              echo "$listOfPlugins"
              break ;;
  *) exec "$@"
     break ;;
  esac
  
done
