#!/usr/bin/env bash
set -efx -o pipefail

# the fully-configured conf file, including 'addns'-created entries 
RUNTIME_CONF_FILE=/usr/local/netscaler/log.conf
if [ -z ${CONF_FILE_CONTENTS+x} ]; # if env var is unset
then
    echo Initializing with contents of $CONF_FILE file...
    cp --force $CONF_FILE $RUNTIME_CONF_FILE
else
    echo Initializing with contents of CONF_FILE_CONTENTS env var...
    echo -n "$CONF_FILE_CONTENTS" > $RUNTIME_CONF_FILE
fi

for i in ${NS_IPS//,/ } # iterate over ips, adding to runtime conf file
do
expect <<- EOF
    spawn $NSWL -addns -f $RUNTIME_CONF_FILE
    expect "NSIP:"
    send "$i\r"
    expect "userid:"
    send "$::env(NS_USERID)\r"
    expect "password:"
    send "$::env(NS_PASSWORD)\r"
    expect "Done !!"
EOF
done

exec $NSWL -start -f $RUNTIME_CONF_FILE
