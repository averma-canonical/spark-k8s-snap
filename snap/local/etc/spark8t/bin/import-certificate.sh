#!/bin/bash
set -x

alias=$1
path=$2

if [[ $alias && $path ]]
then
    echo "Alias $1"
    echo "Certificate path $2"

    ${SNAP}/usr/lib/jvm/java-17-openjdk-amd64/bin/keytool -import -v -alias "$1" -file "$2"  -storepass changeit -noprompt -keystore ${SNAP_DATA}/etc/ssl/certs/java/cacerts
    echo "Certificate imported!"
    
    echo "List inserted cert:"
    ${SNAP}/usr/lib/jvm/java-17-openjdk-amd64/bin/keytool -list -keystore ${SNAP_DATA}/etc/ssl/certs/java/cacerts -alias "$1"


else
    echo "Missing alias or path!"
fi
set +x