# docker FusionDirectory 1.3

WIP:

## first installation:
### Install LDAP schemas on the ldap server.
and add optionals schemas provided by plugins if FD_PLUGINS is specified.  
__this is the only moment where cn=config parameters are needed__
```shell
docker run -ti --rm -e OPENLDAP_URL=ldap://aMasterServer -e LDAP_CONFIG_PWD='supersecret' -e FD_PLUGINS="mail alias dns dhcp" fusion-directory:1.3 init plugins
```
recommended: uses docker secrets because  environment variables are in clear text when the container is inspected.

### Run the one time interactive FusionDirectory setup
1. Start the container without configuration:
    ```shell
    docker run -d -p 80:80 --ulimit nofile=8192:8192 fusion-directory:1.3
    ```
2. when asked to add the admin token in a file, encapsulate the given command into docker exec:
    ```shell
    docker exec -t {{container_id}} sh -c 'echo -n exampleOnetimeToken > /var/cache/fusiondirectory/fusiondirectory.auth'
    ```
3. Finish the setup and download the configuration file.
4. stop/remove the running fusiondirectory service


### deploy the final service with configuration:
```shell
docker run -d -p 80:80 --ulimit nofile=8192:8192 -e FD_PLUGINS="mail alias dns dhcp" -v "/home/docker_host/fd_config/fusiondirectory.conf:/etc/fusiondirectory/fusiondirectory.conf" fusion-directory:1.3
```

Enjoy !

Aalaesar.