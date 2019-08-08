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
SCRIPT_PATH="/usr/local/unravel/install_bin/cluster-setup-scripts/unravel_hdp_setup.py"
SPARK_VER=$(spark-submit --version 2>&1 | grep -oP -m 1 '.*?version\s+\K([0-9.]+)')
AMBARI_USER=$(python -c 'import hdinsight_common.Constants as Constants; print(Constants.AMBARI_WATCHDOG_USERNAME)')
AMBARI_PASS=$(python -c 'import hdinsight_common.Constants as Constants, hdinsight_common.ClusterManifestParser as ClusterManifestParser, base64; print(base64.b64decode(ClusterManifestParser.parse_local_manifest().ambari_users.usersmap[Constants.AMBARI_WATCHDOG_USERNAME].password))' 2>/dev/null)
echo "Unravel Instrumentation script: $SCRIPT_PATH"
#echo -e "\nRunning Setup Script in the background\n"
#echo -e "\nCheck log files in /tmp/unravel/hdi_onpremises_setup.*\n"

if [ $# -eq 1 ] && [ "$1" = "uninstall" ];then
   echo -e "\nUninstall Unravel\n"
#   python /usr/local/unravel/hdi_onpremises_setup.py -uninstall 2>&1
   python $SCRIPT_PATH --ambari-server headnodehost --ambari-user $AMBARI_USER --ambari-password $AMBARI_PASS --spark-version $SPARK_VER -uninstall
else
   echo -e "\nInstall Unravel\n"
#   nohup python /usr/local/unravel/hdi_onpremises_setup.py > $TMP_DIR/hdi_onpremises_setup.log 2>$TMP_DIR/hdi_onpremises_setup.err &
   python $SCRIPT_PATH --ambari-server headnodehost --ambari-user $AMBARI_USER --ambari-password $AMBARI_PASS --spark-version $SPARK_VER -uninstall
   /usr/local/unravel/init_scripts/unravel_all.sh restart
fi
