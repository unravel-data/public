#! /bin/bash

################################################################################################
# Unravel for HDInsight Bootstrap Script                                                       #
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

function fetch_sensor_zip() {
    local zip_name="unravel-agent-pack-bin.zip"

    if [ -f $AGENT_DST/$zip_name ]; then
        # do not refetch the agent zip
        return
    fi

    echo "Fetching sensor zip file" | tee -a ${OUT_FILE}
    URL="http://${UNRAVEL_SERVER}/hh/$zip_name"
    echo "GET $URL" | tee -a ${OUT_FILE}
    wget -4 -q -T 10 -t 5 -O - $URL > ${TMP_DIR}/$zip_name
    #wget $URL -O ${TMP_DIR}/$SPK_ZIP_NAME
    RC=$?
    echo "RC: " $RC | tee -a ${OUT_FILE}

    if [ $RC -eq 0 ]; then
        sudo mkdir -p $AGENT_JARS
        sudo chmod -R 655 ${AGENT_DST}
        sudo chown -R ${AGENT_DST_OWNER} ${AGENT_DST}
        sudo /bin/cp ${TMP_DIR}/$zip_name  $AGENT_DST/
        (cd $AGENT_JARS ; sudo unzip ../$zip_name)
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
  echo "GET $HHURL" |tee -a $OUT_FILE
  wget -4 -q -T 10 -t 5 -O - $HHURL > ${TMP_DIR}/$HH_JAR_NAME
  RC=$?
  if [ $RC -eq 0 ]; then
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
            install_hive_site
            isFunction after_hh_install && after_hh_install
            echo "Hivehook install is completed." | tee -a ${OUT_FILE}

            hivehook_postinstall_check
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
    su - ${UNRAVEL_ES_USER} -c bash -c "cd /usr/local/\${DAEMON_NAME}; ./unravel_emr_sensor.sh" >\$OUT_LOG 2>&1 &
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
    PIDS=\$(ps -U ${UNRAVEL_ES_USER} -f | egrep "unravel_emr_sensor.sh|unravel_es/unravel-emr-sensor.jar" | grep -v grep | awk '{ print \$2 }' )
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
  cat <<EOF > /usr/local/unravel_es/unravel_es.properties
#######################################################
# unravel_es settings                                 #
# - modify the settings and restart the service       #
#######################################################

# debug=false
# done-dir=/path/to/done/dir
# sleep-sec=30
# unravel-server=127.0.0.1
# cluster-id=j-default
# cluster-type=emr
# chunk-size=20
EOF
}

function gen_sensor_script() {
    sudo /bin/mkdir -p /usr/local/unravel_es
    sudo /bin/rm ${TMP_DIR}/u_es 2>/dev/null

    isFunction resolve_cluster_id && resolve_cluster_id

    [ ! -z "$CLUSTER_ID" ] && CLUSTER_ID_ARG="--cluster-id $CLUSTER_ID"
    [ ! -z "$UNRAVEL_ES_CHUNK" ] && CHUNK_ARG="--chunk-size $UNRAVEL_ES_CHUNK"

    cat <<EOF >"${TMP_DIR}/u_es"
#!/bin/bash

UNRAVEL_HOST=$UNRAVEL_HOST
IDENT=unravel_es
cd /usr/local/unravel_es
# this script (process) will stick around as a nanny
FLAP_COUNT=0
MINIMUM_RUN_SEC=5
while true ; do
  # nanny loop
  START_AT=\$(date +%s)
  java -server -Xmx2g -Xms2g -cp /usr/local/\${IDENT}/lib/* -jar /usr/local/\${IDENT}/unravel-emr-sensor.jar $ES_CLUSTER_TYPE_SWITCH $CLUSTER_ID_ARG $CHUNK_ARG --unravel-server \$UNRAVEL_HOST $* > \${IDENT}.out  2>&1

  CHILD_PID=\$!
  # if this script gets INT or TERM, then clean up child process and exit
  trap 'kill $CHILD_PID; exit 5' SIGINT SIGTERM
  # wait for child
  wait \$CHILD_PID
  CHILD_RC=\$?
  FINISH_AT=\$(date +%s)
  RUN_SECS=\$((\$FINISH_AT-\$START_AT))
  echo "\$(date '+%Y%m%dT%H%M%S') \${IDENT} died after \${RUN_SECS} seconds" >> \${IDENT}.out
  if [ \$CHILD_RC -eq 71 ]; then
      echo "\$(date '+%Y%m%dT%H%M%S') \${IDENT} retcode is 71, indicating no restart required" >>\$UNRAVEL_LOG_DIR/\${IDENT}.out
      exit 71
    fi
    if [ \$RUN_SECS -lt \$MINIMUM_RUN_SEC ]; then
      FLAP_COUNT=\$((\$FLAP_COUNT+1))
      if [ \$FLAP_COUNT -gt 10 ]; then
        echo "\$(date '+%Y%m%dT%H%M%S') \${IDENT} died too fast, NOT restarting to avoid flapping" >>\${IDENT}.out
        exit 6
      fi
  else
      FLAP_COUNT=0
  fi
  sleep 10
done
EOF
    sudo /bin/mv ${TMP_DIR}/u_es /usr/local/unravel_es/unravel_emr_sensor.sh
    sudo chmod +x /usr/local/unravel_es/*.sh
    sudo chown -R ${UNRAVEL_ES_USER}:${UNRAVEL_ES_GROUP} /usr/local/unravel_es
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
  if isFunction can_install_es; then
    if ! can_install_es; then
      echo "Unravel MR Sensor (unravel_es) is not eligible" | tee -a ${OUT_FILE}
      return 0
    fi
  fi

  if es_already_installed; then
    echo "Unravel MR Sensor (unravel_es) already installed" | tee -a ${OUT_FILE}
    return 0
  fi

  sudo yum install -y wget

  sudo /bin/mkdir -p /usr/local/unravel_es/lib
  if [ "$ENABLE_GPL_LZO" == "yes" ] || [ "$ENABLE_GPL_LZO" == "true" ]; then
    sudo wget -4 -q -T 10 -t 5 -O - http://central.maven.org/maven2/org/anarres/lzo/lzo-core/1.0.5/lzo-core-1.0.5.jar > /usr/local/unravel_es/lib/lzo-core.jar
  fi

  # generate /etc/init.d/unravel_es
  get_sensor_initd
  # generate /usr/local/unravel_emr_sensor.sh
  gen_sensor_script
  # generate /usr/local/unravel_es/unravel_es.properties
  gen_sensor_properties

  UES_JAR_NAME="unravel-emr-sensor.jar"
  UESURL="http://${UNRAVEL_SERVER}/hh/$UES_JAR_NAME"
  echo "GET $UESURL" |tee -a  $OUT_FILE
  wget -4 -q -T 10 -t 5 -O - $UESURL > ${TMP_DIR}/$UES_JAR_NAME
  RC=$?
  if [ $RC -eq 0 ]; then
      sudo /bin/cp ${TMP_DIR}/$UES_JAR_NAME  /usr/local/unravel_es
      sudo chmod 755 /usr/local/unravel_es/$UES_JAR_NAME
      sudo chown -R ${UNRAVEL_ES_USER}:${UNRAVEL_ES_GROUP} /usr/local/unravel_es
  else
      echo "ERROR: Fetch of $UESURL failed, RC=$RC" |tee -a $OUT_FILE
      return 1
  fi

  # start
  if isFunction install_service_impl; then
    install_service_impl
  else
    install_service_dflt
  fi
  RC=$?

  if [ $RC -eq 0 ]; then
    sudo service unravel_es start
  fi
  RC=$?

  if [ $RC -eq 0 ]; then
      echo "Unravel MR Sensor (unravel_es) is installed and running" | tee -a  $OUT_FILE
      return $(es_postinstall_check)
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
    echo "Unravel MR Sensor (unravel_es) is uninstalled" | tee -a ${OUT_FILE}
  else
    echo "Unravel MR Sensor (unravel_es) has not been installed. Aborting." | tee -a ${OUT_FILE}
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
#                                                                                             #
# Accepts:                                                                                    #
#  - es_postinstall_check_arguments()                                                         #
#  - can_install_es()                                                                         #
###############################################################################################
function es_postinstall_check() {
  if isFunction can_install_es; then
    can_install_es && return 0
  fi

  # make sure that 'unravel_es' is running and using correct arguments
  local es_cmd=$(ps aexo "command" | grep unravel-emr-sensor | grep -v grep)

  if [ -z "$es_cmd" ]; then
    echo "ERROR: 'unravel_es' service is not running!" | tee -a ${OUT_FILE}
    return 1
  fi

  if isFunction es_postinstall_check_arguments; then
    es_postinstall_check_arguments $es_cmd && return 0
    return 1
  fi
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

        local retval="$($spark_submit --version 2>&1 | grep -oP '.*?version\s+\K([0-9.]+)')"
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
      install_spark_conf_impl
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
        local base_agent="-javaagent:${AGENT_JARS}/btrace-agent.jar=libs=spark-${SPARK_VER_X}.${SPARK_VER_Y}"
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

        install_spark_conf

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
    echo "  -y                 unattended install" | tee -a ${OUT_FILE}
    echo "  -v                 verbose mode" | tee -a ${OUT_FILE}
    echo "  -h                 usage" | tee -a ${OUT_FILE}
    echo "  --unravel-server   unravel_host:port (required)" | tee -a ${OUT_FILE}
    echo "  --unravel-receiver unravel_restserver:port" | tee -a ${OUT_FILE}
    echo "  --hive-version     installed hive version" | tee -a ${OUT_FILE}
    echo "  --spark-version    installed spark version" | tee -a ${OUT_FILE}
    echo "  --spark-load-mode  sensor mode [DEV | OPS | BATCH]" | tee -a ${OUT_FILE}
    echo "  --env              comma separated <key=value> env variables" | tee -a ${OUT_FILE}
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
            echo "Node is not eligible for unravel_es installation. Skipping" | tee -a ${OUT_FILE}
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
            --unravel-server )
                UNRAVEL_SERVER=$1
                [[ $UNRAVEL_SERVER != *":"* ]] && UNRAVEL_SERVER=${UNRAVEL_SERVER}:3000
                export UNRAVEL_SERVER
                shift
                ;;
            --unravel-receiver )
                LRHOST=$1
                [[ $LRHOST != *":"* ]] && LRHOST=${LRHOST}:4043
                export LRHOST
                shift
                ;;
            --hive-version )
                export HIVE_VER_XYZ=$1
                shift
                ;;
            --spark-version )
                export SPARK_VER_XYZ=$1
                shift
                ;;
            --spark-load-mode )
                export SPARK_APP_LOAD_MODE=$1
                shift
                ;;
            --env)
                for ENV in "$(echo $1 | tr ',' ' ')"; do
                  eval "export $ENV"
                done
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

    install_hivehook
    install_es
    install_spark
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

  export CLUSTER_ID=$(echo -e "import hdinsight_common.ClusterManifestParser as ClusterManifestParser\nprint ClusterManifestParser.parse_local_manifest().deployment.cluster_name" | python)

  local primary_head_node=$(get_primary_headnode)
  local full_host_name=$(hostname -f)

  echo "AMBARI_USR=$AMBARI_USR" | tee -a ${OUT_FILE}
  echo "AMBARI_PWD=$AMBARI_PWD" | tee -a ${OUT_FILE}

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

  exportAuxJars="\nexport HIVE_AUX_JARS_PATH=\$HIVE_AUX_JARS_PATH:$jars_colon"
  newHiveEnvContent="$currentHiveEnvContent$exportAuxJars"

  echo "Modifying hive-env" | tee -a ${OUT_FILE}

  updateResult=$(bash $AMBARICONFIGS_SH -u $AMBARI_USR -p $AMBARI_PWD set $AMBARI_HOST $CLUSTER_ID hive-env "content" "$newHiveEnvContent" 2>/dev/null)

  if [[ $updateResult != *"Tag:version"* ]] && [[ $updateResult == *"[ERROR]"* ]]; then
    echo "[ERROR] Failed to update hive-env" | tee -a ${OUT_FILE}
    echo $updateResult | tee -a ${OUT_FILE}
    [ $ALLOW_ERRORS ] && exit 1
  fi

  currentWebHCatEnvContent=$(bash $AMBARICONFIGS_SH -u $AMBARI_USR -p $AMBARI_PWD get $AMBARI_HOST $CLUSTER_ID webhcat-env  2>/dev/null | grep '"content"' | perl -lne 'print $1 if /"content" : "(.*)"/')
  newWebHCatEnvContent="$currentWebHCatEnvContent$exportAuxJars"

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

function es_postinstall_check_arguments() {
    # make sure cluster-id is provided
    local ret=0
    echo $1 | grep -e '--cluster-id'
    if [ 0 -ne $? ]; then
        echo "ERROR: 'unravel_es' for Qubole does not use cluster-id" | tee -a ${OUT_FILE}
        ret=1
    fi
    return $ret
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

# dump the contents of env variables and shell settings
debug_dump

# do not make this script errors abort the whole bootstrap
allow_errors

install -y $*

