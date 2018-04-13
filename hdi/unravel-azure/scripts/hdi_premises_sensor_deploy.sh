#! /bin/bash

################################################################################################
# Unravel for HDInsight Sensory Deploy Script                                                  #
#                                                                                              #
# The bootstrap script log is located at /tmp/unravel                                          #
################################################################################################
[ -z "$TMP_DIR" ] && export TMP_DIR=/tmp/unravel
if [ ! -d $TMP_DIR ]; then
    mkdir -p $TMP_DIR
    chmod a+rw $TMP_DIR
fi

SENSOR_DIR=/usr/local

SENSOR_FILE_URL="https://unravelstorage01.blob.core.windows.net/unravel-app-blob-2018-04-13/unravel-sensor.tar.gz"

echo -e "\nDownloading unravel-sensor.tar.gz\n"
wget -O $TMP_DIR/unravel-sensor.tar.gz $SENSOR_FILE_URL

if [ $? -eq 0 ];then
    echo -e "\nunravel-sensor.tar.gz Downloaded\n"
else
    echo -e "\nunravel-sensor.tar.gz download failed\n"
    exit 1
fi

echo -e "\nExtracting unravel-sensor.tar.gz\n"
tar -zxvf $TMP_DIR/unravel-sensor.tar.gz -C $SENSOR_DIR/

if [ -d $SENSOR_DIR/unravel-agent ] && [ -d $SENSOR_DIR/unravel_client ]; then
    echo -e "\nDeploy Sensor successed\n"
else
    echo -e "\nDeploy Sensor Failed\n"
    exit 1
fi
