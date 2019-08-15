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
SENSOR_FILE_NAME="unravel-sensor-4530.tar.gz"
SENSOR_FILE_URL="https://unravelstorage01.blob.core.windows.net/unravel-app-blob-2018-04-13/$SENSOR_FILE_NAME"

echo -e "\nDownloading $SENSOR_FILE_NAME\n"
wget -O $TMP_DIR/$SENSOR_FILE_NAME $SENSOR_FILE_URL

if [ $? -eq 0 ];then
    echo -e "\n$SENSOR_FILE_NAME Downloaded\n"
else
    echo -e "\n$SENSOR_FILE_NAME download failed\n"
    exit 1
fi

echo -e "\nExtracting $SENSOR_FILE_NAME\n"
tar -zxvf $TMP_DIR/$SENSOR_FILE_NAME -C $SENSOR_DIR/

if [ -d $SENSOR_DIR/unravel-agent ] && [ -d $SENSOR_DIR/unravel_client ]; then
    echo -e "\nDeploy Sensor successed\n"
else
    echo -e "\nDeploy Sensor Failed\n"
    exit 1
fi
