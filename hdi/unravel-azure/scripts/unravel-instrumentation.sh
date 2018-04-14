#! /bin/bash

################################################################################################
# Unravel for HDInsight Bootstrap Script                                                       #
#                                                                                              #
# The bootstrap script log is located at /tmp/unravel                                          #
################################################################################################

[ -z "$TMP_DIR" ] && export TMP_DIR=/tmp/unravel
if [ ! -d $TMP_DIR ]; then
    mkdir -p $TMP_DIR
    chmod a+rw $TMP_DIR
fi

SCRIPT_PATH="/usr/local/unravel/hdi_onpremises_setup.py"
echo "Unravel Instrumentation script: $SCRIPT_PATH"
echo -e "\nRunning Setup Script in the background\n"
echo -e "\nCheck log files in /tmp/unravel/hdi_onpremises_setup.*\n"

if [ $# -eq 1 ] && [ "$1" = "uninstall" ];then
   echo -e "\nUninstall Unravel\n"
   python /usr/local/unravel/hdi_onpremises_setup.py -uninstall 2>&1
else
   echo -e "\nInstall Unravel\n"
   nohup python /usr/local/unravel/hdi_onpremises_setup.py > $TMP_DIR/hdi_onpremises_setup.log 2>$TMP_DIR/hdi_onpremises_setup.err &
fi
