# Download unravel rpm
ver_comp () {
    # $1 == $2 return 0
    # $1 < $2 return 2
    # $1 > $2 return 1
    if [[ $1 == $2 ]]
    then
        return 0
    fi
    local IFS=.
    local i ver1=($1) ver2=($2)
    # fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++))
    do
        ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++))
    do
        if [[ -z ${ver2[i]} ]]
        then
            # fill empty fields in ver2 with zeros
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]}))
        then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]}))
        then
            return 2
        fi
    done
    return 0
}

RPM_URL="https://preview.unraveldata.com/img/unravel-4.2.7-Azure-latest.rpm"

if [ $# -eq 9 ]; then
 RPM_URL=$9
fi
RPM_VER=$(echo ${RPM_URL} | grep -m 1 -o '[4-5].[0-9].[0-9]' | grep -m 1 '[4-5].[0-9].[0-9]')

/usr/bin/wget ${RPM_URL}

BLOBSTORACCT=${1}
BLOBPRIACKEY=${2}
BLOBSECACKEY=${3}

DLKSTOREACCT=${4}
DLKCLIENTAID=${5}
DLKCLIENTKEY=${6}
DLKCLITOKEPT=${7}
DLKCLIROPATH=${8}


# Prepare the VM for unravel rpm install
/usr/bin/yum install -y ntp
/usr/bin/yum install -y libaio
/usr/bin/yum install -y lzop
/usr/bin/systemctl enable ntpd
/usr/bin/systemctl start ntpd
/usr/bin/systemctl disable firewalld
/usr/bin/systemctl stop firewalld

/usr/sbin/iptables -F

/usr/sbin/setenforce 0
/usr/bin/sed -i 's/enforcing/disabled/g' /etc/selinux/config /etc/selinux/config

sleep 30


# Prepare disk for unravel
mkdir -p /srv

DATADISK=`/usr/bin/lsblk |grep 500G | awk '{print $1}'`
echo $DATADISK > /tmp/datadisk
echo "/dev/${DATADISK}1" > /tmp/dataprap

echo "Partitioning Disk ${DATADISK}"
echo -e "o\nn\np\n1\n\n\nw" | fdisk /dev/${DATADISK}

DATAPRAP=`cat /tmp/dataprap`
DDISK=`cat /tmp/datadisk`
/usr/sbin/mkfs -t ext4 ${DATAPRAP}

DISKUUID=`/usr/sbin/blkid |grep ext4 |grep $DDISK  | awk '{ print $2}' |sed -e 's/"//g'`
echo "${DISKUUID}    /srv   ext4 defaults  0 0" >> /etc/fstab

/usr/bin/mount -a

# install unravel rpm
/usr/bin/rpm  -U $(basename $RPM_URL)

/usr/bin/sleep 5


# Update Unravel Lic Key into the unravel.properties file
# Obtain a valid unravel Lic Key file ; the following is just non working one
UN_PROP_PATH='/usr/local/unravel/etc/unravel.properties'
echo "com.unraveldata.lic=1p6ed4s492012j5rb242rq3x3w702z1l455g501z2z4o2o4lo675555u3h" >> ${UN_PROP_PATH}

# Compare Unravel Version add CDH_CPATH if older than 4.5
ver_comp $RPM_VER 4.5.0
if [[ $? -eq 2 ]]; then
    echo "export CDH_CPATH='/usr/local/unravel/dlib/hdp2.6.x/*'" >> /usr/local/unravel/etc/unravel.ext.sh
fi

# run switch to user for version 4.3 and higher
ver_comp $RPM_VER 4.2.7
if [[ $? -eq 1 ]]; then
    sudo useradd  hdfs
    sudo groupadd hadoop
    sudo usermod -a -G hadoop hdfs
    sudo /usr/local/unravel/install_bin/switch_to_user.sh hdfs hadoop
fi


# Update Azure blob storage account credential in unravel.properties file
# Update and uncomment the following lines to reflect your Azure blob storage account name and keys

if [ $BLOBSTORACCT != "NONE" ] && [ $BLOBPRIACKEY != "NONE" ] && [ $BLOBSECACKEY != "NONE" ]; then

   echo "blob storage account name is ${BLOBSTORACCT}"
   echo "blob primary access key is ${BLOBPRIACKEY}"
   echo "blob secondary access key is ${BLOBSECACKEY}"
   echo "# Adding Blob Storage Account information, Update and uncomment following lines" >> ${UN_PROP_PATH}
   # Blob storage properties for Unravel 4.5.x and newer
   ver_comp $RPM_VER 4.4.3
   if [[ $? -eq 1 ]]; then
       echo "com.unraveldata.hdinsight.storage-account.1=fs.azure.account.key.${BLOBSTORACCT}.blob.core.windows.net" >> ${UN_PROP_PATH}
       echo "com.unraveldata.hdinsight.access-key.1=${BLOBPRIACKEY}" >> ${UN_PROP_PATH}
   else
       echo "com.unraveldata.hdinsight.storage-account-name-1=fs.azure.account.key.${BLOBSTORACCT}.blob.core.windows.net" >> ${UN_PROP_PATH}
       echo "com.unraveldata.hdinsight.primary-access-key=${BLOBPRIACKEY}" >> ${UN_PROP_PATH}
       echo "com.unraveldata.hdinsight.storage-account-name-2=fs.azure.account.key.${BLOBSTORACCT}.blob.core.windows.net" >> ${UN_PROP_PATH}
       echo "com.unraveldata.hdinsight.secondary-access-key=${BLOBSECACKEY}" >> ${UN_PROP_PATH}
   fi

else
   echo "One or more of your blob storage account parameter is invalid, please check your parameter file"
fi

sleep 3

if [ $DLKSTOREACCT != "NONE" ] && [ $DLKCLIENTAID != "NONE" ] && [ $DLKCLIENTKEY != "NONE" ] && [ $DLKCLITOKEPT != "NONE" ] && [ $DLKCLIROPATH != "NONE" ]; then

   echo "Data Lake store name is ${DLKSTOREACCT}"
   echo "Data Lake Client ID is ${DLKCLIENTAID}"
   echo "Data Lake Client Key is ${DLKCLIENTKEY}"
   echo "Data Lake Access Token is ${DLKCLITOKEPT}"
   echo "Data Lake Client Root Path is ${DLKCLIROPATH}"
   echo "# Adding Data Lake Account information, Update and uncomment following lines" >> ${UN_PROP_PATH}
   echo "com.unraveldata.adl.accountFQDN=${DLKSTOREACCT}.azuredatalakestore.net" >> ${UN_PROP_PATH}
   echo "com.unraveldata.adl.clientId=${DLKCLIENTAID}" >> ${UN_PROP_PATH}
   echo "com.unraveldata.adl.clientKey=${DLKCLIENTKEY}" >> ${UN_PROP_PATH}
   echo "com.unraveldata.adl.accessTokenEndpoint=${DLKCLITOKEPT}" >> ${UN_PROP_PATH}
   echo "com.unraveldata.adl.clientRootPath=${DLKCLIROPATH}" >> ${UN_PROP_PATH}

else
  echo "One or more of your data lake storge parameter is invalid, please check your parameter file"
fi

# Adding unravel properties for Azure Cloud

echo "com.unraveldata.onprem=false" >> ${UN_PROP_PATH}
echo "com.unraveldata.spark.live.pipeline.enabled=true" >> ${UN_PROP_PATH}
echo "com.unraveldata.spark.appLoading.maxAttempts=10" >> ${UN_PROP_PATH}
echo "com.unraveldata.spark.appLoading.delayForRetry=4000" >> ${UN_PROP_PATH}

# Starting Unravel daemons
# uncomment below will start unravel daemon automatically but within unravel_all.sh start  will have exit status=1.
# Thus we recommend login to unravel VM and run unravel_all.sh manually
# /etc/init.d/unravel_all.sh start
