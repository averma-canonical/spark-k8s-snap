#!/bin/bash
set -e

echo "Alias $1"
echo "Certificate path $2"

${SNAP}/usr/lib/jvm/java-11-openjdk-amd64/bin/keytool -import -v -alias "$1" -file "$2"  -storepass changeit -noprompt -keystore ${SNAP_DATA}/etc/ssl/certs/java/cacerts
echo "Certificate imported!"