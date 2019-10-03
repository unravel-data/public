#! /bin/bash

################################################################################################
# Unravel 4.5 for HDInsight Bootstrap Script                                                   #                                                     #
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
#        [ "$ALLOW_ERRORS" ]  &&  exit 1
#        exit 0
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

function fetch_sensor_zip() {
    local zip_name="unravel-agent-pack-bin.zip"


    echo "Fetching sensor zip file" | tee -a ${OUT_FILE}
    URL="http://${UNRAVEL_SERVER}/hh/$zip_name"
    if [ ! -z $SENSOR_URL ]; then
        URL=${SENSOR_URL%%/}/$zip_name
    fi
    echo "GET $URL" | tee -a ${OUT_FILE}
    wget -4 -q -T 10 -t 5 -O - $URL > ${TMP_DIR}/$zip_name
    #wget $URL -O ${TMP_DIR}/$SPK_ZIP_NAME
    RC=$?
    echo "RC: " $RC | tee -a ${OUT_FILE}

    # Try to download sensor file from dfs backup if wget failed
    if [ $RC -ne 0 ]; then
        download_from_dfs $zip_name ${TMP_DIR}/$zip_name
        RC=$?
    fi

    if [ $RC -eq 0 ]; then
        upload_to_dfs ${TMP_DIR}/$zip_name
        sudo mkdir -p $AGENT_JARS
        sudo chmod -R 655 ${AGENT_DST}
        sudo chown -R ${AGENT_DST_OWNER} ${AGENT_DST}
        sudo /bin/cp ${TMP_DIR}/$zip_name  $AGENT_DST/
        (cd $AGENT_JARS ; sudo unzip -o ../$zip_name)
    else
        echo "Fetch of $URL failed, RC=$RC"  >&2 | tee -a ${OUT_FILE}
        [ $ALLOW_ERRORS ] && exit 6
        exit 0
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



# Can be overriden by the implementation scripts in 'hivehook_env_setup' function
# Also, can be provided at the top level bootstrap or setup script
[ -z "$HIVE_VER_XYZ_DEFAULT" ] && export HIVE_VER_XYZ_DEFAULT=1.2.0

# Unravel HiveHook setup

###############################################################################################
# Wait for hive-site.xml file to appear                                                       #
#                                                                                             #
# Accepts:                                                                                    #
#  - should_wait_for_hive()           Indicates whether the wait is meaningful                #
###############################################################################################
function wait_for_hive() {
    if isFunction should_wait_for_hive && should_wait_for_hive; then
        local retries=$1
        if [ -z "$UNATTENDED" ]; then
            read -p "Hive config folder [$HIVE_CONF_DEST]: " HIVE_CONF_DEST_PROMPT
            if [ ! -z "$HIVE_CONF_DEST_PROMPT" ]; then
                HIVE_CONF_DEST="$HIVE_CONF_DEST_PROMPT"
            fi
        fi

        local checked_file=$HIVE_CONF_DEST/hive-site.xml

        ls -al $checked_file  1>/dev/null 2>/dev/null
        CV=$?

        if [ $retries -gt 0 ]; then
            echo "Waiting for $checked_file file to appear (max. ${retries}s)" | tee -a ${OUT_FILE}
            while [ $CV -ne 0 ] && [ $retries -gt 0 ]; do
                retries=$((retries-1))
                echo -n "." | tee -a ${OUT_FILE}
                sleep 1
                ls -al $checked_file  1>/dev/null 2>/dev/null
                CV=$?
            done
            echo
        fi

        if [ $CV -ne 0 ]; then
            echo "Unable to locate $checked_file file" | tee -a ${OUT_FILE}
            return 1
        fi

        echo "$checked_file file found" | tee -a ${OUT_FILE}

        if [ 0 -ne $1 ] && [ ! -z "$UNATTENDED" ]; then
            # let the dust settle
            echo "Letting the system settle for 20s" | tee -a ${OUT_FILE}
            sleep_with_dots 20
            echo | tee -a ${OUT_FILE}
        fi
    fi
}

# uninstall hive-site.xml changes
function uninstall_hive_site() {
    # if an implementation specific uninstall is provided execute it and return
    if isFunction uninstall_hive_site_impl; then
      uninstall_hive_site_impl
      return
    fi

    # if we cannot find our backup of the hive-site.xml with our changes in it, then no way
    #   to ensure we leave the cluster in a good state, so we must bail out
    if [ ! -e  $HIVE_CONF_DEST/hive-site.xml.unravel ]; then
        echo "Previous Unravel instrumentation install not detected" >&2
        exit 0
    fi

    # continue to the default uninstall
    if wait_for_hive 0; then
        # if hive-site.xml was modified after our changes, detect that and avoid messing it up by not uninstalling
        cmp --quiet $HIVE_CONF_DEST/hive-site.xml.unravel $HIVE_CONF_DEST/hive-site.xml
        RC=$?
        if [ $RC -ne 0 ]; then
            # hive-site.xml was changed after we installed, so reject
            echo "Error:  $HIVE_CONF_DEST/hive-site.xml was changed after Unravel instrumentation install, so uninstall must be done by hand" >&2
            exit 1
        fi

        if [ -e $HIVE_CONF_DEST/hive-site.xml.pre_unravel ]; then
            if [ -s $HIVE_CONF_DEST/hive-site.xml.pre_unravel ]; then
                # non-zero sized pre_unravel
                sudo /bin/mv -f $HIVE_CONF_DEST/hive-site.xml.pre_unravel $HIVE_CONF_DEST/hive-site.xml
            else
                # empty pre_unravel means no hive-site.xml before we installed, so we remove the file
                sudo /bin/rm -f $HIVE_CONF_DEST/hive-site.xml $HIVE_CONF_DEST/hive-site.xml.pre_unravel 2>/dev/null
            fi
        fi
        sudo /bin/rm -fr  ${TMP_DIR}/hh[0-9]* ${TMP_DIR}/hs[0-9]* ${UNRAVEL_HH_DEST}

        # remove the marker file
        sudo /bin/rm -f ${HIVE_CONF_DEST}/hive-site.xml.unravel
    else
        # if no hive-site.xml then we are disabled anyway, so nothing to do
        echo "No $HIVE_CONF_DEST/hive-site.xml detected, nothing to do" >&2
    fi
}

###############################################################################################
# Checks whether the Unravel Hive Hook has already been installed                             #
#                                                                                             #
# Accepts:                                                                                    #
#  - UNRAVEL_CONF_DEST                                                                        #
###############################################################################################
function hivehook_already_installed() {
    local conf_dest=$(eval echo $HIVE_CONF_DEST)

  if [ -e ${conf_dest}/hive-site.xml.pre_unravel ]; then
    return 0
  else
    return 1
  fi
}


function get_hadoop_ver() {
  # detect Hadoop version
  #
  HADOOP_VER_XYZ="$(hadoop version | grep '^Hadoop ' | head -1 | awk '{ print $2 }' | awk -F- '{ print $1 }')"

  if [ -z "$HADOOP_VER_XYZ" ]; then
    HADOOP_VER_XYZ="$HADOOP_VER_XYZ_DEFAULT"
  fi

  HADOOP_VER_XY="$(echo $HADOOP_VER_XYZ | awk -F.  '{ printf("%s.%s",$1, $2) }')"
  if [ -z "$HADOOP_VER_XYZ" ]; then
    echo "Unable to determine Hadoop version, assuming 2.6" |tee -a $OUT_FILE
    HADOOP_VER_XY=2.6
  fi
  echo "Hadoop main version: $HADOOP_VER_XY"  |tee -a  $OUT_FILE
}

function generate_snippet() {
  # prepare hive-site.xml snippet
  cat <<EOF >${TMP_DIR}/hh$$

<property>
  <name>com.unraveldata.hive.hook.tcp</name>
  <value>true</value>
  <description>Unravel hive-hook processing via tcp enabled if true; this takes precedence over an hdfs destination</description>
</property>

<property>
  <name>com.unraveldata.host</name>
  <value>${UNRAVEL_HOST}</value>
  <description>Unravel hive-hook processing host</description>
</property>

<property>
  <name>com.unraveldata.hive.hdfs.dir</name>
  <value>/user/unravel/HOOK_RESULT_DIR</value>
  <description>destination for hive-hook, Unravel log processing</description>
</property>

<property>
  <name>hive.exec.driver.run.hooks</name>
  <value>com.unraveldata.dataflow.hive.hook.HiveDriverHook</value>
  <description>for Unravel, from unraveldata.com</description>
</property>

<property>
  <name>hive.exec.pre.hooks</name>
  <value>com.unraveldata.dataflow.hive.hook.HivePreHook</value>
  <description>for Unravel, from unraveldata.com</description>
</property>

<property>
  <name>hive.exec.post.hooks</name>
  <value>com.unraveldata.dataflow.hive.hook.HivePostHook</value>
  <description>for Unravel, from unraveldata.com</description>
</property>

<property>
  <name>hive.exec.failure.hooks</name>
  <value>com.unraveldata.dataflow.hive.hook.HiveFailHook</value>
  <description>for Unravel, from unraveldata.com</description>
</property>

EOF

}

function install_hive_site() {
    if isFunction should_install_hh_conf; then
        should_install_hh_conf
        if [ 0 -ne $? ]; then
            echo "System is not eligible for Hive configuration modifications" | tee -a ${OUT_FILE}
            return
        fi
    fi

    if isFunction install_hive_site_impl; then
      install_hive_site_impl
      return
    fi

    if [ ! -d $HIVE_CONF_DEST ]; then
        echo "Hive conifguration directory does not exist. Skipping Hive configuration installation" | tee -a ${OUT_FILE}
        return
    fi

    if [ -e $HIVE_CONF_DEST/hive-site.xml ]; then
        # existing hive-site.xml
        if has_unravel_hook; then
          echo "${HIVE_CONF_DEST}/hive-site.xml has already been modified for Unravel. Skipping." | tee -a ${OUT_FILE}
          return
        fi

        sudo /bin/cp -p $HIVE_CONF_DEST/hive-site.xml $HIVE_CONF_DEST/hive-site.xml.pre_unravel
        ## cat $HIVE_CONF_DEST/hive-site.xml | grep -v '</configuration>' > ${TMP_DIR}/hs$$
        cat $HIVE_CONF_DEST/hive-site.xml | sed -e 's^</configuration>^^' > ${TMP_DIR}/hs$$
        echo "" >> ${TMP_DIR}/hs$$
        generate_snippet
        cat ${TMP_DIR}/hh$$ >> ${TMP_DIR}/hs$$
        echo '</configuration>' >>  ${TMP_DIR}/hs$$
    else
        # indicate that we saw no previous hive-site.xml by creating 0 sized file
        sudo touch  $HIVE_CONF_DEST/hive-site.xml.pre_unravel
        # create hive-site.xml
        echo '<?xml version="1.0" encoding="UTF-8"?>' > ${TMP_DIR}/hs$$
        echo '<configuration>' >> ${TMP_DIR}/hs$$
        echo "" >> ${TMP_DIR}/hs$$
        generate_snippet
        cat ${TMP_DIR}/hh$$ >>${TMP_DIR}/hs$$
        echo '</configuration>' >>  ${TMP_DIR}/hs$$
    fi
    # prepare for mv
    sudo /bin/cp -f ${TMP_DIR}/hs$$ $HIVE_CONF_DEST/
    # keep a copy of the new file in case it gets wiped out by another bootstrap step
    sudo /bin/cp -f ${TMP_DIR}/hs$$ $HIVE_CONF_DEST/hive-site.xml.unravel
    sudo chmod 644 $HIVE_CONF_DEST/hs$$ $HIVE_CONF_DEST/hive-site.xml.unravel
    sudo chown ${HIVE_CONF_DEST_OWNER} $HIVE_CONF_DEST/hs$$ $HIVE_CONF_DEST/hive-site.xml.unravel
    # atomic mv of file
    sudo /bin/mv  $HIVE_CONF_DEST/hs$$ $HIVE_CONF_DEST/hive-site.xml

}

function install_hh_jar() {
  # install jar
  #dest:
  HH_JAR_NAME="unravel-hive-${HIVE_VER_X}.${HIVE_VER_Y}.0-hook.jar"
  HHURL="http://${UNRAVEL_SERVER}/hh/$HH_JAR_NAME"
  if [ ! -z $SENSOR_URL ]; then
    HHURL=${SENSOR_URL%%/}/$HH_JAR_NAME
  fi
  echo "GET $HHURL" |tee -a $OUT_FILE
  wget -4 -q -T 10 -t 5 -O - $HHURL > ${TMP_DIR}/$HH_JAR_NAME
  RC=$?

  if [ $RC -ne 0 ]; then
    echo "Failed to download Hive hook from $HHURL try to download it from dfs backup"
    download_from_dfs $HH_JAR_NAME ${TMP_DIR}/$HH_JAR_NAME
    RC=$?
  fi

  if [ $RC -eq 0 ]; then
    upload_to_dfs ${TMP_DIR}/$HH_JAR_NAME
    echo "Copying ${HH_JAR_NAME} to ${UNRAVEL_HH_DEST}" | tee -a $OUT_FILE
    sudo mkdir -p $UNRAVEL_HH_DEST
    sudo chown ${UNRAVEL_HH_DEST_OWNER} $UNRAVEL_HH_DEST
    sudo /bin/cp ${TMP_DIR}/$HH_JAR_NAME  $UNRAVEL_HH_DEST
    sudo chmod 644 $UNRAVEL_HH_DEST/$HH_JAR_NAME
    sudo chown ${UNRAVEL_HH_DEST_OWNER} $UNRAVEL_HH_DEST/$HH_JAR_NAME
  else
    echo "Fetch of $HHURL failed, RC=$RC" |tee -a $OUT_FILE
    [ "$ALLOW_ERRORS" ]  &&  exit 6
    return 0
  fi
}

function uninstall_hh_jar() {
  rm -rf ${UNRAVEL_HH_DEST} | tee -a ${OUT_FILE}
}

function resolve_hive_version() {
    isFunction hivehook_env_setup && hivehook_env_setup

    if [ -z "$HIVE_VER_X" ] && [ -z "$HIVE_VER_Y" ] && [ -z "$HIVE_VER_Z" ]; then
        if wait_for_hive 600; then
            if [ -z "$HIVE_VER_XYZ" ]; then
                HIVE=$(which hive)
                if [ ! -z "$HIVE" ]; then
                    HIVE_VER_XYZ=$($HIVE --version 2>/dev/null | grep -Po 'Hive \K([0-9]+\.[0-9]+\.[0-9]+)')
                fi
            fi

            if [ -z "$HIVE_VER_XYZ" ]; then
                echo "Unable to determine Hive version, assuming $HIVE_VER_XYZ_DEFAULT" | tee -a ${OUT_FILE}
                export HIVE_VER_XYZ=$HIVE_VER_XYZ_DEFAULT
            fi
            export HIVE_VER_X="$(echo $HIVE_VER_XYZ | awk -F.  '{ print $1 }')"
            export HIVE_VER_Y="$(echo $HIVE_VER_XYZ | awk -F.  '{ print $2 }')"
            export HIVE_VER_Z="$(echo $HIVE_VER_XYZ | awk -F.  '{ print $3 }')"
        fi
    fi
}

###############################################################################################
# Installs the Unravel Hive Hook                                                              #
#                                                                                             #
# Requires:                                                                                   #
#  - HIVE_VER_XYZ                                                                             #
#  - UNRAVEL_SERVER                                                                           #
#  - TMP_DIR                                                                                  #
#  - HIVE_CONF_DEST hive-site.conf location                                                   #
#  - HADOOP_CONF  hadoop conf folder                                                          #
# Provides:                                                                                   #
#  - HIVE_VER_X                                                                               #
#  - HIVE_VER_Y                                                                               #
#  - HIVE_VER_Z                                                                               #
# Accepts:                                                                                    #
#  - UNRAVEL_HH_DEST_OWNER user (default ec2-user)                                            #
#  - UNRAVEL_HH_DEST folder (default /usr/local/unravel_client)                               #
###############################################################################################
function hivehook_install() {
    isFunction hivehook_env_setup && hivehook_env_setup

    if hivehook_already_installed ; then
        echo "Unravel Hive Sensor already installed" | tee -a ${OUT_FILE}
    else
        resolve_hive_version
        if [ ! -z "$HIVE_VER_X" ] && [ ! -z "$HIVE_VER_Y" ] && [ ! -z "$HIVE_VER_Z" ]; then
            echo "Using Hive version: ${HIVE_VER_X}.${HIVE_VER_Y}.${HIVE_VER_Z}" | tee -a ${OUT_FILE}

            # system specific before install hook
            isFunction before_hh_install && before_hh_install
            install_hh_jar
            #install_hive_site
            isFunction after_hh_install && after_hh_install
            echo "Hivehook install is completed." | tee -a ${OUT_FILE}

            #hivehook_postinstall_check
            return $?
        else
            echo "Skipping hive hook installation." | tee -a ${OUT_FILE}
        fi
    fi
}

###############################################################################################
# Removes the Unravel Hive Hook                                                               #
#                                                                                             #
# Requires:                                                                                   #
#  - TMP_DIR                                                                                  #
#  - HIVE_CONF_DEST hive-site.conf location                                                   #
#  - HADOOP_CONF  hadoop conf folder                                                          #
# Accepts:                                                                                    #
#  - UNRAVEL_HH_DEST_OWNER user (default ec2-user)                                            #
#  - UNRAVEL_HH_DEST folder (default /usr/local/unravel_client)                               #
###############################################################################################
function hivehook_uninstall() {
  isFunction hivehook_env_setup && hivehook_env_setup

  if ! hivehook_already_installed ; then
    echo "Unravel Hive Sensor not installed" | tee -a ${OUT_FILE}
  else
    isFunction before_hh_uninstall && before_hh_uninstall

    uninstall_hh_jar
    uninstall_hive_site

    isFunction after_hh_uninstall && after_hh_uninstall

    echo "unravel Hive-hook is uninstalled" | tee -a ${OUT_FILE}
  fi
}
###############################################################################################
# Convenience wrapper for installation or removal of the Unravel Hive Hook                    #
#                                                                                             #
# The first argument is the desired command {install, uninstall}. The rest of the arguments   #
# depends on the accepted argument set of the target command.                                 #
# Requires:                                                                                   #
#  - hivehook_install()                                                                       #
#  - hivehook_uninstall()                                                                     #
###############################################################################################
function hivehook_setup() {
  CMD=$1
  shift
  case $CMD in
    install ) hivehook_install $*;;
    uninstall ) hivehook_uninstall $*;;
    ? ) echo "Unknown command $CMD for 'hivehook_setup' function" | tee -a ${OUT_FILE}
  esac
}

###############################################################################################
# Performs post-installation sanity checks                                                    #
#                                                                                             #
# Accepts:                                                                                    #
#  - hivehook_postinstall_check_impl()                                                        #
###############################################################################################
function hivehook_postinstall_check() {
    local ret=0
    local owner

    if [ ! -d $UNRAVEL_HH_DEST ]; then
        echo "ERROR: Directory $UNRAVEL_HH_DEST was not created" | tee -a ${OUT_FILE}
        ret=1
    else
        owner=$(ls -ld $UNRAVEL_HH_DEST | awk '{print $3 ":" $4}')
        if [ "$owner" != "$UNRAVEL_HH_DEST_OWNER" ]; then
            echo "ERROR: Invalid owner of $UNRAVEL_HH_DEST. Expecting $UNRAVEL_HH_DEST_OWNER but got $owner" | tee -a ${OUT_FILE}
            ret=1
        fi
        if [ ! "$(find $UNRAVEL_HH_DEST -type f -name 'unravel-hive-*-hook.jar')" ]; then
            echo "ERROR: HiveHook jar(s) not present in $UNRAVEL_HH_DEST" | tee -a ${OUT_FILE}
            ret=1
        fi
    fi
    if [ ! -z "$HIVE_CONF_DEST" ] && [ -d $HIVE_CONF_DEST ]; then
        owner=$(ls -ld $HIVE_CONF_DEST | awk '{print $3 ":" $4}')
        if [ "$owner" != "$HIVE_CONF_DEST_OWNER" ]; then
            echo "ERROR: Invalid owner of $HIVE_CONF_DEST. Expecting $HIVE_CONF_DEST_OWNER but got $owner" | tee -a ${OUT_FILE}
            return 1
        fi
        if [ ! -e "$HIVE_CONF_DEST/hive-site.xml.pre_unravel" ]; then
            echo "ERROR: Missing $HIVE_CONF_DEST/hive-site.xml.pre_unravel file" | tee -a ${OUT_FILE}
            ret=1
        else
            if cmp -s "$HIVE_CONF_DEST/hive-site.xml" "$HIVE_CONF_DEST/hive-site.xml.pre_unravel"; then
                echo "ERROR: $HIVE_CONF_DEST/hive-site.xml and $HIVE_CONF_DEST/hive-site.xml.pre_unravel are identical. Unravel settings might be missing" | tee -a ${OUT_FILE}
                ret=1
            fi
            if [ ! -e "$HIVE_CONF_DEST/hive-site.xml.unravel" ]; then
                echo "ERROR: Missing $HIVE_CONF_DEST/hive-site.xml.unravel" | tee -a ${OUT_FILE}
            fi
        fi
    fi

    if isFunction hivehook_postinstall_check_impl; then
        hivehook_postinstall_check_impl
        [ 0 -ne $? ] && ret=1
    fi

    return $ret
}

function has_unravel_hook() {
  # check for the required property in hive-site.xml
  grep -e "com.unraveldata.host" ${HIVE_CONF_DEST}/hive-site.xml
  return $?
}


if [ -z "$UNRAVEL_ES_USER" ]; then
  export UNRAVEL_ES_USER=hdfs
fi

if [ -z "$UNRAVEL_ES_GROUP" ]; then
  export UNRAVEL_ES_GROUP=$UNRAVEL_ES_USER
fi


# Unravel Integration - Unravel MR sensor (unravel_es) setup

function get_sensor_initd() {
    sudo /bin/rm -f ${TMP_DIR}/u_es 2>/dev/null
    cat <<EOF >"${TMP_DIR}/u_es"
#!/bin/bash
# chkconfig: 2345 90 10
### BEGIN INIT INFO
# Provides:          Unravel EMR Sensor daemon
# Required-Start:
# Required-Stop:
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Instrumentation for Unravel
# Description:       Instrumentation for Unravel, sends job logs to Unravel server
### END INIT INFO

. /lib/lsb/init-functions

#set -x

DAEMON_NAME="unravel_es"
PID_FILE="${TMP_DIR}/\${DAEMON_NAME}.pid"
OUT_LOG="${TMP_DIR}/\${DAEMON_NAME}.out"
UNRAVEL_ES_USER=${UNRAVEL_ES_USER}
if [ -e /usr/local/unravel_es/etc/unravel_ctl ]; then
    source /usr/local/unravel_es/etc/unravel_ctl
fi


function get_pid {
  cat \$PID_FILE
}

function is_running {
  [ -f \$PID_FILE ] && ps \$(get_pid) > /dev/null 2>&1
}

function start {
  if is_running; then
    echo "\$DAEMON_NAME already started"
  else
    echo "Starting \$DAEMON_NAME..."
    su - \${UNRAVEL_ES_USER} -c bash -c "cd /usr/local/\${DAEMON_NAME}; ./dbin/unravel_emr_sensor.sh" >\$OUT_LOG 2>&1 &
    echo \$! > \$PID_FILE
    disown %1
    if ! is_running ; then
      echo "Unable to start \$DAEMON_NAME, see \$OUT_LOG"
      exit 1
    fi
  fi
}

function stop {
  if is_running; then
    pid=\$(get_pid)
    echo "Stopping \$DAEMON_NAME... PID: \$pid"
    kill \$pid
    sleep 1
    # Search for any process that launched the shell script or the jar.
    # So keep this backward compatible with Unravel 4.4 version.
    PIDS=\$(ps -U \${UNRAVEL_ES_USER} -f | egrep "unravel_es|unravel_emr_sensor" | grep -v grep | awk '{ print \$2 }' )
    [ "\$PIDS" ] && kill \$PIDS
    for i in {1..10}
    do
        if ! is_running; then
			break
        fi
        echo -n "."
        sleep 1
    done
    if is_running; then
        echo "\$DAEMON_NAME not stopped; may still be shutting down or shutdown may have failed"
        exit 1
    else
        echo "\$DAEMON_NAME stopped"
        if [ -f \$PID_FILE ]; then
            rm \$PID_FILE
        fi
    fi
  else
    echo "\$DAEMON_NAME not running"
  fi
}

case \$1 in
  'start' )
     start
     ;;
  'stop' )
     stop
     ;;
  'restart' )
     stop
     if is_running; then
       echo "Unable to stop \$DAEMON_NAME, will not attempt to start"
       exit 1
     fi
     start
     ;;
  'status' )
    if is_running; then
      echo "\$DAEMON_NAME is running"
    else
      echo "\$DAEMON_NAME is not running"
    fi
    ;;
  *)
    echo "usage: `basename \$0` {start|stop|status|restart}"
esac

exit 0
EOF
    sudo /bin/mv ${TMP_DIR}/u_es /etc/init.d/unravel_es
    sudo chown root:root /etc/init.d/unravel_es
    sudo chmod 744 /etc/init.d/unravel_es
}

function gen_sensor_properties() {
  sudo mkdir -p /usr/local/unravel_es/etc
  cat <<EOF > /usr/local/unravel_es/etc/unravel_es.properties
#######################################################
# unravel_es settings                                 #
# - modify the settings and restart the service       #
#######################################################

# debug=false
# done-dir=/path/to/done/dir
# sleep-sec=30
# chunk-size=20
cluster-type=hdi
cluster-id=`echo $CLUSTER_ID`
unravel-server=`echo $UNRAVEL_SERVER | sed -e "s/:.*/:4043/g"`
am-polling=$AM_POLLING
enable-aa=$ENABLE_AA
hive-id-cache=$HIVE_ID_CACHE
EOF
}

###############################################################################################
# Generating unravel.properties file with kerberos configurations                             #
###############################################################################################
function gen_secure_properties() {
export UNRAVEL_CTL=/usr/local/unravel_es/etc/unravel_ctl
if [ $UNRAVEL_ES_USER == 'hdfs' ] && [ ! -e $UNRAVEL_CTL ]; then
    UNRAVEL_ES_USER=unravel
    UNRAVEL_ES_GROUP=unravel
elif [ $UNRAVEL_ES_USER != 'hdfs' ]; then
    cat <<EOF > $UNRAVEL_CTL
UNRAVEL_ES_USER=$UNRAVEL_ES_USER
UNRAVEL_ES_GROUP=$UNRAVEL_ES_USER
EOF
else
  source $UNRAVEL_CTL
fi

id -u ${UNRAVEL_ES_USER} &>/dev/null || useradd ${UNRAVEL_ES_USER}
setfacl -m user:${UNRAVEL_ES_USER}:r-- $KEYTAB_PATH
if [ ! -e /usr/local/unravel_es/etc/unravel.properties ]; then
    mkdir -p /usr/local/unravel_es/etc
    cat <<EOF > /usr/local/unravel_es/etc/unravel.properties
com.unraveldata.kerberos.principal=$KEYTAB_PRINCIPAL
com.unraveldata.kerberos.keytab.path=$KEYTAB_PATH
yarn.resourcemanager.webapp.username=$RM_USER
yarn.resourcemanager.webapp.password=$RM_PASSWORD
EOF
    echo "Kerberos Principal: $KEYTAB_PRINCIPAL"
    echo "Kerberos Keytab: $KEYTAB_PATH"
else
    cat /usr/local/unravel_es/etc/unravel.properties
fi
}

###############################################################################################
# Checks whether the Unravel MR sensor (unravel_es) has already been installed                #
###############################################################################################
function es_already_installed() {
  ls /usr/local/unravel_es 2>/dev/null
}

###############################################################################################
# Installs the Unravel MR sensor (unravel_es)                                                 #
#                                                                                             #
# Requires:                                                                                   #
#  - UNRAVEL_ES_USER                                                                          #
#  - UNRAVEL_ES_GROUP                                                                         #
#  - UNRAVEL_SERVER                                                                           #
#  - UNRAVEL_HOST                                                                             #
#  - UNRAVEL_RESTSERVER_HOST_AND_PORT                                                         #
#  - TMP_DIR                                                                                  #
# Accepts:                                                                                    #
#  - ENABLE_GPL_LZO                                                                           #
###############################################################################################
function es_install() {
  echo "Attempting to install ES (Unravel MR Sensor)" | tee -a ${OUT_FILE}
  if isFunction can_install_es; then
    if ! can_install_es; then
      echo "Unravel MR Sensor (unravel_es) is not eligible since can only be installed on master node" | tee -a ${OUT_FILE}
      return 0
    fi
  fi

  if es_already_installed; then
    echo "Unravel MR Sensor (unravel_es) already installed by checking /usr/local/unravel_es, will attempt to overwrite it." | tee -a ${OUT_FILE}
  fi

  sudo /bin/mkdir -p /usr/local/unravel_es/lib
  if [ "$ENABLE_GPL_LZO" == "yes" ] || [ "$ENABLE_GPL_LZO" == "true" ]; then
    sudo wget --timeout=15 -t 2 -4 -q -T 10 -t 5 -O - http://central.maven.org/maven2/org/anarres/lzo/lzo-core/1.0.5/lzo-core-1.0.5.jar > /usr/local/unravel_es/lib/lzo-core.jar
    if [ $? -eq 0 ]; then
        echo "lzo-core-1.0.5.jar Downloaded "
    else
        echo "Failed to Download lzo-core-1.0.5.jar"
        echo "If the cluster has restricted internet access please download lzo-core-1.0.5.jar and copy it to  /tmp/"
        if [ -f /tmp/lzo-core-1.0.5.jar ]; then
            sudo mv /tmp/lzo-core-1.0.5.jar /usr/local/unravel_es/lib/lzo-core.jar
        else
            exit 1
        fi
    fi
  fi

  # generate /etc/init.d/unravel_es
  # For Secure Cluster create unravel.properties file
  if is_secure; then
    echo "Setting up Unravel properties for secure cluster..."
    gen_secure_properties
  fi
  get_sensor_initd
  # Note that /usr/local/unravel_es/dbin/unravel_emr_sensor.sh is now
  # packaged by the RPM and unzipped.
  # Generate /usr/local/unravel_es/etc/unravel_es.properties. We will ignore the
  # template (unravel_es.properties.template) that ships with the RPM.
  gen_sensor_properties

  echo "running unravel_es as: $UNRAVEL_ES_USER"
  echo "running unravel_es as: $UNRAVEL_ES_GROUP"
  UES_JAR_NAME="unravel-emrsensor-pack.zip"
  UESURL="http://${UNRAVEL_SERVER}/hh/$UES_JAR_NAME"
  if [ ! -z $SENSOR_URL ]; then
    UESURL=${SENSOR_URL%%/}/$UES_JAR_NAME
  fi
  UES_PATH="/usr/local/unravel_es"
  echo "GET $UESURL" |tee -a  $OUT_FILE
  wget -4 -q -T 10 -t 5 -O - $UESURL > ${TMP_DIR}/$UES_JAR_NAME
  RC=$?
  if [ $RC -eq 0 ]; then
      upload_to_dfs ${TMP_DIR}/$UES_JAR_NAME
      sudo /bin/cp ${TMP_DIR}/$UES_JAR_NAME  ${UES_PATH}
      [ -d "${UES_PATH}/dlib" ] && rm -rf ${UES_PATH}/dlib
      sudo unzip -o /usr/local/unravel_es/$UES_JAR_NAME -d ${UES_PATH}/
      sudo chmod 755 ${UES_PATH}/dbin/*
      sudo chown -R "${UNRAVEL_ES_USER}":"${UNRAVEL_ES_GROUP}" ${UES_PATH}
  else
      echo "ERROR: Fetch of $UESURL failed, RC=$RC" |tee -a $OUT_FILE
      download_from_dfs $UES_JAR_NAME
      if [ $? -ne 0 ]; then
        return 1
      fi
  fi

  # start
  if isFunction install_service_impl; then
    install_service_impl
  else
    install_service_dflt
  fi
  RC=$?

  if [ $RC -eq 0 ]; then
    sudo service unravel_es restart
  fi
  RC=$?

  if [ $RC -eq 0 ]; then
      echo "Unravel MR Sensor (unravel_es) is installed and running" | tee -a  $OUT_FILE
      sudo sed -i '20imkdir -p /tmp/unravel' /etc/init.d/unravel_es
      sudo sed -i '21ichmod 777 /tmp/unravel' /etc/init.d/unravel_es
      sudo systemctl daemon-reload
      es_postinstall_check
      local result=$?
      echo "Done calling es_postinstall_check with result ${result} (1 == failed, 0 == passed)." | tee -a $OUT_FILE
      return $result
  else
      echo "ERROR: Unravel MR Sensor (unravel_es) start failed" | tee -a  $OUT_FILE
      return 1
  fi
}

###############################################################################################
# Stops and removes the Unravel MR sensor (unravel_es)                                        #
###############################################################################################
function es_uninstall() {
  if es_already_installed; then
    sudo /etc/init.d/unravel_es stop 2>/dev/null
    sudo /bin/rm -fr  /usr/local/unravel_es /etc/init.d/unravel_es  2>/dev/null
    echo "Unravel MR Sensor (unravel_es) was successfully uninstalled" | tee -a ${OUT_FILE}
  else
    echo "Unravel MR Sensor (unravel_es) has not been installed. Aborting the uninstall." | tee -a ${OUT_FILE}
  fi
}

###############################################################################################
# Convenience wrapper for installation or removal of the Unravel MR sensor (unravel_es)       #
#                                                                                             #
# The first argument is the desired command {install, uninstall}. The rest of the arguments   #
# depends on the accepted argument set of the target command.                                 #
# Requires:                                                                                   #
#  - es_install()                                                                             #
#  - es_uninstall()                                                                           #
###############################################################################################
function es_setup() {
  CMD=$1
  shift
  case $CMD in
    install ) es_install $*;;
    uninstall ) es_uninstall $*;;
    ? ) echo "Unknown command $CMD for 'es_setup' function" | tee -a ${OUT_FILE}
  esac
}

###############################################################################################
# Performs post-installation sanity checks                                                    #
# Returns 0 if properly installed on a master node, otherwise, return 1                       #
#                                                                                             #
# Accepts:                                                                                    #
#  - es_postinstall_check_configs()                                                         #
#  - can_install_es()                                                                         #
###############################################################################################
function es_postinstall_check() {
  echo "Performing Unravel ES post-install checks to ensure service is running and properly configured" | tee -a ${OUT_FILE}

  if isFunction can_install_es ; then
     can_install_es
     if [ 0 -ne $? ]; then
       echo "Not running on a master node, so can skip the ES Post Install check" | tee -a ${OUT_FILE}
       return 0
     fi
  fi
  # make sure that 'unravel_es' is running and using correct arguments
  local es_cmd=$(ps aexo "command" | grep -E "unravel.emr.sensor" | grep -v "grep")
  echo "ES Process = ${es_cmd}" | tee -a ${OUT_FILE}
  echo "" | tee -a ${OUT_FILE}

  if [ -z "$es_cmd" ]; then
    echo "ERROR: 'unravel_es' service is not running!" | tee -a ${OUT_FILE}
    return 1
  fi

  if isFunction es_postinstall_check_configs; then
    es_postinstall_check_configs
    if [ 0 -ne $? ]; then
      echo "ERROR: es_postinstall_check_configs failed" | tee -a ${OUT_FILE}
      return 1
    fi
  fi
  return 0
}

function install_service_dflt() {
  sudo /sbin/chkconfig unravel_es on
}



# Can be overridden by the implementation scripts in 'spark_env_setup' function
# Also, can be provided at the top level bootstrap or setup script
[ -z "$SPARK_VER_XYZ_DEFAULT" ] && export SPARK_VER_XYZ_DEFAULT=1.6.0

# Unravel Spark setup

###############################################################################################
# Removes the Unravel Spark sensor                                                            #
#                                                                                             #
# Requires:                                                                                   #
#  - TMP_DIR                                                                                  #
#  - SPARK_CONF_DEST                                                                          #
#  - SPARK_HOME                                                                               #
# Accepts:                                                                                    #
#  - UNRAVEL_SPARK_DEST_OWNER user (default root)                                             #
#  - UNRAVEL_SPARK_DEST folder (default /usr/local/unravel-spark)                             #
#  - ZEPPELIN_CONF_DIR                                                                        #
###############################################################################################
function spark_uninstall() {
    spark_uninstall_conf
}

function spark_uninstall_conf() {
    isFunction spark_env_setup && spark_env_setup
    if isFunction uninstall_spark_conf_impl; then
      uninstall_spark_conf_impl
      return
    fi

    local conf_dest=$(eval echo $SPARK_CONF_DEST)
    if wait_for_spark 0 ; then
        if [ ! -e  $conf_dest/spark-defaults.conf.unravel ]; then
            echo "$conf_dest/spark-defaults.conf.unravel was not detected, uninstall (if at all needed) must be done manually." >&2 | tee -a ${OUT_FILE}
            return 0
        fi
        # if spark-defaults.conf was modified after our changes, detect that and avoid messing it up by not uninstalling
        cmp --quiet $conf_dest/spark-defaults.conf.unravel $conf_dest/spark-defaults.conf
        RC=$?
        if [ $RC -ne 0 ]; then
            # spark-defaults.conf was changed after we installed, so reject
            echo "ERROR: $conf_dest/spark-defaults.conf was changed after Unravel instrumentation install, so uninstall must be done by hand" >&2 | tee -a ${OUT_FILE}
            return 1
        fi

        # removing sensors folder and unravel config files
        sudo /bin/rm -fr $conf_dest/spark-defaults.conf.unravel
        #
        if [ -e $conf_dest/spark-defaults.conf.pre_unravel ]; then
            if [ -s $conf_dest/spark-defaults.conf.pre_unravel ]; then
              echo "Restoring ${conf_dest}/spark-defaults.conf" | tee -a ${OUT_FILE}
                # non-zero sized pre_unravel
                sudo /bin/mv -f $conf_dest/spark-defaults.conf.pre_unravel $conf_dest/spark-defaults.conf
            else
                # empty pre_unravel means no spark-defaults.conf before we installed, so we remove the file
                sudo /bin/rm -f $conf_dest/spark-defaults.conf $conf_dest/spark-defaults.conf.pre_unravel 2>/dev/null
            fi
        else
             sudo /bin/rm -f $conf_dest/spark-defaults.conf
        fi
        sudo /bin/rm -f $conf_dest/spark-defaults.conf.unravel

        restore_zeppelin
    else
        # if we cannot find our backup of the spark-defaults.conf with our changes in it, then no way
        #   to ensure we leave the cluster in a good state, so we must bail out
        if [ ! -e  $conf_dest/spark-defaults.conf ]; then
            echo "No $conf_dest/spark-defaults.conf detected, nothing to do" >&2 | tee -a ${OUT_FILE}
            return 0
        fi
    fi
}

###############################################################################################
# Wait for spark-defaults.conf file to appear                                                 #
#                                                                                             #
# Accepts:                                                                                    #
#  - should_wait_for_spark()    Indicates whether the wait is meaningful (eg. master node)    #
###############################################################################################
function wait_for_spark() {
    if isFunction should_wait_for_spark && should_wait_for_spark; then
        local retries=$1
        local conf_dest=$(eval echo $SPARK_CONF_DEST)
        if [ -z "$UNATTENDED" ]; then
            while : ; do
                read -p "Spark config folder [$conf_dest]: " SPARK_CONF_DEST_PROMPT
                if [ ! -z "$SPARK_CONF_DEST_PROMPT" ]; then
                    conf_dest="$SPARK_CONF_DEST_PROMPT"
                fi
                if [ -d $conf_dest ]; then
                    break
                else
                    echo "Non-existing Spark config directory [$conf_dest]. Please, re-enter the location." | tee -a ${OUT_FILE}
                fi
            done
        fi

        local checked_file=$conf_dest/spark-defaults.conf

        ls -al $checked_file  1>/dev/null 2>/dev/null
        CV=$?

        if [ $retries -gt 0 ]; then
            echo "Waiting for $checked_file file to appear (max. ${retries}s)" | tee -a ${OUT_FILE}
            while [ $CV -ne 0 ] && [ $retries -gt 0 ]; do
                retries=$((retries-1))
                echo -n "." | tee -a ${OUT_FILE}
                sleep 1
                ls -al $checked_file  1>/dev/null 2>/dev/null
                CV=$?
            done
            echo
        fi

        if [ $CV -ne 0 ]; then
            echo "Unable to locate $checked_file file" | tee -a ${OUT_FILE}
            return 1
        fi

        echo "$checked_file file found" | tee -a ${OUT_FILE}

        if [ 0 -ne $1 ] && [ ! -z "$UNATTENDED" ]; then
            # let the dust settle
            echo "Letting the system settle for 20s" | tee -a ${OUT_FILE}
            sleep_with_dots 20
            echo | tee -a ${OUT_FILE}
        fi
    fi
}

function try_spark_ver() {
    if [ ! -z "$SPARK_VER_XYZ" ]; then
        return
    fi

    local loop_count=0
    while true ; do
        echo "Running spark-submit to get the Spark version" | tee -a ${OUT_FILE}
        local spark_submit=$(which spark-submit)
        if [ -z "$spark_submit" ]; then
            if [ ! -z "$SPARK_HOME" ]; then
                spark_submit="${SPARK_HOME}/bin/spark-submit"
            fi
        fi
        if [ -z "$spark_submit" ]; then
            if [ -z "$UNATTENDED" ]; then
                read -p "Unable to run 'spark-submit' command. Please, provide Spark version [$SPARK_VER_XYZ_DEFAULT]: " SPARK_VER_XYZ_PROMPT
                export SPARK_VER_XYZ=$SPARK_VER_XYZ_PROMPT
                return 0
            fi
            return 1
        fi

        local retval="$($spark_submit --version 2>&1 | grep -oP -m 1 '.*?version\s+\K([0-9.]+)')"
        if [ ! -z "$retval" ] ; then
            echo "spark ver ${retval} found after ${loop_count} minutes" | tee -a ${OUT_FILE}
            echo "$retval" | tee -a ${OUT_FILE}
            export SPARK_VER_XYZ="$retval"
            return 0
        fi

        if [ -z "$UNATTENDED" ]; then
            break
        fi

        loop_count=$(($loop_count+1))
        if [ $loop_count -gt 10 ]; then
            echo "giving up on spark after ${loop_count} minutes"  >&2 | tee -a ${OUT_FILE}
            return 6
        fi
        echo "waiting for up to 10 minutes for spark to be installed..."  >&2 | tee -a ${OUT_FILE}
        sleep_with_dots 60
    done
}

###############################################################################################
# Performs Spark configuration modifications for Unravel sensor                               #
#                                                                                             #
# Requires:                                                                                   #
#  - DRIVER_AGENT_ARGS                                                                        #
#  - EXECUTOR_AGENT_ARGS                                                                      #
#  - SPARK_CONF_DEST                                                                          #
# Accepts:                                                                                    #
#  - should_install_spark_conf()                                                              #
#  - HDFS_URL                                                                                 #
###############################################################################################
function install_spark_conf() {
    if isFunction should_install_spark_conf; then
        should_install_spark_conf
        if [ 0 -ne $? ]; then
            echo "System is not eligible for Spark configuration modifications" | tee -a ${OUT_FILE}
            return
        fi
    fi
    if isFunction install_spark_conf_impl; then
      #install_spark_conf_impl
      return
    fi

    local conf_dest=$(eval echo $SPARK_CONF_DEST)

    if [ ! -d $conf_dest ]; then
        echo "Spark config directory \"${conf_dest}\" does not exist. Skipping spark config installation" | tee -a ${OUT_FILE}
        return
    fi

    echo "Installing SparkConf()" | tee -a ${OUT_FILE}

    local EVENTLOG_DEFAULT_PATH="/var/log/spark/apps"
    local tfile=${TMP_DIR}/spk$$
    if [ -z "$HDFS_URL" ]; then
      HDFS_URL=$(cat $HADOOP_CONF/core-site.xml | grep -A 2 fs.defaultFS | grep '/value' | sed -e 's|^.*[<]value[>]\(.*\)[<]/value[>].*|\1|')
    fi

    if [ -e $conf_dest/spark-defaults.conf ]; then
        echo "Modifying existing spark-defaults.conf" | tee -a ${OUT_FILE}
        # existing spark-defaults.conf
        sudo /bin/cp -p $conf_dest/spark-defaults.conf $conf_dest/spark-defaults.conf.pre_unravel

        cat $conf_dest/spark-defaults.conf | egrep -v '^spark.driver.extraJavaOptions|^spark.executor.extraJavaOptions|^spark.eventLog.dir|^spark.history.fs.logDirectory' > $tfile
        echo "spark.unravel.server.hostport ${UNRAVEL_RESTSERVER_HOST_AND_PORT}" >>$tfile

        local existing_eventLog_entry=$(cat $conf_dest/spark-defaults.conf | grep '^spark.eventLog.dir')
        local protocol_hdfs="hdfs://"
        local protocol_file="file://"
        local protocol_s3="s3://"
        local protocol_s3n="s3n://"
        local protocol_maprfs="maprfs://"

        # by default set eventlog_without_file_protocol to EVENTLOG_DEFAULT_PATH
        local eventlog_without_file_protocol=${EVENTLOG_DEFAULT_PATH}

        # create the complete path, inclusing hdfs protocol, the host:port, and path
        local eventlog_path=""

        if [ ! -z "$existing_eventLog_entry" ]; then
            # take the value corresponding to "spark.eventLog.dir" and remove the protocol and host:port portion
            local eventLog_entry_array=($existing_eventLog_entry)

            eventlog_without_file_protocol=$(echo ${eventLog_entry_array[1]} | sed "s;^$protocol_hdfs;;" | sed "s;^$protocol_maprfs;;" | sed "s;^$protocol_file;;" | sed "s;^$protocol_s3;;" | sed "s;^$protocol_s3n;;")
            # cut host:port portion
            hostPort=$(echo $eventlog_without_file_protocol | cut -d "/" -f 1)
            eventlog_without_file_protocol=${eventlog_without_file_protocol:${#hostPort}}
            eventlog_path=${HDFS_URL}${eventlog_without_file_protocol}
        else
            eventlog_path=${HDFS_URL}${eventlog_without_file_protocol}
        fi
        echo "HDFS URL: ${HDFS_URL}" | tee -a ${OUT_FILE}
        echo "Event log file location: $eventlog_path" | tee -a ${OUT_FILE}


        echo "spark.eventLog.dir ${eventlog_path}" >>$tfile
        echo "spark.history.fs.logDirectory ${eventlog_path}" >>$tfile
        local existing_driver_entry=$(cat $conf_dest/spark-defaults.conf | grep '^spark.driver.extraJavaOptions')
        [ -z "$existing_driver_entry" ] && existing_driver_entry="spark.driver.extraJavaOptions"

        local existing_executor_entry=$(cat $conf_dest/spark-defaults.conf | grep '^spark.executor.extraJavaOptions')
        [ -z "$existing_executor_entry" ] && existing_executor_entry="spark.executor.extraJavaOptions"

        echo "${existing_driver_entry}  $DRIVER_AGENT_ARGS" >>$tfile
        echo "${existing_executor_entry} $EXECUTOR_AGENT_ARGS" >>$tfile
    else
        echo "Creating new spark-defaults.conf" | tee -a ${OUT_FILE}
        # create spark-defaults.conf
        eventlog_path=${HDFS_URL}${EVENTLOG_DEFAULT_PATH}
        echo "spark.unravel.server.hostport ${UNRAVEL_RESTSERVER_HOST_AND_PORT}" >$tfile
        echo "spark.eventLog.dir ${eventlog_path}" >>$tfile
        echo "spark.history.fs.logDirectory ${eventlog_path}" >>$tfile
          # create spark-defaults.conf
          # driver in client mode
        echo "spark.driver.extraJavaOptions $DRIVER_AGENT_ARGS" >>$tfile
        echo "spark.executor.extraJavaOptions $EXECUTOR_AGENT_ARGS" >>$tfile
    fi
    # prepare for mv
    sudo /bin/cp -f $tfile $conf_dest/
    # keep a copy of the new file in case it gets wiped out by another bootstrap step
    sudo /bin/cp -f $tfile $conf_dest/spark-defaults.conf.unravel
    sudo chmod 655 $conf_dest/spk$$ $conf_dest/spark-defaults.conf.unravel
    sudo chown $CONF_DEST_OWNER:$CONF_DEST_OWNER $conf_dest/spk$$ $conf_dest/spark-defaults.conf.unravel
    # atomic mv of file
    sudo /bin/mv  $conf_dest/spk$$ $conf_dest/spark-defaults.conf
}

###############################################################################################
# Checks whether the Unravel Spark sensor has already been configured                         #
#                                                                                             #
# Requires:                                                                                   #
#  - SPARK_CONF_DEST                                                                          #
#  - SPARK_VERSION_XYZ                                                                        #
###############################################################################################
function spark_already_configured() {
  local conf_dest=$(eval echo $SPARK_CONF_DEST)

  if [ -e ${conf_dest}/spark-defaults.conf.pre_unravel ]; then
    return 0
  else
    return 1
  fi
}

###############################################################################################
# Provides:                                                                                   #
#  - SPARK_VER_X                                                                              #
#  - SPARK_VER_Y                                                                              #
#  - SPARK_VER_Z                                                                              #
# Accepts:                                                                                    #
#  - SPARK_VER_XYZ                                                                            #
###############################################################################################
function resolve_spark_version() {
    isFunction spark_env_setup && spark_env_setup

    if [ -z "$SPARK_VER_X" ] && [ -z "$SPARK_VER_Y" ] && [ -z "$SPARK_VER_Z" ]; then
        if wait_for_spark 600; then
            # try getting spark version from env
            try_spark_ver
            if [ -z "$SPARK_VER_XYZ" ]; then
                if [ -z "$UNATTENDED" ]; then
                    read -p "Unable to determine Spark version, assuming default [$SPARK_VER_XYZ_DEFAULT]: " ver
                    export SPARK_VER_XYZ=$ver
                else
                    echo "Unable to determine Spark version, assuming $SPARK_VER_XYZ_DEFAULT" | tee -a ${OUT_FILE}
                    export SPARK_VER_XYZ="$SPARK_VER_XYZ_DEFAULT"
                fi
            fi

            export SPARK_VER_X="$(echo $SPARK_VER_XYZ | awk -F.  '{ print $1 }')"
            export SPARK_VER_Y="$(echo $SPARK_VER_XYZ | awk -F.  '{ print $2 }')"
            export SPARK_VER_Z="$(echo $SPARK_VER_XYZ | awk -F.  '{ print $3 }')"
            echo "Using Spark version: ${SPARK_VER_X}.${SPARK_VER_Y}.${SPARK_VER_Z}" | tee -a ${OUT_FILE}
        fi
    fi
}

###############################################################################################
# Provides:                                                                                   #
#  - DRIVER_AGENT_ARGS              JVM args to add to driver                                 #
#  - EXECUTOR_AGENT_ARGS            JVM args to add to executors
# Accepts:                                                                                    #
#  - SPARK_APP_LOAD_MODE            Spark App loading mode {DEV | OPS | BATCH} (default OPS)  #
###############################################################################################
function resolve_agent_args() {
    if [ "$SPARK_APP_LOAD_MODE" != "BATCH" ]; then
        local base_agent="-Dcom.unraveldata.client.rest.shutdown.ms=300 -javaagent:${AGENT_JARS}/btrace-agent.jar=libs=spark-${SPARK_VER_X}.${SPARK_VER_Y}"
        export DRIVER_AGENT_ARGS="${base_agent},config=driver"
        export EXECUTOR_AGENT_ARGS="${base_agent},config=executor"
    fi
}

###############################################################################################
# Installs the Unravel Spark sensor                                                           #
#                                                                                             #
# Requires:                                                                                   #
#  - UNRAVEL_SERVER                                                                           #
#  - UNRAVEL_RESTSERVER_HOST_AND_PORT                                                         #
#  - TMP_DIR                                                                                  #
#  - SPARK_CONF_DEST                                                                          #
#  - SPARK_HOME                                                                               #
# Accepts:                                                                                    #
#  - SPARK_VER_XYZ                                                                            #
#  - UNRAVEL_SPARK_DEST_OWNER       user (default root)                                       #
#  - UNRAVEL_SPARK_DEST             folder (default /usr/local/unravel-spark)                 #
#  - SPARK_APP_LOAD_MODE            Spark App loading mode {DEV | OPS | BATCH} (default OPS)  #
#  - ZEPPELIN_CONF_DIR                                                                        #
###############################################################################################
function spark_install() {
    if spark_already_configured; then
        echo "Unravel Spark Sensor already installed" | tee -a ${OUT_FILE}
        return
    fi

    if isFunction spark_install_impl; then
      spark_install_impl
      return
    fi

    isFunction spark_env_setup && spark_env_setup

    resolve_spark_version
    if [ ! -z "$SPARK_VER_X" ] && [ ! -z "$SPARK_VER_X" ] && [ ! -z "$SPARK_VER_Z" ]; then
        fetch_sensor_zip

        resolve_agent_args

        #install_spark_conf

        append_to_zeppelin

        spark_postinstall_check
        return $?
    else
        echo "Spark is unavailable. Skipping Spark integration" | tee -a ${OUT_FILE}
    fi
}

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

###############################################################################################
# Convenience wrapper for installation or removal of the Unravel Spark sensor                 #
#                                                                                             #
# The first argument is the desired command {install, uninstall}. The rest of the arguments   #
# depends on the accepted argument set of the target command.                                 #
# Requires:                                                                                   #
#  - spark_install()                                                                          #
#  - spark_uninstall()                                                                        #
###############################################################################################
function spark_setup() {
  CMD=$1
  shift
  case $CMD in
    install ) spark_install $*;;
    uninstall ) spark_uninstall $*;;
    ? ) echo "Unknown command $CMD for 'spark_setup' function" | tee -a ${OUT_FILE}
  esac
}

###############################################################################################
# Performs post-installation sanity checks                                                    #
#                                                                                             #
# Requires:                                                                                   #
#  - DRIVER_AGENT_ARGS                                                                        #
#  - EXECUTOR_AGENT_ARGS                                                                      #
#  - SPARK_CONF_DEST                                                                          #
# Accepts:                                                                                    #
#  - spark_postinstall_check_impl()                                                           #
###############################################################################################
function spark_postinstall_check() {
  local ret=0
  local owner

  if isFunction spark_postinstall_check_impl; then
    spark_postinstall_check_impl
    return
  fi

  echo "Validating Spark sensor installation ..." | tee -a ${OUT_FILE}

  if [ ! -d $AGENT_DST ]; then
    echo "ERROR: Directory $AGENT_DST was not created" | tee -a ${OUT_FILE}
    ret=1
  else
    owner=$(ls -ld $AGENT_DST | awk '{print $3 ":" $4}')
    if [ "$owner" != "$AGENT_DST_OWNER" ]; then
      echo "ERROR: Invalid owner of $AGENT_DSST. Expecting $AGENT_DST_OWNER but got $owner" | tee -a ${OUT_FILE}
      ret=1
    fi
    if [ ! "$(find $AGENT_DST -type f -name 'unravel-agent-pack-bin.zip')" ]; then
      echo "ERROR: Spark sensor archive not present in $AGENT_DST" | tee -a ${OUT_FILE}
      ret=1
    fi
  fi
  if [ ! -d $AGENT_JARS ]; then
    echo "ERROR: Directory $AGENT_JARS was not created" | tee -a ${OUT_FILE}
    ret=1
  else
    if [ ! "$(find $AGENT_JARS -type f -name '*spark*.jar')" ]; then
      echo "ERROR: Spark sensor jars are missing in $AGENT_JARS" | tee -a ${OUT_FILE}
      ret=1
    fi
  fi
  if [ -d $SPARK_CONF_DEST ]; then
    if [ ! -e "$SPARK_CONF_DEST/spark-defaults.conf.pre_unravel" ]; then
      echo "ERROR: Missing $SPARK_CONF_DEST/spark-defaults.conf.pre_unravel file" | tee -a ${OUT_FILE}
      ret=1
    else
      if cmp -s "$SPARK_CONF_DEST/spark-defaults.conf" "$SPARK_CONF_DEST/spark-defaults.conf.pre_unravel"; then
        echo "ERROR: $SPARK_CONF_DEST/spark-defaults.conf and $SPARK_CONF_DEST/spark-defaults.conf.pre_unravel are identical. Unravel settings might be missing" | tee -a ${OUT_FILE}
        ret=1
      fi
      if [ ! -e "$SPARK_CONF_DEST/spark-defaults.conf.unravel" ]; then
        echo "ERROR: Missing $SPARK_CONF_DEST/spark-defaults.conf.unravel" | tee -a ${OUT_FILE}
        ret = 1
      fi
    fi

    cat ${SPARK_CONF_DEST}/spark-defaults.conf | fgrep "$EXECUTOR_AGENT_ARGS" 1>/dev/null 2>/dev/null
    [ 0 -ne $? ] && echo "ERROR: Missing spark config modifications for executor probe" | tee -a ${OUT_FILE} && ret = 1

    cat ${SPARK_CONF_DEST}/spark-defaults.conf | fgrep "$DRIVER_AGENT_ARGS" 1>/dev/null 2>/dev/null
    [ 0 -ne $? ] && echo "ERROR: Missing spark config modifications for driver probe" | tee -a ${OUT_FILE} && ret = 1
  fi


  if [ $ret ]; then
    echo "Spark sensor installation validated" | tee -a ${OUT_FILE}
  else
    echo "Spark sensor installation validation failed" | tee -a ${OUT_FILE}
  fi

  return $ret
}

# Unravel integration installation support

function install_usage() {
    echo "Usage: $(basename ${BASH_SOURCE[0]}) install <options>" | tee -a ${OUT_FILE}
    echo "Supported options:" | tee -a ${OUT_FILE}
    echo "  -y                  unattended install" | tee -a ${OUT_FILE}
    echo "  -v                  verbose mode" | tee -a ${OUT_FILE}
    echo "  -h                  usage" | tee -a ${OUT_FILE}
    echo "  --unravel-server    unravel_host:port (required)" | tee -a ${OUT_FILE}
    echo "  --unravel-receiver  unravel_restserver:port" | tee -a ${OUT_FILE}
    echo "  --hive-version      installed hive version" | tee -a ${OUT_FILE}
    echo "  --spark-version     installed spark version" | tee -a ${OUT_FILE}
    echo "  --spark-load-mode   sensor mode [DEV | OPS | BATCH]" | tee -a ${OUT_FILE}
    echo "  --env               comma separated <key=value> env variables" | tee -a ${OUT_FILE}
    echo "  --enable-am-polling Enable Auto Action AM Metrics Polling" | tee -a ${OUT_FILE}
    echo "  --disable-aa        Disable Auto Action" | tee -a ${OUT_FILE}
    echo "  --rm-userid         Yarn resource manager webui username" | tee -a ${OUT_FILE}
    echo "  --rm-password       Yarn resource manager webui password" | tee -a ${OUT_FILE}
    echo "  --user-id           User id to run Unravel Daemon" | tee -a ${OUT_FILE}
    echo "  --group-id          Group id to run Unravel Daemon" | tee -a ${OUT_FILE}
    echo "  --keytab-file       Path to the kerberos keytab file that will be used to kinit" | tee -a ${OUT_FILE}
    echo "  --principal         Kerberos principal name that will be used to kinit" | tee -a ${OUT_FILE}
}

function install_hivehook() {
    if isFunction can_install_hivehook; then
        can_install_hivehook
        if [ 0 -ne $? ]; then
            echo "Node is not eligible for Unravel HiveHook installation. Skipping" | tee -a ${OUT_FILE}
            return
        fi
    fi

    if [ -z "$UNATTENDED" ]; then
        read -p 'Install Unravel hivehook? [Yn]: ' res
        case $res in
            [nN]) return ;;
            [yY]) ;; #continue
            ?) return ;;
        esac
    fi

    echo "Installing Unravel hivehook ..." | tee -a ${OUT_FILE}
    resolve_hive_version

    if [ -z "$HIVE_VER_XYZ" ]; then
        echo "Missing HIVE_VER_XYZ value. Can not install hivehook. Skipping" | tee -a ${OUT_FILE}
        return
    fi
    hivehook_setup install
    echo "... done" | tee -a ${OUT_FILE}
}

function install_es() {
    if isFunction can_install_es; then
        can_install_es
        if [ 0 -ne $? ]; then
            echo "Node is not eligible for unravel_es installation since it is not a master node. Skipping" | tee -a ${OUT_FILE}
            return
        fi
    fi

    if [ -z "$UNATTENDED" ]; then
        read -p 'Install Unravel MR sensor (unravel_es)? [Yn]: ' res
        case $res in
            [nN]) return ;;
            [yY]) ;; #continue
            ?) return ;;
        esac
    fi

    echo "Installing Unravel MR sensor (unravel_es) ..." | tee -a ${OUT_FILE}

    es_setup install
    echo "... done" | tee -a ${OUT_FILE}
}

function install_spark() {
    if isFunction can_install_spark; then
        can_install_spark
        if [ 0 -ne $? ]; then
            echo "Node is not eligible for Unravel Spark sensor installation. Skipping" | tee -a ${OUT_FILE}
            return
        fi
    fi

    if [ -z "$UNATTENDED" ]; then
        read -p 'Install Unravel Spark sensor [Yn]: ' res
        case $res in
            [nN]) return ;;
            [yY]) ;; #continue
            ?) return ;;
        esac
    fi
    echo "Installing Unravel Spark sensor ..." | tee -a ${OUT_FILE}

    spark_setup install
    echo "... done" | tee -a ${OUT_FILE}
}

function install() {
    if [ 0 -eq $# ]; then
        install_usage
        exit 0
    fi

    WGET=$(which wget 2>/dev/null)
    UNZIP=$(which unzip 2>/dev/null)

    DEPS_OK=0
    METRICS_FACTOR=1
    ENABLE_AA=true
    AM_POLLING=false
    HIVE_ID_CACHE=1000
    UNRAVEL_ES_USER=hdfs
    UNRAVEL_ES_GROUP=hadoop
    RM_USER=a
    RM_PASSWORD=a
    KEYTAB_PATH='/etc/security/keytabs/ambari.server.keytab'
    DFS_PATH='/tmp/unravel-sensors/'

    if [ -z "$WGET" ]; then
      echo "ERROR: 'wget' is not available. Please, install it and rerun the setup" | tee -a ${OUT_FILE}
      DEPS_OK=1
    fi

    if [ -z "$UNZIP" ]; then
      echo "ERROR: 'unzip' is not available. Please, install it and rerun the setup" | tee -a ${OUT_FILE}
      DEPS_OK=1
    fi

    if [ $DEPS_OK -ne 0 ]; then
      [ $ALLOW_ERRORS ] && exit 1
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
            "hive-version" | "--hive-version" )
                export HIVE_VER_XYZ=$1
                shift
                ;;
            "spark-version" | "--spark-version" )
                export SPARK_VER_XYZ=$1
                shift
                ;;
            "spark-load-mode" | "--spark-load-mode" )
                export SPARK_APP_LOAD_MODE=$1
                shift
                ;;
            "env" | "--env")
                for ENV in "$(echo $1 | tr ',' ' ')"; do
                  eval "export $ENV"
                done
                shift
                ;;
            "uninstall" | "--uninstall")
                export UNINSTALL=True
                ;;
            "metrics-factor" | "--metrics-factor")
                export METRICS_FACTOR=$1
                shift
                ;;
            "all" | "--all")
                export ENABLE_ALL_SENSOR=True
                ;;
            "enable-am-polling" | "--enable-am-polling")
                export AM_POLLING=true
                ;;
            "disable-aa" | "--disable-aa")
                export ENABLE_AA=false
                ;;
            "hive-id-cache" | "--hive-id-cache")
                export HIVE_ID_CACHE=$1
                shift
                ;;
            "--user-id")
                export UNRAVEL_ES_USER=$1
                shift
                ;;
            "--group-id")
                export UNRAVEL_ES_GROUP=$1
                shift
                ;;
            "--keytab-file")
                export KEYTAB_PATH=$1
                shift
                ;;
            "--principal")
                export KEYTAB_PRINCIPAL=$1
                shift
                ;;
            "--rm-userid")
                export RM_USER=$1
                shift
                ;;
            "--rm-password")
                export RM_PASSWORD=$1
                shift
                ;;
            "--sensor-url")
                export SENSOR_URL=$1
                shift
                ;;
            "--sensor-dfs-path")
                export DFS_PATH=$1
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

    # construct default principal name
    if [ -z $KEYTAB_PRINCIPAL ]; then
        DEFAULT_REALM=`cat /etc/krb5.conf | grep default_realm | awk '{ print $3 }'`
        KEYTAB_PRINCIPAL="ambari-server-$CLUSTER_ID@$DEFAULT_REALM"
    fi

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

    install_hivehook
    install_es
    install_spark
}

function  is_secure() {
    result=$(curl -u $AMBARI_USR:"$AMBARI_PWD" http://headnodehost:$AMBARI_PORT/api/v1/clusters/$CLUSTER_ID | \
    python -c 'import sys,json; print(json.load(sys.stdin)["Clusters"]["security_type"].strip())')
    echo "Checking Security Type"
    echo "Security Type: $result"
    if [ $result == 'KERBEROS' ]; then
      return 0
    else
      return 1
    fi
}

PLATFORM="HDI"

echo "AMBARI_PORT before: ${AMBARI_PORT}"
[ -z "$AMBARI_PORT" ] && export AMBARI_PORT=8080
echo "AMBARI_PORT after: ${AMBARI_PORT}"

HEADIP=`ping -c 1 headnodehost | grep PING | awk '{print $3}' | tr -d '()'`
[ -z "$AMBARI_HOST" ] && export AMBARI_HOST=$HEADIP
echo "AMBARI_HOST: ${AMBARI_HOST}"

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


###############################################################################################
#   START OF HDInsightUtilities-v01.sh
#
###############################################################################################
function download_file {
    srcurl=$1;
    destfile=$2;
    overwrite=$3;

    if [ "$overwrite" = false ] && [ -e $destfile ]; then
        return;
    fi

    wget -O $destfile -q $srcurl;
}

function untar_file
{
    zippedfile=$1;
    unzipdir=$2;

    if [ -e $zippedfile ]; then
        tar -xf $zippedfile -C $unzipdir;
    fi
}

function test_is_headnode
{
    shorthostname=`hostname -s`
    if [[  $shorthostname == headnode* || $shorthostname == hn* ]]; then
        echo 1;
    else
        echo 0;
    fi
}

function test_is_datanode
{
    shorthostname=`hostname -s`
    if [[ $shorthostname == workernode* || $shorthostname == wn* ]]; then
        echo 1;
    else
        echo 0;
    fi
}

function test_is_zookeepernode
{
    shorthostname=`hostname -s`
    if [[ $shorthostname == zookeepernode* || $shorthostname == zk* ]]; then
        echo 1;
    else
        echo 0;
    fi
}

function test_is_first_datanode
{
    shorthostname=`hostname -s`
    if [[ $shorthostname == workernode0 || $shorthostname == wn0-* ]]; then
        echo 1;
    else
        echo 0;
    fi
}

#following functions are used to determine headnodes.
#Returns fully qualified headnode names separated by comma by inspecting hdfs-site.xml.
#Returns empty string in case of errors.
function get_headnodes
{
    hdfssitepath=/etc/hadoop/conf/hdfs-site.xml
    nn1=$(sed -n '/<name>dfs.namenode.http-address.mycluster.nn1/,/<\/value>/p' $hdfssitepath)
    nn2=$(sed -n '/<name>dfs.namenode.http-address.mycluster.nn2/,/<\/value>/p' $hdfssitepath)

    nn1host=$(sed -n -e 's/.*<value>\(.*\)<\/value>.*/\1/p' <<< $nn1 | cut -d ':' -f 1)
    nn2host=$(sed -n -e 's/.*<value>\(.*\)<\/value>.*/\1/p' <<< $nn2 | cut -d ':' -f 1)

    nn1hostnumber=$(sed -n -e 's/hn\(.*\)-.*/\1/p' <<< $nn1host)
    nn2hostnumber=$(sed -n -e 's/hn\(.*\)-.*/\1/p' <<< $nn2host)

    #only if both headnode hostnames could be retrieved, hostnames will be returned
    #else nothing is returned
    if [[ ! -z $nn1host && ! -z $nn2host ]]
    then
        if (( $nn1hostnumber < $nn2hostnumber )); then
                        echo "$nn1host,$nn2host"
        else
                        echo "$nn2host,$nn1host"
        fi
    fi
}

function get_primary_headnode
{
        headnodes=`get_headnodes`
        echo "`(echo $headnodes | cut -d ',' -f 1)`"
}

function get_secondary_headnode
{
        headnodes=`get_headnodes`
        echo "`(echo $headnodes | cut -d ',' -f 2)`"
}

function get_primary_headnode_number
{
        primaryhn=`get_primary_headnode`
        echo "`(sed -n -e 's/hn\(.*\)-.*/\1/p' <<< $primaryhn)`"
}

function get_secondary_headnode_number
{
        secondaryhn=`get_secondary_headnode`
        echo "`(sed -n -e 's/hn\(.*\)-.*/\1/p' <<< $secondaryhn)`"
}
###############################################################################################
#   END OF HDInsightUtilities-v01.sh
#
###############################################################################################


function cluster_detect() {
  # Import the helper method module.
  #wget --timeout=15 -t 2 -O /tmp/HDInsightUtilities-v01.sh -q https://hdiconfigactions.blob.core.windows.net/linuxconfigactionmodulev01/HDInsightUtilities-v01.sh

  #source /tmp/HDInsightUtilities-v01.sh && rm -f /tmp/HDInsightUtilities-v01.sh

  export AMBARI_USR=$(echo -e "import hdinsight_common.Constants as Constants\nprint Constants.AMBARI_WATCHDOG_USERNAME" | python)
  export AMBARI_PWD=$(echo -e "import hdinsight_common.ClusterManifestParser as ClusterManifestParser\nimport hdinsight_common.Constants as Constants\nimport base64\nbase64pwd = ClusterManifestParser.parse_local_manifest().ambari_users.usersmap[Constants.AMBARI_WATCHDOG_USERNAME].password\nprint base64.b64decode(base64pwd)" | python)

  export CLUSTER_ID=$(echo -e "import hdinsight_common.ClusterManifestParser as ClusterManifestParser\nprint ClusterManifestParser.parse_local_manifest().deployment.cluster_name" | python)

  local primary_head_node=$(get_primary_headnode)
  local full_host_name=$(hostname -f)

  echo "AMBARI_USR=$AMBARI_USR" | tee -a ${OUT_FILE}
  # Should not log the Ambari password.
  #echo "AMBARI_PWD=$AMBARI_PWD" | tee -a ${OUT_FILE}

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
  export HOST_ROLE=$HOST_ROLE
}



# Unravel integration for HDP - HiveHook support

# setup env
export HADOOP_CONF=/etc/hadoop/
# hive conf is managed by Ambari
export HIVE_CONF_DEST=
export HIVE_CONF_DEST_OWNER=
export UNRAVEL_HH_DEST_OWNER="root:root"
export UNRAVEL_HH_DEST=/usr/local/unravel_client


function should_install_hh_conf() {
  [ "$HOST_ROLE" == "master" ] && return 0 || return 1
}

function install_hive_site_impl() {
  echo "Installing Unravel HiveHook jar" | tee -a ${OUT_FILE}
  install_hh_jar

  echo "Updating Ambari configurations" | tee -a ${OUT_FILE}

  install_hh_aux_jars

  install_hooks

  stopServiceViaRest HIVE
  stopServiceViaRest OOZIE
  startServiceViaRest HIVE
  startServiceViaRest OOZIE
}

function uninstall_hive_site_impl() {
  echo "Uninstalling Unravel HiveHook jar" | tee -a ${OUT_FILE}

  uninstall_hh_jar

  echo "Updating Ambari configurations" | tee -a ${OUT_FILE}

  uninstall_hh_aux_jars

  uninstall_hooks

  stopServiceViaRest HIVE
  stopServiceViaRest OOZIE
  startServiceViaRest HIVE
  startServiceViaRest OOZIE
}

function set_hivesite_prop() {
  local key=$1
  local val=$2

  echo "Setting hive-site property: $key=$val"
  updateResult=$(bash $AMBARICONFIGS_SH -u $AMBARI_USR -p $AMBARI_PWD set $AMBARI_HOST $CLUSTER_ID hive-site "$key" "$val" 2>/dev/null)

  if [[ $updateResult != *"Tag:version"* ]] && [[ $updateResult == *"[ERROR]"* ]]; then
    echo "[ERROR] Failed to update hive-site" | tee -a ${OUT_FILE}
    echo $updateResult | tee -a ${OUT_FILE}
    return 1
  fi
}

function delete_hivesite_prop() {
  local key=$1

  updateResult=$(bash $AMBARICONFIGS_SH -u $AMBARI_USR -p $AMBARI_PWD delete $AMBARI_HOST $CLUSTER_ID hive-site "$key" 2>/dev/null)

  if [[ $updateResult != *"Tag:version"* ]] && [[ $updateResult == *"[ERROR]"* ]]; then
    echo "[ERROR] Failed to update hive-site" | tee -a ${OUT_FILE}
    echo $updateResult | tee -a ${OUT_FILE}
    return 1
  fi
}

function install_hh_aux_jars() {
  local jars=$(find $UNRAVEL_HH_DEST -iname '*.jar' -type f | sed -e 's|^|file://|' | paste -d, -s)
  local jars_colon=$(find $UNRAVEL_HH_DEST -iname '*.jar' -type f | paste -d: -s)

  currentHiveAuxJarsPath=$(bash $AMBARICONFIGS_SH -u $AMBARI_USR -p $AMBARI_PWD get $AMBARI_HOST $CLUSTER_ID hive-site 2>/dev/null | grep 'hive.aux.jars.path' | sed -n -e 's/.*: "\([^"]*\)".*/\1/p')

  if [ -z "$currentHiveAuxJarsPath" ]; then
    newJars=$jars
  else
    newJars=$currentHiveAuxJarsPath,$jars
  fi

  echo "Modifying hive-site" | tee -a ${OUT_FILE}
  set_hivesite_prop "hive.aux.jars.path" "$newJars"

  currentHiveEnvContent=$(bash $AMBARICONFIGS_SH -u $AMBARI_USR -p $AMBARI_PWD get $AMBARI_HOST $CLUSTER_ID hive-env 2>/dev/null | grep '"content"' | perl -lne 'print $1 if /"content" : "(.*)"/')

  export AuxJars="\nexport HIVE_AUX_JARS_PATH=\$HIVE_AUX_JARS_PATH:$jars_colon"
  newHiveEnvContent="$currentHiveEnvContent$AuxJars"

  echo "Modifying hive-env" | tee -a ${OUT_FILE}

  updateResult=$(bash $1 -u $AMBARI_USR -p $AMBARI_PWD set $AMBARI_HOST $CLUSTER_ID hive-env "content" "$newHiveEnvContent" 2>/dev/null)

  if [[ $updateResult != *"Tag:version"* ]] && [[ $updateResult == *"[ERROR]"* ]]; then
    echo "[ERROR] Failed to update hive-env" | tee -a ${OUT_FILE}
    echo $updateResult | tee -a ${OUT_FILE}
    [ $ALLOW_ERRORS ] && exit 1
  fi

  currentWebHCatEnvContent=$(bash $AMBARICONFIGS_SH -u $AMBARI_USR -p $AMBARI_PWD get $AMBARI_HOST $CLUSTER_ID webhcat-env  2>/dev/null | grep '"content"' | perl -lne 'print $1 if /"content" : "(.*)"/')
  newWebHCatEnvContent="$currentWebHCatEnvContent$AuxJars"

  echo "Modifying webhcat-env" | tee -a ${OUT_FILE}

  updateResult=$(bash $AMBARICONFIGS_SH -u $AMBARI_USR -p $AMBARI_PWD set $AMBARI_HOST $CLUSTER_ID webhcat-env "content" "$newWebHCatEnvContent" 2>/dev/null)

  if [[ $updateResult != *"Tag:version"* ]] && [[ $updateResult == *"[ERROR]"* ]]; then
    echo "[ERROR] Failed to update webhcat-env" | tee -a ${OUT_FILE}
    echo $updateResult | tee -a ${OUT_FILE}
    [ $ALLOW_ERRORS ] && exit 1
  fi

  echo "${currentHiveAuxJarsPath}|${currentHiveEnvContent}|${currentWebHCatEnvContent}" | tee -a $UNRAVEL_HH_DEST/unravel.env.backup
}

function uninstall_hh_aux_jars() {
  IFS=$'|' read -r -a backupEnv <<< $(cat $UNRAVEL_HH_DEST/unravel.env.backup)

  if [ -z "${backupEnv[@]}" ]; then
    echo "No previous Unravel env settings detected" | tee -a ${OUT_FILE}
    return
  fi

  echo "Env backup: ${backupEnv[@]}" | tee -a ${OUT_FILE}

  echo "Restoring hive-site config" | tee -a ${OUT_FILE}
  set_hivesite_prop "hive.aux.jars.path" "${backupEnv[0]}"

  echo "Restoring hive-env config" | tee -a ${OUT_FILE}
  updateResult=$(bash $AMBARICONFIGS_SH -u $AMBARI_USR -p $AMBARI_PWD set $AMBARI_HOST $CLUSTER_ID hive-env "content" "${backupEnv[1]}" 2>/dev/null)

  if [[ $updateResult != *"Tag:version"* ]] && [[ $updateResult == *"[ERROR]"* ]]; then
    echo "[ERROR] Failed to update hive-env" | tee -a ${OUT_FILE}
    echo $updateResult | tee -a ${OUT_FILE}
    [ $ALLOW_ERRORS ] && exit 1
  fi

  echo "Restoring webhcat-env config" | tee -a ${OUT_FILE}
  updateResult=$(bash $AMBARICONFIGS_SH -u $AMBARI_USR -p $AMBARI_PWD set $AMBARI_HOST $CLUSTER_ID webhcat-env "content" "${backupEnv[2]}" 2>/dev/null)

  if [[ $updateResult != *"Tag:version"* ]] && [[ $updateResult == *"[ERROR]"* ]]; then
    echo "[ERROR] Failed to update webhcat-env" | tee -a ${OUT_FILE}
    echo $updateResult | tee -a ${OUT_FILE}
    [ $ALLOW_ERRORS ] && exit 1
  fi
}

function install_hooks() {
  set_hivesite_prop "com.unraveldata.hive.hook.tcp" "true"
  set_hivesite_prop "com.unraveldata.host" "${UNRAVEL_HOST}"
  set_hivesite_prop "com.unraveldata.hive.hdfs.dir" "/user/unravel/HOOK_RESULT_DIR"
  set_hivesite_prop "hive.exec.driver.run.hooks" "com.unraveldata.dataflow.hive.hook.HiveDriverHook"
  set_hivesite_prop "hive.exec.pre.hooks" "com.unraveldata.dataflow.hive.hook.HivePreHook"
  set_hivesite_prop "hive.exec.post.hooks" "com.unraveldata.dataflow.hive.hook.HivePostHook"
  set_hivesite_prop "hive.exec.failure.hooks" "com.unraveldata.dataflow.hive.hook.HiveFailHook"
}

function uninstall_hooks() {
  delete_hivesite_prop "com.unraveldata.hive.hook.tcp"
  delete_hivesite_prop "com.unraveldata.host"
  delete_hivesite_prop "com.unraveldata.hive.hdfs.dir"
  delete_hivesite_prop "hive.exec.driver.run.hooks"
  delete_hivesite_prop "hive.exec.pre.hooks"
  delete_hivesite_prop "hive.exec.post.hooks"
  delete_hivesite_prop "hive.exec.failure.hooks"
}


# Unravel integration for HDInsight - Unravel MR sensor (unravel_es) support

# env

export ES_CLUSTER_TYPE_SWITCH=""


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

################################################################################################
# Do not install unravel_es on non-master nodes                                                #
# Requires:                                                                                    #
#  - HOST_ROLE                                                                                 #
#                                                                                              #
################################################################################################
function can_install_es() {
    if [ "$HOST_ROLE" == "master" ]; then
        return 0
    fi
    return 1
}

################################################################################################
# Test an IP address for validity:                                                             #
# Usage:                                                                                       #
#   valid_ip IP_ADDRESS                                                                        #
# Will return 0 if valid, otherwise, 1                                                         #
################################################################################################
function valid_ip() {
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

################################################################################################
# Check if the Unravel ES config is correct.                                                   #
#                                                                                              #
# Usage:                                                                                       #
#   es_postinstall_check_configs                                                               #
# Will return 0 if valid, otherwise, 1                                                         #
################################################################################################
function es_postinstall_check_configs() {
    if [[ ! -e  /usr/local/unravel_es/etc/unravel_es.properties ]]; then
        echo "ERROR: Did not find /usr/local/unravel_es/etc/unravel_es.properties file." | tee -a ${OUT_FILE}
        return 1
    fi

    FOUND_CLUSTER_ID=`grep -E "^cluster-id=" /usr/local/unravel_es/etc/unravel_es.properties | cut -d '=' -f2`
    FOUND_UNRAVEL_SERVER=`grep -E "^unravel-server=" /usr/local/unravel_es/etc/unravel_es.properties | cut -d'=' -f2 | cut -d':' -f1`

    echo "The unravel_es.properties file contains the following cluster-id=${FOUND_CLUSTER_ID}" | tee -a ${OUT_FILE}
    echo "The unravel_es.properties file contains the following unravel-server=${FOUND_UNRAVEL_SERVER}" | tee -a ${OUT_FILE}

    if [[ -z "$FOUND_CLUSTER_ID" ]]; then
        echo "ERROR: Property cluster-id is missing in unravel_es.properties" | tee -a ${OUT_FILE}
        return 1
    else
        if [[ "$FOUND_CLUSTER_ID" == "j-DEFAULT" ]]; then
            echo "ERROR: Must set cluster-id to a valid value in unravel_es.properties instead of $FOUND_CLUSTER_ID" | tee -a ${OUT_FILE}
            return 1
        fi
    fi

    if [[ -z "$FOUND_UNRAVEL_SERVER" ]]; then
        echo "ERROR: Property unravel-server is missing in unravel_es.properties" | tee -a ${OUT_FILE}
        return 1
    else
        valid_ip "$FOUND_UNRAVEL_SERVER"
        if [[ 0 -ne $? ]]; then
            echo "WARNING: Property unravel-server in unravel_es.properties is not a valid IP address. Check that it's a valid FQDN." | tee -a ${OUT_FILE}
        else
            echo "The unravel-server property is a proper IP"  | tee -a ${OUT_FILE}
        fi
    fi

    return 0
}

function install_service_impl() {
  sudo update-rc.d unravel_es defaults
}



# Unravel integration for HDInsight - Spark support

# setup env
export SPARK_CONF_DEST=
export ZEPPELIN_CONF_DIR=
export UNRAVEL_SPARK_DEST=/usr/local/unravel-agent
export UNRAVEL_SPARK_DEST_OWNER="root:root"
export SPARK_SENSOR_JARS=${UNRAVEL_SPARK_DEST}/jars

function should_install_spark_conf() {
  [ "$HOST_ROLE" == "master" ] && return 0 || return 1
}

function spark_install_impl() {
    isFunction spark_env_setup && spark_env_setup
    fetch_sensor_zip

    if isFunction should_install_spark_conf; then
        should_install_spark_conf
        if [ 1 -eq $? ]; then
            echo "System is not eligible for Spark configuration modifications" | tee -a ${OUT_FILE}
            return
        fi
    fi

    resolve_spark_version
    if [ ! -z "$SPARK_VER_X" ] && [ ! -z "$SPARK_VER_X" ] && [ ! -z "$SPARK_VER_Z" ]; then

        resolve_agent_args

        install_spark_conf

        append_to_zeppelin

        spark_postinstall_check
        return $?
    else
        echo "Spark is unavailable. Skipping Spark integration" | tee -a ${OUT_FILE}
    fi
}

function install_spark_conf_impl() {

  echo "Updating Ambari configurations" | tee -a ${OUT_FILE}
  install_spark_defaults_conf

  stopServiceViaRest SPARK
  startServiceViaRest SPARK

  stopServiceViaRest SPARK2
  startServiceViaRest SPARK2
}

function uninstall_spark_conf_impl() {

  echo "Updating Ambari configurations" | tee -a ${OUT_FILE}
  uninstall_spark_defaults_conf

  stopServiceViaRest SPARK
  startServiceViaRest SPARK

  stopServiceViaRest SPARK2
  startServiceViaRest SPARK2

}

function set_sparkdefaults_prop() {
  local key=$1
  local val=$2

  echo "Setting spark-defaults property: $key=$val"
  updateResult=$(bash $AMBARICONFIGS_SH -u $AMBARI_USR -p $AMBARI_PWD set $AMBARI_HOST $CLUSTER_ID spark-defaults "$key" "$val" 2>/dev/null)

  if [[ $updateResult != *"Tag:version"* ]] && [[ $updateResult == *"[ERROR]"* ]]; then
    updateResult=$(bash $AMBARICONFIGS_SH -u $AMBARI_USR -p $AMBARI_PWD set $AMBARI_HOST $CLUSTER_ID spark2-defaults "$key" "$val" 2>/dev/null)
    if [[ $updateResult != *"Tag:version"* ]] && [[ $updateResult == *"[ERROR]"* ]]; then
	echo "[ERROR] Failed to update spark-defaults" | tee -a ${OUT_FILE}
	echo $updateResult | tee -a ${OUT_FILE}
	return 1
    fi
  fi
}

function delete_sparkdefaults_prop() {
  local key=$1

  updateResult=$(bash $AMBARICONFIGS_SH -u $AMBARI_USR -p $AMBARI_PWD delete $AMBARI_HOST $CLUSTER_ID spark-defaults "$key" 2>/dev/null)

  if [[ $updateResult != *"Tag:version"* ]] && [[ $updateResult == *"[ERROR]"* ]]; then
    echo "[ERROR] Failed to update hive-site" | tee -a ${OUT_FILE}
    echo $updateResult | tee -a ${OUT_FILE}
    return 1
  fi
}

function install_spark_defaults_conf() {

  currentDriverExJavaOpt=$(bash $AMBARICONFIGS_SH -u $AMBARI_USR -p $AMBARI_PWD get $AMBARI_HOST $CLUSTER_ID spark-defaults 2>/dev/null | grep 'spark.driver.extraJavaOptions' | sed -n -e 's/.*: "\([^"]*\)".*/\1/p')

  if [ -z "$currentDriverExJavaOpt" ]; then
    newDriverExJavaOpts=$DRIVER_AGENT_ARGS
  else
    newDriverExJavaOpts="$currentDriverExJavaOpt $DRIVER_AGENT_ARGS"
  fi

  echo "Modifying spark-defaults" | tee -a ${OUT_FILE}
  set_sparkdefaults_prop "spark.driver.extraJavaOptions" "$newDriverExJavaOpts"

  currentExecutorExJavaOpt=$(bash $AMBARICONFIGS_SH -u $AMBARI_USR -p $AMBARI_PWD get $AMBARI_HOST $CLUSTER_ID spark-defaults 2>/dev/null | grep 'spark.executor.extraJavaOptions' | sed -n -e 's/.*: "\([^"]*\)".*/\1/p')

  if [ -z "$currentExecutorExJavaOpt" ]; then
    newExecutorExJavaOpts=$EXECUTOR_AGENT_ARGS
  else
    newExecutorExJavaOpts="$currentExecutorExJavaOpt $EXECUTOR_AGENT_ARGS"
  fi

  echo "Modifying spark-defaults" | tee -a ${OUT_FILE}
  set_sparkdefaults_prop "spark.executor.extraJavaOptions" "$newExecutorExJavaOpts"

  set_sparkdefaults_prop spark.unravel.server.hostport ${UNRAVEL_RESTSERVER_HOST_AND_PORT}

  local EVENTLOG_DEFAULT_PATH="/var/log/spark/apps"
  local hdfs_url=$(bash $AMBARICONFIGS_SH -u $AMBARI_USR -p $AMBARI_PWD get $AMBARI_HOST $CLUSTER_ID core-site 2>/dev/null | grep -m 1 'fs.defaultFS' | sed -n -e 's/.*: "\([^"]*\)".*/\1/p')

  local existing_eventLog_entry=$( bash $AMBARICONFIGS_SH -u $AMBARI_USR -p $AMBARI_PWD get $AMBARI_HOST $CLUSTER_ID spark-defaults 2>/dev/null | grep 'spark.eventLog.dir' |sed -n -e 's/.*: "\([^"]*\)".*/\1/p')
  local protocol_hdfs="hdfs://"
  local protocol_file="file://"
  local protocol_wasb="wasb://"
  # by default set eventlog_without_file_protocol to EVENTLOG_DEFAULT_PATH
  local eventlog_without_file_protocol=${EVENTLOG_DEFAULT_PATH}


  # create the complete path, inclusing hdfs protocol, the host:port, and path
  local eventlog_path=""

  # take the value corresponding to "spark.eventLog.dir" and remove the protocol and host:port portion

  if [ ! -z "$existing_eventLog_entry" ]; then
    eventlog_without_file_protocol=$(echo ${existing_eventLog_entry} | sed "s;^$protocol_hdfs;;" | sed "s;^$protocol_file;;" | sed "s;^$protocol_wasb;;")
    # cut host:port portion
    hostPort=$(echo $eventlog_without_file_protocol | cut -d "/" -f 1)
    eventlog_without_file_protocol=${eventlog_without_file_protocol:${#hostPort}}
    eventlog_path=${hdfs_url}${eventlog_without_file_protocol}
    echo "HDFS URL: ${hdfs_url}" | tee -a ${OUT_FILE}
    echo "Event log file location: $eventlog_path" | tee -a ${OUT_FILE}
  else
    eventlog_path=${hdfs_url}${eventlog_without_file_protocol}
  fi

  set_sparkdefaults_prop "spark.eventLog.dir" "$eventlog_path"
  set_sparkdefaults_prop "spark.history.fs.logDirectory" "$eventlog_path"

  echo "${currentDriverExJavaOpt}|${currentExecutorExJavaOpt}" | tee -a $UNRAVEL_SPARK_DEST/unravel.env.backup
}

function uninstall_spark_defaults_conf() {
  IFS=$'|' read -r -a backupEnv <<< $(cat $UNRAVEL_SPARK_DEST/unravel.env.backup)

  if [ -z "${backupEnv[@]}" ]; then
    echo "No previous Unravel env settings detected" | tee -a ${OUT_FILE}
    return
  fi

  echo "Env backup: ${backupEnv[@]}" | tee -a ${OUT_FILE}

  echo "Restoring spark-defaults config" | tee -a ${OUT_FILE}
  set_sparkdefaults_prop "spark.driver.extraJavaOptions" "${backupEnv[0]}"

  echo "Restoring spark-defaults config" | tee -a ${OUT_FILE}
  set_sparkdefaults_prop "spark.executor.extraJavaOptions" "${backupEnv[1]}"

  delete_sparkdefaults_prop spark.unravel.server.hostport


}

function spark_postinstall_check_impl() {
  echo "Validating Spark sensor installation ..." | tee -a ${OUT_FILE}

  if [ ! -d $AGENT_DST ]; then
    echo "ERROR: Directory $AGENT_DST was not created" | tee -a ${OUT_FILE}
    ret=1
  else
    owner=$(ls -ld $AGENT_DST | awk '{print $3 ":" $4}')
    if [ "$owner" != "$AGENT_DST_OWNER" ]; then
      echo "ERROR: Invalid owner of $AGENT_DSST. Expecting $AGENT_DST_OWNER but got $owner" | tee -a ${OUT_FILE}
      ret=1
    fi
    if [ ! "$(find $AGENT_DST -type f -name 'unravel-agent-pack-bin.zip')" ]; then
      echo "ERROR: Spark sensor archive not present in $AGENT_DST" | tee -a ${OUT_FILE}
      ret=1
    fi
  fi
  if [ ! -d $AGENT_JARS ]; then
    echo "ERROR: Directory $AGENT_JARS was not created" | tee -a ${OUT_FILE}
    ret=1
  else
    if [ ! "$(find $AGENT_JARS -type f -name '*spark*.jar')" ]; then
      echo "ERROR: Spark sensor jars are missing in $AGENT_JARS" | tee -a ${OUT_FILE}
      ret=1
    fi
  fi
  if [ $ret ]; then
    echo "Spark sensor installation validated" | tee -a ${OUT_FILE}
  else
    echo "Spark sensor installation validation failed" | tee -a ${OUT_FILE}
  fi

  return $ret

}

function configs_py(){
    echo "\
#!/usr/bin/env python
'''
Licensed to the Apache Software Foundation (ASF) under one
or more contributor license agreements.  See the NOTICE file
distributed with this work for additional information
regarding copyright ownership.  The ASF licenses this file
to you under the Apache License, Version 2.0 (the
\"License\"); you may not use this file except in compliance
with the License.  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an \"AS IS\" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
'''
import optparse
from optparse import OptionGroup
import sys
import urllib2
import time
import json
import base64
import xml
import xml.etree.ElementTree as ET
import os
import logging

logger = logging.getLogger('AmbariConfig')

HTTP_PROTOCOL = 'http'
HTTPS_PROTOCOL = 'https'

SET_ACTION = 'set'
GET_ACTION = 'get'
DELETE_ACTION = 'delete'

GET_REQUEST_TYPE = 'GET'
PUT_REQUEST_TYPE = 'PUT'

# JSON Keywords
PROPERTIES = 'properties'
ATTRIBUTES = 'properties_attributes'
CLUSTERS = 'Clusters'
DESIRED_CONFIGS = 'desired_configs'
TYPE = 'type'
TAG = 'tag'
ITEMS = 'items'
TAG_PREFIX = 'version'

CLUSTERS_URL = '/api/v1/clusters/{0}'
DESIRED_CONFIGS_URL = CLUSTERS_URL + '?fields=Clusters/desired_configs'
CONFIGURATION_URL = CLUSTERS_URL + '/configurations?type={1}&tag={2}'

FILE_FORMAT = \
\"\"\"
\"properties\": {
  \"key1\": \"value1\"
  \"key2\": \"value2\"
},
\"properties_attributes\": {
  \"attribute\": {
    \"key1\": \"value1\"
    \"key2\": \"value2\"
  }
}
\"\"\"

class UsageException(Exception):
  pass

def api_accessor(host, login, password, protocol, port):
  def do_request(api_url, request_type=GET_REQUEST_TYPE, request_body=''):
    try:
      url = '{0}://{1}:{2}{3}'.format(protocol, host, port, api_url)
      admin_auth = base64.encodestring('%s:%s' % (login, password)).replace('\n', '')
      request = urllib2.Request(url)
      request.add_header('Authorization', 'Basic %s' % admin_auth)
      request.add_header('X-Requested-By', 'ambari')
      request.add_data(request_body)
      request.get_method = lambda: request_type
      response = urllib2.urlopen(request)
      response_body = response.read()
    except Exception as exc:
      raise Exception('Problem with accessing api. Reason: {0}'.format(exc))
    return response_body
  return do_request

def get_config_tag(cluster, config_type, accessor):
  response = accessor(DESIRED_CONFIGS_URL.format(cluster))
  try:
    desired_tags = json.loads(response)
    current_config_tag = desired_tags[CLUSTERS][DESIRED_CONFIGS][config_type][TAG]
  except Exception as exc:
    raise Exception('\"{0}\" not found in server response. Response:\n{1}'.format(config_type, response))
  return current_config_tag

def create_new_desired_config(cluster, config_type, properties, attributes, accessor):
  new_tag = TAG_PREFIX + str(int(time.time() * 1000000))
  new_config = {
    CLUSTERS: {
      DESIRED_CONFIGS: {
        TYPE: config_type,
        TAG: new_tag,
        PROPERTIES: properties
      }
    }
  }
  if len(attributes.keys()) > 0:
    new_config[CLUSTERS][DESIRED_CONFIGS][ATTRIBUTES] = attributes
  request_body = json.dumps(new_config)
  new_file = 'doSet_{0}.json'.format(new_tag)
  logger.info('### PUTting json into: {0}'.format(new_file))
  output_to_file(new_file)(new_config)
  accessor(CLUSTERS_URL.format(cluster), PUT_REQUEST_TYPE, request_body)
  logger.info('### NEW Site:{0}, Tag:{1}'.format(config_type, new_tag))

def get_current_config(cluster, config_type, accessor):
  config_tag = get_config_tag(cluster, config_type, accessor)
  logger.info(\"### on (Site:{0}, Tag:{1})\".format(config_type, config_tag))
  response = accessor(CONFIGURATION_URL.format(cluster, config_type, config_tag))
  config_by_tag = json.loads(response)
  current_config = config_by_tag[ITEMS][0]
  return current_config[PROPERTIES], current_config.get(ATTRIBUTES, {})

def update_config(cluster, config_type, config_updater, accessor):
  properties, attributes = config_updater(cluster, config_type, accessor)
  create_new_desired_config(cluster, config_type, properties, attributes, accessor)

def update_specific_property(config_name, config_value):
  def update(cluster, config_type, accessor):
    properties, attributes = get_current_config(cluster, config_type, accessor)
    properties[config_name] = config_value
    return properties, attributes
  return update

def update_from_xml(config_file):
  def update(cluster, config_type, accessor):
    return read_xml_data_to_map(config_file)
  return update

# Used DOM parser to read data into a map
def read_xml_data_to_map(path):
  configurations = {}
  properties_attributes = {}
  tree = ET.parse(path)
  root = tree.getroot()
  for properties in root.getiterator('property'):
    name = properties.find('name')
    value = properties.find('value')
    final = properties.find('final')

    if name != None:
      name_text = name.text if name.text else \"\"
    else:
      logger.warn(\"No name is found for one of the properties in {0}, ignoring it\".format(path))
      continue

    if value != None:
      value_text = value.text if value.text else \"\"
    else:
      logger.warn('No value is found for \"{0}\" in {1}, using empty string for it'.format(name_text, path))
      value_text = \"\"

    if final != None:
      final_text = final.text if final.text else \"\"
      properties_attributes[name_text] = final_text

    configurations[name_text] = value_text
  return configurations, {\"final\" : properties_attributes}

def update_from_file(config_file):
  def update(cluster, config_type, accessor):
    try:
      with open(config_file) as in_file:
        file_content = in_file.read()
    except Exception as e:
      raise Exception('Cannot find file \"{0}\" to PUT'.format(config_file))
    try:
      file_properties = json.loads(file_content)
    except Exception as e:
      raise Exception('File \"{0}\" should be in the following JSON format (\"properties_attributes\" is optional):\n{1}'.format(config_file, FILE_FORMAT))
    new_properties = file_properties.get(PROPERTIES, {})
    new_attributes = file_properties.get(ATTRIBUTES, {})
    logger.info('### PUTting file: \"{0}\"'.format(config_file))
    return new_properties, new_attributes
  return update

def delete_specific_property(config_name):
  def update(cluster, config_type, accessor):
    properties, attributes = get_current_config(cluster, config_type, accessor)
    properties.pop(config_name, None)
    for attribute_values in attributes.values():
      attribute_values.pop(config_name, None)
    return properties, attributes
  return update

def output_to_file(filename):
  def output(config):
    with open(filename, 'w') as out_file:
      json.dump(config, out_file, indent=2)
  return output

def output_to_console(config):
  print json.dumps(config, indent=2)

def get_config(cluster, config_type, accessor, output):
  properties, attributes = get_current_config(cluster, config_type, accessor)
  config = {PROPERTIES: properties}
  if len(attributes.keys()) > 0:
    config[ATTRIBUTES] = attributes
  output(config)

def set_properties(cluster, config_type, args, accessor):
  logger.info('### Performing \"set\":')

  if len(args) == 1:
    config_file = args[0]
    root, ext = os.path.splitext(config_file)
    if ext == \".xml\":
      updater = update_from_xml(config_file)
    elif ext == \".json\":
      updater = update_from_file(config_file)
    else:
      logger.error(\"File extension {0} doesn't supported\".format(ext))
      return -1
    logger.info('### from file {0}'.format(config_file))
  else:
    config_name = args[0]
    config_value = args[1]
    updater = update_specific_property(config_name, config_value)
    logger.info('### new property - \"{0}\":\"{1}\"'.format(config_name, config_value))
  update_config(cluster, config_type, updater, accessor)
  return 0

def delete_properties(cluster, config_type, args, accessor):
  logger.info('### Performing \"delete\":')
  if len(args) == 0:
    logger.error(\"Not enough arguments. Expected config key.\")
    return -1

  config_name = args[0]
  logger.info('### on property \"{0}\"'.format(config_name))
  update_config(cluster, config_type, delete_specific_property(config_name), accessor)
  return 0


def get_properties(cluster, config_type, args, accessor):
  logger.info(\"### Performing 'get' content:\")
  if len(args) > 0:
    filename = args[0]
    output = output_to_file(filename)
    logger.info('### to file \"{0}\"'.format(filename))
  else:
    output = output_to_console
  get_config(cluster, config_type, accessor, output)
  return 0

def main():

  parser = optparse.OptionParser(usage=\"usage: %prog [options]\")

  login_options_group = OptionGroup(parser, 'To specify credentials please use \'-e\' OR \'-u\' and \'-p\'')
  login_options_group.add_option(\"-u\", \"--user\", dest=\"user\", default=\"admin\", help=\"Optional user ID to use for authentication. Default is 'admin'\")
  login_options_group.add_option(\"-p\", \"--password\", dest=\"password\", default=\"admin\", help=\"Optional password to use for authentication. Default is 'admin'\")
  login_options_group.add_option(\"-e\", \"--credentials-file\", dest=\"credentials_file\", help=\"Optional file with user credentials separated by new line.\")
  parser.add_option_group(login_options_group)

  parser.add_option(\"-t\", \"--port\", dest=\"port\", default=\"8080\", help=\"Optional port number for Ambari server. Default is '8080'. Provide empty string to not use port.\")
  parser.add_option(\"-s\", \"--protocol\", dest=\"protocol\", default=\"http\", help=\"Optional support of SSL. Default protocol is 'http'\")
  parser.add_option(\"-a\", \"--action\", dest=\"action\", help=\"Script action: <get>, <set>, <delete>\")
  parser.add_option(\"-l\", \"--host\", dest=\"host\", help=\"Server external host name\")
  parser.add_option(\"-n\", \"--cluster\", dest=\"cluster\", help=\"Name given to cluster. Ex: 'c1'\")
  parser.add_option(\"-c\", \"--config-type\", dest=\"config_type\", help=\"One of the various configuration types in Ambari. Ex: core-site, hdfs-site, mapred-queue-acls, etc.\")

  config_options_group = OptionGroup(parser, \"To specify property(s) please use '-f' OR '-k' and '-v'\")
  config_options_group.add_option(\"-f\", \"--file\", dest=\"file\", help=\"File where entire configurations are saved to, or read from. Supported extensions (.xml, .json>)\")
  config_options_group.add_option(\"-k\", \"--key\", dest=\"key\", help=\"Key that has to be set or deleted. Not necessary for 'get' action.\")
  config_options_group.add_option(\"-v\", \"--value\", dest=\"value\", help=\"Optional value to be set. Not necessary for 'get' or 'delete' actions.\")
  parser.add_option_group(config_options_group)

  (options, args) = parser.parse_args()

  logger.setLevel(logging.INFO)
  formatter = logging.Formatter('%(asctime)s %(levelname)s %(message)s')
  stdout_handler = logging.StreamHandler(sys.stdout)
  stdout_handler.setLevel(logging.INFO)
  stdout_handler.setFormatter(formatter)
  logger.addHandler(stdout_handler)

  # options with default value

  if not options.credentials_file and (not options.user or not options.password):
    parser.error(\"You should use option (-e) to set file with Ambari user credentials OR use (-u) username and (-p) password\")

  if options.credentials_file:
    if os.path.isfile(options.credentials_file):
      try:
        with open(options.credentials_file) as credentials_file:
          file_content = credentials_file.read()
          login_lines = filter(None, file_content.splitlines())
          if len(login_lines) == 2:
            user = login_lines[0]
            password = login_lines[1]
          else:
            logger.error(\"Incorrect content of {0} file. File should contain Ambari username and password separated by new line.\".format(options.credentials_file))
            return -1
      except Exception as e:
        logger.error(\"You don't have permissions to {0} file\".format(options.credentials_file))
        return -1
    else:
      logger.error(\"File {0} doesn't exist or you don't have permissions.\".format(options.credentials_file))
      return -1
  else:
    user = options.user
    password = options.password

  port = options.port
  protocol = options.protocol

  #options without default value
  if None in [options.action, options.host, options.cluster, options.config_type]:
    parser.error(\"One of required options is not passed\")

  action = options.action
  host = options.host
  cluster = options.cluster
  config_type = options.config_type

  accessor = api_accessor(host, user, password, protocol, port)
  if action == SET_ACTION:

    if not options.file and (not options.key or not options.value):
      parser.error(\"You should use option (-f) to set file where entire configurations are saved OR (-k) key and (-v) value for one property\")
    if options.file:
      action_args = [options.file]
    else:
      action_args = [options.key, options.value]
    return set_properties(cluster, config_type, action_args, accessor)

  elif action == GET_ACTION:
    if options.file:
      action_args = [options.file]
    else:
      action_args = []
    return get_properties(cluster, config_type, action_args, accessor)

  elif action == DELETE_ACTION:
    if not options.key:
      parser.error(\"You should use option (-k) to set property name witch will be deleted\")
    else:
      action_args = [options.key]
    return delete_properties(cluster, config_type, action_args, accessor)
  else:
    logger.error('Action \"{0}\" is not supported. Supported actions: \"get\", \"set\", \"delete\".'.format(action))
    return -1

if __name__ == \"__main__\":
  try:
    sys.exit(main())
  except (KeyboardInterrupt, EOFError):
    print(\"\nAborting ... Keyboard Interrupt.\")
    sys.exit(1)
" > /tmp/unravel/configs.py
}

function final_check(){
    echo "Running final_check.py in the background"
    cat << EOF > "/tmp/unravel/final_check.py"
#!/usr/bin/env python
#v1.1.7
import urllib2
from subprocess import call, check_output
import json, argparse, re, base64
from time import sleep
import hdinsight_common.Constants as Constants
import hdinsight_common.ClusterManifestParser as ClusterManifestParser

parser = argparse.ArgumentParser()
parser.add_argument('-host', '--unravel-host', help='Unravel Server hostname', dest='unravel', required=True)
parser.add_argument('-protocol', '--unravel-protocol', help='Unravel Server protocol', default="http")
parser.add_argument('--lr-port', help='Unravel Log receiver port', default='4043')
parser.add_argument('--all', help='enable all Unravel Sensor', action='store_true')
parser.add_argument('-user', '--username', help='Ambari login username')
parser.add_argument('-pass', '--password', help='Ambari login password')
parser.add_argument('-c', '--cluster_name', help='ambari cluster name')
parser.add_argument('-s', '--spark_ver', help='spark version')
parser.add_argument('-hive', '--hive_ver', help='hive version', required=True)
parser.add_argument('-l', '--am_host', help='ambari host', required=True)
parser.add_argument('--uninstall', '-uninstall', help='remove unravel configurations from ambari', action='store_true')
parser.add_argument('--metrics-factor', help='Unravel Agent metrics factor ', type=int, default=1)
argv = parser.parse_args()
argv.username = Constants.AMBARI_WATCHDOG_USERNAME
base64pwd = ClusterManifestParser.parse_local_manifest().ambari_users.usersmap[Constants.AMBARI_WATCHDOG_USERNAME].password
argv.password = base64.b64decode(base64pwd)
argv.cluster_name = ClusterManifestParser.parse_local_manifest().deployment.cluster_name
unravel_server = argv.unravel
argv.unravel = argv.unravel.split(':')[0]
argv.spark_ver = argv.spark_ver.split('.')
argv.hive_ver = argv.hive_ver.split('.')
log_dir='/tmp/unravel/'
spark_def_json = log_dir + 'spark-def.json'
hive_env_json = log_dir + 'hive-env.json'
hadoop_env_json = log_dir + 'hadoop-env.json'
mapred_site_json = log_dir + 'mapred-site.json'
hive_site_json = log_dir + 'hive-site.json'
tez_site_json = log_dir + 'tez-site.json'

def am_req(api_name=None, full_api=None):
    if api_name:
        result = json.loads(check_output("curl -u {0}:'{1}' -s -H 'X-RequestedBy:ambari' -X GET http://{2}:8080/api/v1/clusters/{3}/{4}".format(argv.username, argv.password, argv.am_host, argv.cluster_name, api_name), shell=True))
    elif full_api:
        result = json.loads(check_output("curl -u {0}:'{1}' -s -H 'X-RequestedBy:ambari' -X GET {2}".format(argv.username, argv.password,full_api), shell=True))
    return result

#####################################################################
#    Check current configuration and update if not correct          #
#           Give None value if need to skip configuration           #
#####################################################################
def check_configs(hdfs_url=None, hive_env_content=None, hadoop_env_content=None, hive_site_configs=None,
                  spark_defaults_configs=None, mapred_site_configs=None, tez_site_configs=None, uninstall=False):
    # spark-default
    if spark_defaults_configs:
        check_spark_default_configs(uninstall=uninstall)

    # hive-env
    if hive_env_content:
        check_hive_env_content(uninstall)

    # hive-site
    if hive_site_configs:
        check_hive_site_configs(uninstall)

    # hadoop-env
    if hadoop_env_content:
        check_haddop_env_content(uninstall)

    # mapred-site
    if mapred_site_configs:
        check_mapred_site_configs(uninstall)

    #tez-site
    if tez_site_configs:
        check_tez_site_configs(uninstall)

def check_haddop_env_content(uninstall=False):
    get_config('hadoop-env', set_file=hadoop_env_json)
    hadoop_env = read_json(hadoop_env_json)
    found_prop = hadoop_env.find(get_prop_val(hadoop_env_content).split(' ')[1])

    if found_prop > -1 and not uninstall:
        print('\nUnravel HADOOP_CLASSPATH is correct\n')
    else:
        hadoop_env = json.loads(hadoop_env)
        if found_prop > -1 and uninstall:
        # Remove unravel hive hook path
            print('\nUnravel HADOOP_CLASSPATH found, removing\n')
            hadoop_env_regex = get_prop_val(hadoop_env_content).replace("\$", "\\$")
            new_prop = remove_propery(prop_val=hadoop_env['properties']['content'], prop_regex=hadoop_env_regex)
            hadoop_env['properties']['content'] = new_prop
        elif uninstall:
            pass
        elif not found_prop > -1:
            print('\nUnravel HADOOP_CLASSPATH is missing, updating\n')
            content = hadoop_env['properties']['content']
            print('Haddop-env content: ', content)
            hadoop_env['properties']['content'] = content + '\n' + get_prop_val(hadoop_env_content)
        write_json(hadoop_env_json, json.dumps(hadoop_env))
        update_config('hadoop-env', set_file=hadoop_env_json)
    sleep(5)

def check_hive_env_content(uninstall=False):
    get_config('hive-env', set_file=hive_env_json)
    hive_env = read_json(hive_env_json)
    found_prop = get_prop_val(hive_env_content).split(' ')[1] in hive_env
    if found_prop and not uninstall:
        print('\nUnravel AUX_CLASSPATH is in hive-env\n')
    else:
        hive_env = json.loads(hive_env)
        if found_prop and uninstall:
                print('\nUnravel HADOOP_CLASSPATH found, removing\n')
                hive_env_regex = get_prop_val(hive_env_content).replace('\$', '\\$')
                new_prop = remove_propery(prop_val=hive_env['properties']['content'], prop_regex=hive_env_regex)
                hive_env['properties']['content'] = new_prop
        elif uninstall:
            pass
        elif not found_prop:
            print('\n\nUnravel AUX_CLASSPATH is missing\n')
            content = hive_env['properties']['content']
            print('Current hive-env content: ', content)
            hive_env['properties']['content'] = content + '\n' + get_prop_val(hive_env_content)
        write_json(hive_env_json, json.dumps(hive_env))
        update_config('hive-env', set_file=hive_env_json)
        sleep(5)

def check_hive_site_configs(uninstall=False):
    get_config('hive-site', set_file=hive_site_json)
    hive_site = read_json(hive_site_json)
    try:
        check_hive_site = all(get_prop_val(x) in hive_site for _, x in hive_site_configs.iteritems())
    except Exception as e:
        print(e)
        check_hive_site = False
    if check_hive_site and not uninstall:
        print('\nUnravel Custom hive-site configs correct\n')
    else:
        hive_site = json.loads(hive_site)
        if uninstall:
            for key, val in hive_site_configs.iteritems():
                if hive_site['properties'].get(key, None) and get_prop_val(val) in hive_site['properties'][key]:
                    print('\nUnravel Custom hive-site config {0} found, removing\n'.format(key))
                    hive_site['properties'][key] = remove_propery(prop_val=hive_site['properties'][key],
                                                                  prop_regex=',?' + get_prop_val(val))
        elif not check_hive_site:
            print('\n\nUnravel Custom hive-site configs are missing\n')

            for key, val in hive_site_configs.iteritems():
                try:
                    print('Current: ' + key + ': ', hive_site['properties'][key])
                    if re.match('hive.exec.(pre|post|failure).hooks', key) and get_prop_val(val) not in hive_site['properties'][key]:
                        hive_site['properties'][key] += ',' + get_prop_val(val)
                    elif re.match('hive.exec.(pre|post|failure).hooks', key):
                        pass
                    else:
                        hive_site['properties'][key] = get_prop_val(val)
                except:
                    print (key + ': ', 'None')
                    hive_site['properties'][key] = get_prop_val(val)
        write_json(hive_site_json, json.dumps(hive_site))
        update_config('hive-site', set_file=hive_site_json)
    sleep(5)

def check_mapred_site_configs(uninstall=False):
    get_config('mapred-site', set_file=mapred_site_json)
    mapred_site = json.loads(read_json(mapred_site_json))

    try:
        check_mapr_site = all(get_prop_val(val) in mapred_site['properties'][key] for key, val in mapred_site_configs.iteritems())
    except Exception as e:
        print(e)
        check_mapr_site = False
    if check_mapr_site and not uninstall:
        print('\nUnravel mapred-site configs correct')
    else:
        for key, val in mapred_site_configs.iteritems():
            prop_regex = get_prop_regex(val, '.*?', '.*?', *['[0-9]{1,5}'] * 2)
            if uninstall:
                if mapred_site['properties'].get(key, None) and re.search(prop_regex, mapred_site['properties'][key]):
                    print('\n\nmapred-site config {0} found, removing'.format(key))
                    mapred_site['properties'][key] = remove_propery(prop_val=mapred_site['properties'][key],
                                                                    prop_regex='\s?' + prop_regex)
            elif not check_mapr_site:
                try:
                    print('Current: ' + key + ': ', mapred_site['properties'][key])
                    if get_prop_val(val) in mapred_site['properties'][key]:
                        pass
                    elif re.search(prop_regex, mapred_site['properties'][key]):
                        print('\n\nUnravel mapred-site config incorrect updating property {0}'.format(key))
                        mapred_site['properties'][key] = re.sub(prop_regex, get_prop_val(val), mapred_site['properties'][key])
                    elif get_prop_val(val) not in mapred_site['properties'][key]:
                        print('\n\nadding property in mapred-site {0}'.format(key))
                        mapred_site['properties'][key] += ' ' + get_prop_val(val)
                except:
                    print(key + ': ', 'None')
                    mapred_site['properties'][key] = get_prop_val(val)
        write_json(mapred_site_json, json.dumps(mapred_site))
        update_config('mapred-site', set_file=mapred_site_json)
    sleep(5)

def check_spark_default_configs(uninstall=False):
    try:
        spark_def_ver = get_spark_defaults()
        spark_def = read_json(spark_def_json)
        check_spark_config = all(get_prop_val(x) in spark_def for _, x in spark_defaults_configs.iteritems())
        if check_spark_config and not uninstall:
            print(spark_def_ver + '\n\nSpark Config is correct\n')
        else:
            new_spark_def = json.loads(spark_def)
            if uninstall:
                # remove Unravel spark driver/executor extraJavaOptions and spark.unravel.server.hostport
                for key, val in spark_defaults_configs.iteritems():
                    if new_spark_def['properties'].get(key, None) \
                            and key not in ['spark.eventLog.dir']:
                        print('\n\nUnravel Spark Config {0} found, removing\n'.format(key))
                        val_regex = get_prop_regex(val, *val[1:])
                        if re.match("spark.*?.extraJavaOptions", key):
                            val_regex = get_prop_regex(val, '.*?', *['[0-9]{1,3}'] * 3)
                        new_spark_def['properties'][key] = remove_propery(prop_val=new_spark_def['properties'][key],
                                                                          prop_regex='\s?' + val_regex)
            elif not check_spark_config:
                print('\n\nUnravel Spark Configs incorrect\n')
                for key, val in spark_defaults_configs.iteritems():
                    try:
                        print ('Current: {0}: {1}'.format(key, new_spark_def['properties'][key]))
                        if key == 'spark.eventLog.dir':
                            protocol = new_spark_def['properties'][key].split(':')[0]
                            # Added blob storage account in spark event dir for Blob Storage
                            # Add hdfs fs.default path to spark event dir for ADL
                            # Add hdfs fs.default path to spark event dir for abfs protocol
                            if protocol.startswith(('wasb', 'adl', 'abfs')) and hdfs_url not in new_spark_def['properties'][key]:
                                new_spark_def['properties'][key] = new_spark_def['properties'][key].replace(protocol + '://', hdfs_url)
                        elif (key == 'spark.driver.extraJavaOptions' or key == 'spark.executor.extraJavaOptions') and get_prop_val(val) not in new_spark_def['properties'][key]:
                            regex = get_prop_regex(val, '.*?', *['[0-9]{1,3}'] * 3)
                            if re.search(regex, new_spark_def['properties'][key]):
                                new_spark_def['properties'][key] = re.sub(regex,
                                                                          get_prop_val(val),
                                                                          new_spark_def['properties'][key])
                            else:
                                new_spark_def['properties'][key] += ' ' + get_prop_val(val)
                        elif key != 'spark.driver.extraJavaOptions' and key != 'spark.executor.extraJavaOptions':
                            new_spark_def['properties'][key] = get_prop_val(val)
                    except:
                        print(key + ': ', 'None')
                        new_spark_def['properties'][key] = get_prop_val(val)
            write_json(spark_def_json, json.dumps(new_spark_def))
            update_config(spark_def_ver, set_file=spark_def_json)
        sleep(5)
    except:
        pass

def check_tez_site_configs(uninstall=False):
    get_config('tez-site', set_file=tez_site_json)
    tez_site = json.loads(read_json(tez_site_json))
    make_change = False
    for key, val in tez_site_configs.iteritems():
        if uninstall:
            regex = get_prop_regex(val, '.*?', '.*?', *['[0-9]{1,5}'] * 2)
            if re.search(regex, tez_site['properties'][key]):
                print('Unravel TEZ config {0} found, removing'.format(key))
                tez_site['properties'][key] = remove_propery(prop_val=tez_site['properties'][key],
                               prop_regex='\s?' + regex)
                make_change = True
        else:
            prop_regex = get_prop_regex(val, '.*?', '.*?', *['[0-9]{1,5}'] * 2)
            if get_prop_val(val) in tez_site['properties'][key]:
                print(key + ' is correct')
            elif re.search(prop_regex, tez_site['properties'][key]):
                print(key + ' is not correct updating unravel tez properties')
                tez_site['properties'][key] = re.sub(prop_regex, get_prop_val(val), tez_site['properties'][key])
                make_change = True
            else:
                print(key + ' is missing add unravel tez properties')
                tez_site['properties'][key] += ' ' + get_prop_val(val)
                make_change = True
    if make_change:
        write_json(tez_site_json, json.dumps(tez_site))
        update_config('tez-site', set_file=tez_site_json)

def get_latest_req():
    cluster_requests = am_req(api_name='requests')
    latest_cluster_req = cluster_requests['items'][-1]['href']
    return am_req(full_api=latest_cluster_req)['Requests']

def get_config(config_name, set_file=None):
    if set_file:
        return check_output('python /tmp/unravel/configs.py -l {0} -u {1} -p \'{2}\' -n {3} -a get -c {4} -f {5} 2>/dev/null'.format(argv.am_host, argv.username, argv.password, argv.cluster_name, config_name, set_file), shell=True)
    else:
        return check_output('python /tmp/unravel/configs.py -l {0} -u {1} -p \'{2}\' -n {3} -a get -c {4} 2>/dev/null'.format(argv.am_host, argv.username, argv.password, argv.cluster_name, config_name), shell=True)

def get_spark_defaults():
    try:
        spark_defaults = check_output('python /tmp/unravel/configs.py -l {0} -u {1} -p \'{2}\' -n {3} -a get -c spark-defaults -f {4} 2>/dev/null'.format(argv.am_host, argv.username, argv.password, argv.cluster_name, spark_def_json), shell=True)
        return ('spark-defaults')
    except:
        spark_defaults = check_output('python /tmp/unravel/configs.py -l {0} -u {1} -p \'{2}\' -n {3} -a get -c spark2-defaults -f {4} 2>/dev/null'.format(argv.am_host, argv.username, argv.password, argv.cluster_name, spark_def_json), shell=True)
        return ('spark2-defaults')

def get_unravel_ver(protocol='http'):
    """
    Get Unravel Version from
    :return: string of unravel version e.g. 4.5.0.1
    """
    try:
        req = urllib2.Request('{1}://{0}/version.txt'.format(unravel_server, protocol))
        res = urllib2.urlopen(req)
        content = res.read()
        ver_regex = 'UNRAVEL_VERSION=([45].[0-9]+.[0-9]+.[0-9]+)'
        if re.search(ver_regex, content):
            return re.search(ver_regex, content).group(1)
    except Exception as e:
        print(e)
        print('Failed to get Unravel Version from {0}'.format(unravel_server))
        return('4.5.0.0')

def get_prop_val(config):
    if len(config) == 1:
        return config[0]
    else:
        return config[0].format(*config[1:])

def get_prop_regex(config, *args):
    if len(config) == 1:
        return config[0]
    else:
        return config[0].format(*args)


#####################################################################
#   Read the JSON file and return the plain text                    #
#####################################################################
def read_json(json_file_location):
    with open(json_file_location,'r') as f:
        result = f.read()
        f.close()
    return result

def restart_services():
    """ Restart Staled HDP Services"""
    print("Restarting services")
    restart_api = 'curl -u {0}:\'{1}\' -i -H \'X-Requested-By: ambari\' -X POST -d \'{{"RequestInfo": {{"command":"RESTART","context" :"Unravel request: Restart Services","operation_level":"host_component"}},"Requests/resource_filters":[{{"hosts_predicate":"HostRoles/{4}"}}]}}\' http://{2}:8080/api/v1/clusters/{3}/requests > /tmp/Restart.out 2> /tmp/Restart.err < /dev/null &'
    # Restart all services for HDI 4.X Cluster
    if re.search("Hadoop 3.[0-9]", check_output(['hadoop', 'version'])):
        call(restart_api.format(argv.username, argv.password, argv.am_host, argv.cluster_name, "cluster_name=" + argv.cluster_name),shell=True)
    else:
        call(restart_api.format(argv.username, argv.password, argv.am_host, argv.cluster_name, "stale_configs=true"),shell=True)

def remove_propery(prop_val, prop_regex):
    """
    :type prop_type: json or string
    :return: New Properties after removal
    """
    return re.sub(prop_regex, '', prop_val)

def update_config(config_name, config_key=None, config_value=None, set_file=None):
    """
    Update Service configuration in Ambari
    :param config_name: hadoop-env, hive-env, hive-site, mapred-site, spark-defaults, tez-site
    :param config_key: Optional argument to update specific configuration key directly without set_file
    :param config_value: Optional argument to update specific configuration value directly without set_file
    :param set_file: json file path contains all the new configurations
    """
    try:
        if set_file:
            return check_output('python /tmp/unravel/configs.py -l {0} -u {1} -p \'{2}\' -n {3} -a set -c {4} -f {5}'.format(argv.am_host, argv.username, argv.password, argv.cluster_name, config_name, set_file), shell=True)
        else:
            return check_output('python /tmp/unravel/configs.py -l {0} -u {1} -p \'{2}\' -n {3} -a set -c {4} -k {5} -v {6}'.format(argv.am_host, argv.username, argv.password, argv.cluster_name, config_name, config_key, config_value), shell=True)
    except:
        print('\Update %s configuration failed' % config_name)


def compare_versions(version1, version2):
    """
    :param version1: string of version number
    :type version1: str
    :param version2: string of version number
    :type version2: str
    :return: int 1: v1 > v2 0: v1 == v2 -1: v1 < v2
    """
    result = 0
    version1_list = version1.split('.')
    version2_list = version2.split('.')
    max_version = max(len(version1_list), len(version2_list))
    for index in range(max_version):
        v1_digit = int(version1_list[index]) if len(version1_list) > index else 0
        v2_digit = int(version2_list[index]) if len(version2_list) > index else 0
        if v1_digit > v2_digit:
            return 1
        elif v1_digit < v2_digit:
            return -1
        elif version1_list == version2_list:
            pass
    return result

def write_json(json_file_location, content_write):
    with open(json_file_location,'w') as f:
        f.write(content_write)
        f.close()

core_site = get_config('core-site')
hdfs_url = json.loads(core_site[core_site.find('{'):])['properties']['fs.defaultFS']

# Unravel Sensor Instrumentation
hive_env_content = ['export AUX_CLASSPATH=\${{AUX_CLASSPATH}}:/usr/local/unravel_client/unravel-hive-{0}.{1}.0-hook.jar', argv.hive_ver[0], argv.hive_ver[1]]
hadoop_env_content = ['export HADOOP_CLASSPATH=\${{HADOOP_CLASSPATH}}:/usr/local/unravel_client/unravel-hive-{0}.{1}.0-hook.jar', argv.hive_ver[0], argv.hive_ver[1]]
hive_site_configs = {'hive.exec.driver.run.hooks': ['com.unraveldata.dataflow.hive.hook.{0}', 'HiveDriverHook'],
                    'com.unraveldata.hive.hdfs.dir': ['/user/unravel/HOOK_RESULT_DIR'],
                    'com.unraveldata.hive.hook.tcp': ['true'],
                    'com.unraveldata.host': [argv.unravel],
                    'hive.exec.pre.hooks': ['com.unraveldata.dataflow.hive.hook.{0}', 'HivePreHook'],
                    'hive.exec.post.hooks': ['com.unraveldata.dataflow.hive.hook.{0}', 'HivePostHook'],
                    'hive.exec.failure.hooks': ['com.unraveldata.dataflow.hive.hook.{0}', 'HiveFailHook']
                    }
# New Hive Hook Class Name for 4.5.0.0
unravel_version = get_unravel_ver(argv.unravel_protocol)
print('Unravel Version: {0}'.format(unravel_version))
if compare_versions(unravel_version, "4.5.0.0") >= 0:
    hook_class = 'UnravelHiveHook'
    hive_site_configs['hive.exec.pre.hooks'][1] = hook_class
    hive_site_configs['hive.exec.driver.run.hooks'][1] = hook_class
    hive_site_configs['hive.exec.post.hooks'][1] = hook_class
    hive_site_configs['hive.exec.failure.hooks'][1] = hook_class

agent_path = "/usr/local/unravel-agent"
spark_defaults_configs={'spark.eventLog.dir': [hdfs_url],
                        'spark.unravel.server.hostport': ['{0}:{1}', argv.unravel, argv.lr_port],
                        'spark.driver.extraJavaOptions': ['-javaagent:{0}/jars/btrace-agent.jar=libs=spark-{1}.{2},config=driver -Dunravel.metrics.factor={3}',
                            agent_path, argv.spark_ver[0], argv.spark_ver[1], argv.metrics_factor],
                        'spark.executor.extraJavaOptions': ['-javaagent:{0}/jars/btrace-agent.jar=libs=spark-{1}.{2},config=executor -Dunravel.metrics.factor={3}', agent_path, argv.spark_ver[0],argv.spark_ver[1], argv.metrics_factor]}

# Add account name and root path for ADL Gen 1
if hdfs_url.startswith('adl'):
    core_site_json = json.loads(core_site[core_site.find('{'):])
    spark_defaults_configs['spark.unravel.azure.storage.account-name'] = [core_site_json['properties']['dfs.adls.home.hostname']]
    spark_defaults_configs['spark.unravel.azure.storage.client-root-path'] = [core_site_json['properties']['dfs.adls.home.mountpoint']]

mapred_site_configs = None
if argv.all:
    mapred_site_configs = {'yarn.app.mapreduce.am.command-opts': ['-javaagent:{0}/jars/btrace-agent.jar=libs=mr -Dunravel.server.hostport={1}:{2} -Dunravel.metrics.factor={3}', agent_path, argv.unravel, argv.lr_port, argv.metrics_factor],
                        'mapreduce.task.profile': ['true'],
                        'mapreduce.task.profile.maps': ['0-5'],
                        'mapreduce.task.profile.reduces': ['0-5'],
                        'mapreduce.task.profile.params': ['-javaagent:{0}/jars/btrace-agent.jar=libs=mr -Dunravel.server.hostport={1}:{2} -Dunravel.metrics.factor={3}', agent_path, argv.unravel, argv.lr_port, argv.metrics_factor]}
tez_site_configs = {
                    'tez.am.launch.cmd-opts': ['-javaagent:{0}/jars/btrace-agent.jar=libs=mr,config=tez -Dunravel.server.hostport={1}:{2} -Dunravel.metrics.factor={3}', agent_path, argv.unravel, argv.lr_port, argv.metrics_factor],
                    'tez.task.launch.cmd-opts': ['-javaagent:{0}/jars/btrace-agent.jar=libs=mr,config=tez -Dunravel.server.hostport={1}:{2} -Dunravel.metrics.factor={3}', agent_path, argv.unravel, argv.lr_port, argv.metrics_factor]
                    }

def main():
    sleep(35)
    print('Checking Ambari Operations')
    while(get_latest_req()['request_status'] not in ['COMPLETED','FAILED','ABORTED']
          and get_latest_req()['request_context'] != 'run_customscriptaction'):
        print('Operations Status:' + get_latest_req()['request_status'])
        sleep(60)
    print('All Operations completed, Comparing configs')

    check_configs(
                  hdfs_url,
                  hive_env_content,
                  hadoop_env_content,
                  hive_site_configs,
                  spark_defaults_configs,
                  mapred_site_configs,
                  tez_site_configs,
                  argv.uninstall
                 )

    restart_services()

if __name__ == '__main__':
    main()

EOF
   # Remove Unravel Properties from Ambari
   if [ "$UNINSTALL" == True ]; then
        sudo python /tmp/unravel/final_check.py --uninstall -host ${UNRAVEL_SERVER} -l ${AMBARI_HOST} -s ${SPARK_VER_XYZ} -hive ${HIVE_VER_XYZ}
        if [ -e /etc/init.d/unravel_es ]; then
            es_uninstall
        fi
   elif [ "$ENABLE_ALL_SENSOR" == True ]; then
        sudo python /tmp/unravel/final_check.py -host ${UNRAVEL_SERVER} -l ${AMBARI_HOST} -s ${SPARK_VER_XYZ} -hive ${HIVE_VER_XYZ} --metrics-factor ${METRICS_FACTOR} --all
   else
        sudo python /tmp/unravel/final_check.py -host ${UNRAVEL_SERVER} -l ${AMBARI_HOST} -s ${SPARK_VER_XYZ} -hive ${HIVE_VER_XYZ} --metrics-factor ${METRICS_FACTOR}
    fi
}

function upload_to_dfs(){
    local file_name=`basename $1`
    hdfs dfs -ls ${DFS_PATH%%/}/$file_name
    file_exists=$?
    hdfs dfs -ls ${DFS_PATH} 2>&1 >/dev/null
    folder_exists=$?
    if [[ $folder_exists -ne 0 ]]; then
        hdfs dfs -mkdir -p $DFS_PATH
    fi
    if [[ $file_exists -ne 0 ]]; then
        hdfs dfs -put -f $1 $DFS_PATH
    fi
}

function download_from_dfs(){
    hdfs dfs -get ${DFS_PATH%%/}/$1 $2
}

# dump the contents of env variables and shell settings
debug_dump

# do not make this script errors abort the whole bootstrap
allow_errors

install -y $*

# inject the python script
if [ ${HOST_ROLE} == "master" ]; then
    configs_py
    final_check
fi

if [ "$UNINSTALL" == True ]; then
    rm -rf /usr/local/unravel*
fi