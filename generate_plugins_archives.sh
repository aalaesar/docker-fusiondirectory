#!/bin/bash
## This script is a hack ! :-(
# it create a bunch of tar.gz archives to manage plugin installation and dependencies
# as there is no a clear/efficient way to find if a plugin depends of another plugins
# without a good knowledge of fusion directory itself.
# so the script depend on an already prepared source of dependencies :
# the offical fusiondirectory repository list
set -e
external_source='https://repos.fusiondirectory.org/fusiondirectory-releases/fusiondirectory-1.2.3/debian-stretch/dists/stable/main/binary-amd64/Packages'
# downloading the external source
rm -f /tmp/Packages && wget -q $external_source -P /tmp/
# list of available plugins folders:
# One big oneliner: search directory type only,
# without the current directory, exclude hidden folders
# and do not print de full path
# shellcheck disable=SC2086
available_plugins=($(find /opt/fusiondirectory-plugins-${FD_VERSION}/ -maxdepth 1 -mindepth 1 -not -path '*/\.*' -type d -printf '%f\n'))
#target_source='/opt/fd_plugins_deps.txt'
# trying my best to parse the packages list, creating a dictionnary
# of course it expect the Packages file to have the correct data structure =>
# a 'Depends' line comme ALWAYS after a 'Package' line
declare -A fd_plugins_deps
while read -r my_line; do
    # if this is a package definition line :
    if echo "$my_line" | grep -Eq "^Package:"; then
      # exclude packages schema or not plugins
      if [[ "$my_line" != *"schema"* ]]&&[[ "$my_line" == *"plugin"* ]]; then
        # get the package name without the plugin prefix
        my_package=$(sed 's/plugin-//g' <<<"$my_line" | awk '{print $2}')
        # lastly, check if the package is in the list of available plugins, else forget it
        [[ "${available_plugins[*]}" != *"$my_package"* ]] && unset my_package
      fi
    # if this is a dependency list
    elif echo "$my_line" | grep -Eq "^Depends:"; then
      # only parse it if we have a "good" package name in memory
      if [ -n "$my_package" ]; then
        # get the dependency list, remove commas and the 'fusiondirectory' mandatory package
        # keep the 'plugin-' prefix for now
        my_deps=($(sed -E 's/fusiondirectory|,//g' <<<"$my_line" | awk '{$1=""; print $0}'))
        my_depends=()
        # remove non plugin packages (aka regular system packages) from dependency list
        for depend in ${my_deps[*]}; do
          # only add package starting with the prefix (also remove the prefix at this stage)
          [[ "$depend" == "plugin-"* ]] && my_depends+=(${depend/plugin-/})
        done
        fd_plugins_deps["$my_package"]="${my_depends[*]}"
        # forget everything and start over
        unset my_package my_deps my_depends
      fi
    fi
# filter out most of the file content and prepare the data.
# keep only Packages name and depends fields.
# remove version numbers and the 'fusiondirectory-' prefix
# then Feed it to the loop
done < <(grep -E '^Package:|^Depends:' /tmp/Packages| sed -E 's/\(= 1.2.3-[1-9]\)//g' | sed 's/fusiondirectory-//g')
rm -f /tmp/Packages

# Generate the tar.gz archives for plugin installation
# there is one archive per plugin along with all the plugins it depends on
# so every plugin can be installed independantly
#   this rely on the 'fusiondirectory-setup --install-plugins'
#   who gladdy overwrites existing plugins when they are installed multiple times

# use a recursive function to create a multi level raw list of dependencies 
# it still needs to be sorted and filtered for uniq entries.
function req_print_depends_list() {
  # the plugin doesn't print itself as depency as it would break the recursive function.
  # use echo -n to get a nice oneline result 
  true
  local my_depends=()
  local my_plugin=$1
  # exit case 
  if [ -z "${fd_plugins_deps[$my_plugin]}" ]; then
    echo -n ""
    return 0
  else
    for my_dep in ${fd_plugins_deps[$my_plugin]}; do
      echo -n "$my_dep $(req_print_depends_list "$my_dep")"
    done
  fi
}

# ensure the destination folder exists
mkdir -p "$FD_PLUGINS_DIR"
# creates all the plugin archives:
for the_plugin in ${!fd_plugins_deps[*]}; do
  the_depends_list=($(req_print_depends_list "$the_plugin" | tr " " "\n" | sort -u))
  # shellcheck disable=SC2086
  tar --create --gzip --file "$FD_PLUGINS_DIR/${the_plugin}.tar.gz" --directory=/opt/fusiondirectory-plugins-${FD_VERSION} "$the_plugin" ${the_depends_list[*]}
done
exit 0