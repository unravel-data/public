#! /bin/bash

################################################################################################
# Unravel 4.3, 4.4, and 4.5 for HDInsight Bootstrap Script                                     #
#                                                                                              #
# The bootstrap script log is located at /media/ephemeral0/logs/others/node_bootstrap.log      #
################################################################################################

[ ! -z "$VERBOSE" ] && set -x


# Unravel Integration - common functionality

# Environment defaults
export HADOOP_VER_XYZ_DEFAULT=2.4.0
export SPARK_VER_XYZ_DEFAULT=1.5.1
export AGENT_DST=/usr/local/unravel-agent
export AGENT_DST_OWNER=root:root
export AGENT_JARS=$AGENT_DST/jars

[ -z "$TMP_DIR" ] && export TMP_DIR=/tmp/unravel
if [ ! -d $TMP_DIR ]; then
    mkdir -p $TMP_DIR
    chmod a+rw $TMP_DIR
fi

###############################################################################################
# Sets up the script log file if not already set                                              #
#                                                                                             #
# Provides:                                                                                   #
#  - OUT_FILE                                                                                 #
# Accepts:                                                                                    #
#  - OUT_FILE                                                                                 #
###############################################################################################
function set_out_file() {
    if [ -z "$OUT_FILE" ]; then
        export OUT_FILE=${TMP_DIR}/$(basename $0).out
        /bin/rm -f  ${OUT_FILE}
        touch ${OUT_FILE}
    fi
}

###############################################################################################
# Sets up the unravel temp prop file if not already set                                       #
#                                                                                             #
# Provides:                                                                                   #
#  - OUT_PROP_FILE                                                                                 #
# Accepts:                                                                                    #
#  - OUT_PROP_FILE                                                                                 #
###############################################################################################
function set_temp_prop_file() {
    if [ -z "$OUT_PROP_FILE" ]; then
        export OUT_PROP_FILE=${TMP_DIR}/unravel.ext.properties
        /bin/rm -f  ${OUT_PROP_FILE}
        touch ${OUT_PROP_FILE}
    fi
}

###############################################################################################
# Generates debug output of the environment and bash settings                                 #
#                                                                                             #
# Requires:                                                                                   #
#  - TMP_DIR                                                                                  #
###############################################################################################
function debug_dump() {
    env > ${TMP_DIR}/$(basename $0).env
    set > ${TMP_DIR}/$(basename $0).set
}

###############################################################################################
# Turns on ALLOW_ERRORS                                                                       #
#  - if ALLOW_ERRORS is set (non-empty), then generate non-zero retcodes for failures         #
#                                                                                             #
# Provides:                                                                                   #
#  - ALLOW_ERRORS                                                                             #
###############################################################################################
function allow_errors() {
    export ALLOW_ERRORS=true
}

###############################################################################################
# Sleep for the given number of seconds and render one dot each second                        #
#                                                                                             #
# Requires:                                                                                   #
#  - $1 : the number of seconds to sleep                                                      #
###############################################################################################
sleep_with_dots() {
    local sleep_secs=$1
    while [ $sleep_secs -gt 0 ]; do
      sleep 1
      echo -n "."
      let sleep_secs=${sleep_secs}-1
    done
}

###############################################################################################
# Verify connectivity to Unravel server                                                       #
#                                                                                             #
# Requires:                                                                                   #
#  - UNRAVEL_SERVER                                                                           #
# Accepts:                                                                                    #
#  - ALLOW_ERRORS                                                                             #
###############################################################################################
function check_connectivity() {
    echo "Getting Unravel version to check connectivity..." | tee -a ${OUT_FILE}
    curl http://${UNRAVEL_SERVER}/version.txt >> ${OUT_FILE}
    RT=$?
    echo $RT
    if [ $RT -ne 0 ]; then
        echo "Unable to contact Unravel at ${UNRAVEL_SERVER}" | tee -a ${OUT_FILE}
        [ "$ALLOW_ERRORS" ]  &&  exit 1
        exit 0
    fi
}

###############################################################################################
# Constructs the Unravel REST server name                                                     #
#                                                                                             #
# Requires:                                                                                   #
#  - UNRAVEL_SERVER                                                                           #
# Provides:                                                                                   #
#  - UNRAVEL_HOST                                                                             #
#  - UNRAVEL_RESTSERVER_HOST_AND_PORT                                                         #
# Accepts:                                                                                    #
#  - LRHOST                                                                                   #
###############################################################################################
function setup_restserver() {
  if [ -z "$UNRAVEL_RESTSERVER_HOST_AND_PORT" ]; then
    if [ -z "$LRHOST" ]; then
      export UNRAVEL_HOST="${UNRAVEL_SERVER%%:*}"

      # UNRAVEL_RESTSERVER_HOST_AND_PORT is the host and port of the REST SERVER
      local UNRAVEL_RESTSERVER_PORT=4043
      export UNRAVEL_RESTSERVER_HOST_AND_PORT="${UNRAVEL_HOST}:${UNRAVEL_RESTSERVER_PORT}"
    else
      export UNRAVEL_RESTSERVER_HOST_AND_PORT="${LRHOST}"
    fi
  fi

  if is_lr_reachable; then
    echo "Using Unravel REST Server at $UNRAVEL_RESTSERVER_HOST_AND_PORT" | tee -a ${OUT_FILE}
  else
    echo "ERROR: Unravel REST Server at $UNRAVEL_RESTSERVER_HOST_AND_PORT is not available. Aborting install" | tee -a ${OUT_FILE}
    exit 1
  fi
}

###############################################################################################
# Interactive reads the Unravel server setup                                                 #
#                                                                                             #
# Provides:                                                                                   #
#  - UNRAVEL_SERVER                                                                           #
###############################################################################################
function read_unravel_server() {
    read -p "Unravel server IP address': " UNRAVEL_SERVER
    read -p "Unravel server port [3000]: " UNRAVEL_SERVER_PORT
    if [ -z "$UNRAVEL_SERVER_PORT" ]; then
        export UNRAVEL_SERVER=$UNRAVEL_SERVER:3000
    else
        export UNRAVEL_SERVER=$UNRAVEL_SERVER:$UNRAVEL_SERVER_PORT
    fi
}


function isFunction() {
    declare -Ff "$1" >/dev/null;
}

###############################################################################################
# Checks whether Unravel LR server is reachable                                               #
#                                                                                             #
# Requires:                                                                                   #
#  - UNRAVEL_RESTSERVER_HOST_AND_PORT                                                                             #
###############################################################################################
function is_lr_reachable() {
  echo "curl ${UNRAVEL_RESTSERVER_HOST_AND_PORT}/isalive 1>/dev/null 2>/dev/null" | tee -a ${OUT_FILE}
  curl ${UNRAVEL_RESTSERVER_HOST_AND_PORT}/isalive 1>/dev/null 2>/dev/null
  RET=$?
  echo "CURL RET: $RET" | tee -a ${OUT_FILE}

  return $RET
}

set_out_file
set_temp_prop_file



# Can be overriden by the implementation scripts in 'hivehook_env_setup' function
# Also, can be provided at the top level bootstrap or setup script
[ -z "$HIVE_VER_XYZ_DEFAULT" ] && export HIVE_VER_XYZ_DEFAULT=1.2.0



if [ -z "$UNRAVEL_ES_USER" ]; then
  export UNRAVEL_ES_USER=hdfs
fi

if [ -z "$UNRAVEL_ES_GROUP" ]; then
  export UNRAVEL_ES_GROUP=$UNRAVEL_ES_USER
fi




# Can be overridden by the implementation scripts in 'spark_env_setup' function
# Also, can be provided at the top level bootstrap or setup script
[ -z "$SPARK_VER_XYZ_DEFAULT" ] && export SPARK_VER_XYZ_DEFAULT=1.6.0





function append_to_zeppelin(){
    if [ ! -z "$ZEPPELIN_CONF_DIR" ]; then
        echo "Appending configuration to zeppelin-env.sh" | tee -a ${OUT_FILE}

        local ZEPPELIN_ENV=$ZEPPELIN_CONF_DIR/zeppelin-env.sh

        sudo cp $ZEPPELIN_ENV $ZEPPELIN_CONF_DIR/zeppelin-env.sh.pre_unravel

        sudo echo "# Note1: The setting below is a modified version of what we add for" >>$ZEPPELIN_ENV
        sudo echo "#  spark.driver.extraJavaOptions. Instead of using SPARK_SUBMIT_OPTIONS which " >>$ZEPPELIN_ENV
        sudo echo "# does not support -D system properties, we will use ZEPPELIN_JAVA_OPTS " >>$ZEPPELIN_ENV
        sudo echo "export ZEPPELIN_JAVA_OPTS=\"$DRIVER_AGENT_ARGS\"" >>$ZEPPELIN_ENV
    else
        echo "ZEPPELIN_CONF_DIR not configured. Skipping Zeppelin integration" | tee -a ${OUT_FILE}
    fi
}

function restore_zeppelin() {
    if [ ! -z "$ZEPPELIN_CONF_DIR" ]; then
        echo "Restoring original zeppelin-env.sh" | tee -a ${OUT_FILE}
        # undo changes to Zeppelin's env file
        sudo mv $ZEPPELIN_CONF_DIR/zeppelin-env.sh.pre_unravel $ZEPPELIN_CONF_DIR/zeppelin-env.sh
    else
        echo "ZEPPELIN_CONF_DIR not configured. Unable to restore zeppelin-env.sh" | tee -a ${OUT_FILE}
    fi
}





# Unravel integration installation support

function install_usage() {
    echo "Usage: $(basename ${BASH_SOURCE[0]}) install <options>" | tee -a ${OUT_FILE}
    echo "Supported options:" | tee -a ${OUT_FILE}
    echo "  -y                 unattended install" | tee -a ${OUT_FILE}
    echo "  -v                 verbose mode" | tee -a ${OUT_FILE}
    echo "  -h                 usage" | tee -a ${OUT_FILE}
    echo "  --unravel-server   unravel_host:port (required)" | tee -a ${OUT_FILE}
    echo "  --unravel-receiver unravel_restserver:port" | tee -a ${OUT_FILE}
}




function install() {
    if [ 0 -eq $# ]; then
        install_usage
        exit 0
    fi

    # parse arguments
    while [ "$1" ]; do
        opt=$1
        shift
        case $opt in
            -y )
                export UNATTENDED=yes ;;
            -n )
                export DRYRUN=yes ;;
            -v )
                set -x ;;
            -h )
                install_usage
                exit 0
                ;;
            "unravel-server" | "--unravel-server" )
                UNRAVEL_SERVER=$1
                [[ $UNRAVEL_SERVER != *":"* ]] && UNRAVEL_SERVER=${UNRAVEL_SERVER}:3000
                export UNRAVEL_SERVER
                shift
                ;;
            "unravel-receiver" | "--unravel-receiver" )
                LRHOST=$1
                [[ $LRHOST != *":"* ]] && LRHOST=${LRHOST}:4043
                export LRHOST
                shift
                ;;
            
            * )
                echo "Invalid option $opt" | tee -a ${OUT_FILE}
                install_usage
                exit 1
                ;;
        esac
    done

    # detect the cluster and settings
    isFunction cluster_detect && cluster_detect

    # dump the contents of env variables and shell settings
    debug_dump

    if [ -z "$UNATTENDED" ]; then
        echo
        echo "================================="
        echo "Unravel setup for $PLATFORM clusters"
        echo "================================="
        echo "This script will prepare $PLATFORM cluster for integration with the Unravel stack"
        read -p "Press Enter to continue or Ctrl-C to abort: "
    fi

    if [ -z "$UNRAVEL_SERVER" ]; then
        # try and resolve unravel server
        if [ -z "$UNATTENDED" ]; then
            # read unravel server interactively
            read_unravel_server
        else
            # no interactive input in unattended mode
            echo "Missing unravel server. Cancelling." | tee -a ${OUT_FILE}
            [ $ALLOW_ERRORS ] && exit 1
            exit 0
        fi
    fi

    # make sure all child processes will see the updated value
    export UNRAVEL_SERVER
    echo "> Unravel server: $UNRAVEL_SERVER" | tee -a ${OUT_FILE}

    check_connectivity
    setup_restserver

}


PLATFORM="HDI"

echo "AMBARI_PORT before: ${AMBARI_PORT}"

[ -z "$AMBARI_HOST" ] && export AMBARI_HOST=headnodehost
[ -z "$AMBARI_PORT" ] && export AMBARI_PORT=8080

echo "AMBARI_PORT after: ${AMBARI_PORT}"

AMBARICONFIGS_SH=/var/lib/ambari-server/resources/scripts/configs.sh

###############################################################################################
# Will stop service via Ambari API                                                            #
#  - args: service name                                                                       #
# Requires:                                                                                   #
#  - CLUSTER_ID                                                                               #
#  - AMBARI_USR                                                                               #
#  - AMBARI_PWD                                                                               #
#  - AMBARI_HOST                                                                              #
#  - AMBARI_PORT                                                                              #
###############################################################################################
function stopServiceViaRest() {
    if [ -z "$1" ]; then
        echo "Need service name to start service" | tee -a ${OUT_FILE}
        [ $ALLOW_ERRORS ] && exit 1
    fi
    SERVICENAME=$1
    echo "Stopping $SERVICENAME" | tee -a ${OUT_FILE}
    echo "AMBARI_PORT=$AMBARI_PORT" | tee -a ${OUT_FILE}
    curl -u $AMBARI_USR:$AMBARI_PWD -i -H 'X-Requested-By: ambari' -X PUT -d "{\"RequestInfo\": {\"context\" :\"Unravel request: Stop Service $SERVICENAME\"}, \"Body\": {\"ServiceInfo\": {\"state\": \"INSTALLED\"}}}" http://${AMBARI_HOST}:${AMBARI_PORT}/api/v1/clusters/${CLUSTER_ID}/services/${SERVICENAME}
}

###############################################################################################
# Will start service via Ambari API                                                           #
#  - args: service name                                                                       #
# Requires:                                                                                   #
#  - CLUSTER_ID                                                                               #
#  - AMBARI_USR                                                                               #
#  - AMBARI_PWD                                                                               #
#  - AMBARI_HOST                                                                              #
#  - AMBARI_PORT                                                                              #
###############################################################################################
function startServiceViaRest() {
    if [ -z "$1" ]; then
        echo "Need service name to start service" | tee -a ${OUT_FILE}
        [ $ALLOW_ERRORS ] && exit 1
    fi
    sleep 2
    SERVICENAME=$1
    echo "Starting $SERVICENAME using a background process." | tee -a ${OUT_FILE}
    nohup bash -c "sleep 90; curl -u $AMBARI_USR:'$AMBARI_PWD' -i -H 'X-Requested-By: ambari' -X PUT -d '{\"RequestInfo\": {\"context\" :\"Unravel request: Start Service $SERVICENAME\"}, \"Body\": {\"ServiceInfo\": {\"state\": \"STARTED\"}}}' http://${AMBARI_HOST}:${AMBARI_PORT}/api/v1/clusters/${CLUSTER_ID}/services/${SERVICENAME}" > /tmp/Start${SERVICENAME}.out 2> /tmp/Start${SERVICENAME}.err < /dev/null &
}

function cluster_detect() {
  # Import the helper method module.
  wget -O /tmp/HDInsightUtilities-v01.sh -q https://hdiconfigactions.blob.core.windows.net/linuxconfigactionmodulev01/HDInsightUtilities-v01.sh && source /tmp/HDInsightUtilities-v01.sh && rm -f /tmp/HDInsightUtilities-v01.sh

  export AMBARI_USR=$(echo -e "import hdinsight_common.Constants as Constants\nprint Constants.AMBARI_WATCHDOG_USERNAME" | python)
  export AMBARI_PWD=$(echo -e "import hdinsight_common.ClusterManifestParser as ClusterManifestParser\nimport hdinsight_common.Constants as Constants\nimport base64\nbase64pwd = ClusterManifestParser.parse_local_manifest().ambari_users.usersmap[Constants.AMBARI_WATCHDOG_USERNAME].password\nprint base64.b64decode(base64pwd)" | python)

  CLUSTER_ID=$(echo -e "import hdinsight_common.ClusterManifestParser as ClusterManifestParser\nprint ClusterManifestParser.parse_local_manifest().deployment.cluster_name" | python)

  local primary_head_node=$(get_primary_headnode)
  local full_host_name=$(hostname -f)

  echo "AMBARI_USR=$AMBARI_USR" | tee -a ${OUT_FILE}
  # DO NOT echo the password since it will show up in the Ambari Custom Commands
  #echo "AMBARI_PWD=$AMBARI_PWD" | tee -a ${OUT_FILE}
  echo "CLUSTER_ID=$CLUSTER_ID" | tee -a ${OUT_FILE}

  HEADIP=`ping -c 1 headnodehost | grep PING | awk '{print $3}' | tr -d '()'`
  echo "Headnode IP: ${HEADIP}"

  AMBARI_URL="https://${CLUSTER_ID}.azurehdinsight.net"
  echo "Cluster Ambari URL: $AMBARI_URL"

  AMBARI_PORT="8080"
  API_URL="http://${HEADIP}:${AMBARI_PORT}/api/v1/clusters/$CLUSTER_ID/services/KAFKA/components/KAFKA_BROKER"
  #API_URL="$AMBARI_URL/api/v1/clusters/$CLUSTER_ID/services/KAFKA/components/KAFKA_BROKER"
  echo "Ambari API for Brokers: $API_URL"

  sudo apt-get -y install jq

  # Example of what the raw data looks like.
  export BROKERS_WITH_PORT=`curl -sS -u $AMBARI_USR:$AMBARI_PWD -G $API_URL | jq -r '["\(.host_components[].HostRoles.host_name):9092"] | join(",")'`

  echo "Raw config value: ${BROKERS_WITH_PORT}"
  ARR_BROKERS_WITH_PORT=(${BROKERS_WITH_PORT//,/ })
  echo "Raw value split by comma: ${ARR_BROKERS_WITH_PORT[@]}"

  # E.g., [FQDN1, FQDN2 ...]
  HOSTNAMES_FQDN=()

  # E.g., [shortname1 shortname2 ...]
  HOSTNAMES_SHORT=()

  # E.g., [FQDN1:9092 FQDN2:9092 ...]
  BOOTSTRAP_SERVERS=()

  # E.g., [broker1 broker2 ...]
  JMX_SERVERS=()
  i=0
  echo "Brokers:"
  for x in "${ARR_BROKERS_WITH_PORT[@]}"
  do
      (( i += 1 ))

      FQDN_NAME=`echo $x | cut -d':' -f1`
      echo "$i.  FQDN: ${FQDN_NAME}"

      HOST_SHORT=`echo $x | cut -d':' -f1 | cut -d'.' -f1`

      BROKER_PORT=`echo $x | cut -d':' -f2`
      echo "$i.  Port: $BROKER_PORT"

      HOSTNAMES_FQDN+=( ${FQDN_NAME} )
      HOSTNAMES_SHORT+=( ${HOST_SHORT} )
      BOOTSTRAP_SERVERS+=( "${FQDN_NAME}:${BROKER_PORT}" )
      JMX_SERVERS+=( "broker$i" )
  done

  echo ""
  echo "FQDNs: ${HOSTNAMES_FQDN[@]}"
  echo "Short hostnames: ${HOSTNAMES_SHORT[@]}"
  echo "Bootstrap servers: ${BOOTSTRAP_SERVERS[@]}"
  echo "JMX servers: ${JMX_SERVERS[@]}"
  echo ""

  # Calculate the unravel property
  props="com.unraveldata.ext.kafka.clusters=${CLUSTER_ID}\n"

  BOOTSTRAP_SERVER_STR=`echo ${BOOTSTRAP_SERVERS[@]} | tr ' ' ','`
  props+="com.unraveldata.ext.kafka.${CLUSTER_ID}.bootstrap_servers=${BOOTSTRAP_SERVER_STR}\n"

  JMX_SERVER_STR=`echo ${JMX_SERVERS[@]} | tr ' ' ','`
  props+="com.unraveldata.ext.kafka.${CLUSTER_ID}.jmx_servers=${JMX_SERVER_STR}\n"

  i=0
  for fqdn in "${HOSTNAMES_FQDN[@]}"
  do
      (( i += 1 ))
      name=( "broker$i" )
      props+="com.unraveldata.ext.kafka.${CLUSTER_ID}.jmx.${name}.host=${fqdn}\n"
      props+="com.unraveldata.ext.kafka.${CLUSTER_ID}.jmx.${name}.port=9999\n"
  done
  echo "Unravel prop (contains \n):"
  echo "$props"
  echo ""
  echo "Appending Kafka properties to /tmp/unravel/unravel.ext.properties"
  echo -e $props | tee -a -${OUT_PROP_FILE}
  echo ""
  echo "********************************************************************************"
  echo "PLEASE ENSURE THAT THE UNRAVEL SERVER CAN PING ALL OF THE HOSTNAMES SHOWN ABOVE."
  echo "If unable to ping, you may have to modify /etc/hosts on the Unravel server.     "
  echo "********************************************************************************"
  echo ""
  echo "EXT KAFKA PROP=$props" | tee -a ${OUT_FILE}
  if [[ "$full_host_name" == "hn0"* ]] && [ ${#BOOTSTRAP_SERVERS[@]} -gt 0 ] ; then
    set_temp_prop_file
    echo -e $props | tee -a ${OUT_PROP_FILE}
    setup_restserver
    if [ -n "${UNRAVEL_RESTSERVER_HOST_AND_PORT}" ]; then
      curl -T ${OUT_PROP_FILE} ${UNRAVEL_RESTSERVER_HOST_AND_PORT}/logs/any/kafka_script_action/kafka_prop/ext_kafka_props 1>/dev/null 2>/dev/null
      RET=$?
      echo "CURL RET: $RET" | tee -a ${OUT_FILE}
    fi
  fi

  if [ "${full_host_name,,}" == "${primary_head_node,,}" ]; then
    HOST_ROLE=master
  else
    if [ 1 -eq $(test_is_zookeepernode) ]; then
      HOST_ROLE=zookeeper
    else
      HOST_ROLE=slave
    fi
  fi
  echo "HOST_ROLE=$HOST_ROLE" | tee -a ${OUT_FILE}
}



# setup env
#export HADOOP_CONF=/etc/hadoop/
# hive conf is managed by Ambari
#export HIVE_CONF_DEST=
#export HIVE_CONF_DEST_OWNER=
#export UNRAVEL_HH_DEST_OWNER="root:root"
#export UNRAVEL_HH_DEST=/usr/local/unravel_client



#export ES_CLUSTER_TYPE_SWITCH=""


################################################################################################
# Resolve Qubole cluster ID                                                                    #
# Provides:                                                                                    #
#  - CLUSTER_ID                                                                                #
#                                                                                              #
################################################################################################
function resolve_cluster_id() {
  echo "Using HDInsight cluster $CLUSTER_ID" | tee -a ${OUT_FILE}
}

export ES_CLUSTER_TYPE_SWITCH="--cluster HDI"



# Unravel integration for HDInsight - Spark support

# setup env
#export SPARK_CONF_DEST=
#export ZEPPELIN_CONF_DIR=
#export UNRAVEL_SPARK_DEST=/usr/local/unravel-agent
#export UNRAVEL_SPARK_DEST_OWNER="root:root"
#export SPARK_SENSOR_JARS=${UNRAVEL_SPARK_DEST}/jars


# dump the contents of env variables and shell settings
debug_dump

# do not make this script errors abort the whole bootstrap
allow_errors

ARGS="-y $*"
echo $ARGS | grep -q '\--unravel-server'
HAS_FLAG=$?
if [ $HAS_FLAG -eq 0 ]; then
 true
elif [[ $* =~ .*?:[0-9]+ ]]; then
 ARGS="-y --unravel-server $*"
fi

[ ! -z "$HIVE_VER_XYZ" ] && ARGS+=" --hive-version $HIVE_VER_XYZ"
[ ! -z "$SPARK_VER_XYZ" ] && ARGS+=" --spark-version $SPARK_VER_XYZ"

install $ARGS
