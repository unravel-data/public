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
CLUSTER_NAME=$(curl -u $AMBARI_USER:"$AMBARI_PASS" http://headnodehost:8080/api/v1/clusters 2>/dev/null | python -c "import json,sys; print(json.load(sys.stdin)['items'][0]['Clusters']['cluster_name'])")
UNRAVEL_PROP='/usr/local/unravel/etc/unravel.properties'
CLUSTER_TYPE='spark'
echo "Unravel Instrumentation script: $SCRIPT_PATH"

function getProp() {
  PROP_NAME=$1
  CONF_NAME=$2
  /var/lib/ambari-server/resources/scripts/configs.py -a get -n $CLUSTER_NAME -u $AMBARI_USER -p "$AMBARI_PASS" -c $CONF_NAME --host=headnodehost -f /tmp/unravel/$CONF_NAME 2>/dev/null
  PROP_VAL=$(python -c "import sys, json; print(json.load(open('/tmp/unravel/$CONF_NAME'))['properties']['$PROP_NAME'])")
}

function getBrokerList() {
    cat <<EOF > "/tmp/unravel/parse_brokers.py"
import json,sys
broker_list, bt_server, jmx_servers = list(), list(), list()
broker_items = json.load(sys.stdin)['items']
for item in broker_items:
  broker_list.append(item['HostRoles']['host_name'])
  bt_server.append("{0}:{1}".format(item['HostRoles']['host_name'], '$SERVER_PORT'))
print('com.unraveldata.ext.kafka.$CLUSTER_NAME.bootstrap_servers={0}'.format(','.join(bt_server)))
print('com.unraveldata.ext.kafka.$CLUSTER_NAME.jmx_servers={0}'.format(','.join(broker_list)))
for index, host in enumerate(broker_list):
  print('com.unraveldata.ext.kafka.$CLUSTER_NAME.jmx.{0}.host={1}'.format(broker_list[index], host))
  print('com.unraveldata.ext.kafka.$CLUSTER_NAME.jmx.{0}.port=$JMX_PORT'.format(broker_list[index]))
EOF
    RESULT=$(curl -u "$AMBARI_USER":"$AMBARI_PASS" "http://headnodehost:8080/api/v1/clusters/$CLUSTER_NAME/host_components?HostRoles/component_name=KAFKA_BROKER" 2>/dev/null | python /tmp/unravel/parse_brokers.py)
}

# Kafka configurations
getProp listeners kafka-broker
SERVER_PORT=$(echo $PROP_VAL | awk -F':' '{print $3}')
getProp content kafka-env
JMX_PORT=$(echo $PROP_VAL | grep -o 'JMX_PORT=${.*}\s' | awk -F'[-}]' '{print $2}')
if [[ -n $SERVER_PORT ]] && [[ -n $JMX_PORT ]]; then
  CLUSTER_TYPE='kafka'
  echo "Adding Kafka configurations..."
  echo "com.unraveldata.ext.kafka.clusters=$CLUSTER_NAME" >> $UNRAVEL_PROP
  getBrokerList
  echo "$RESULT" >> $UNRAVEL_PROP
fi

# Hbase configurations
getProp content hbase-env
if [ $? -eq 0 ]; then
  CLUSTER_TYPE='hbase'
  echo "Adding Hbase configurations..."
  echo "com.unraveldata.hbase.source.type=AMBARI" >> $UNRAVEL_PROP
  echo "com.unraveldata.hbase.rest.url=http://headnodehost:8080" >> $UNRAVEL_PROP
  echo "com.unraveldata.hbase.rest.user=$AMBARI_USER" >> $UNRAVEL_PROP
  echo "com.unraveldata.hbase.rest.pwd=$AMBARI_PASS" >> $UNRAVEL_PROP
  echo "com.unraveldata.hbase.clusters=$CLUSTER_NAME" >> $UNRAVEL_PROP
fi

if [ $# -eq 1 ] && [ "$1" = "uninstall" ];then
   echo -e "\nUninstall Unravel\n"
   python $SCRIPT_PATH --ambari-server headnodehost --ambari-user $AMBARI_USER --ambari-password $AMBARI_PASS --spark-version $SPARK_VER -uninstall --restart-am
else
   echo -e "\nInstall Unravel\n"
   if [ $CLUSTER_TYPE == 'spark' ] || [ $CLUSTER_TYPE == 'hbase' ];then
     echo "Running configs script"
    python $SCRIPT_PATH --ambari-server headnodehost --ambari-user $AMBARI_USER --ambari-password $AMBARI_PASS --spark-version $SPARK_VER --restart-am
   fi
#   /usr/local/unravel/init_scripts/unravel_all.sh restart
   exit 0
fi