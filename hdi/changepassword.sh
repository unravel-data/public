#! /bin/bash
USER=$1
PASS=$2
usermod --password $(echo $PASS | openssl passwd -1 -stdin) $USER
