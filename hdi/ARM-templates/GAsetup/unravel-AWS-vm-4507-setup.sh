# Download unravel 4.5.0.5 latest rpm
RPMFILE=`curl -sS -u unravel:WillowRoad68 https://preview.unraveldata.com/unravel/RPM/4.5.0/  |grep EMR |awk '{ print $6}' |cut -d\" -f2  |grep 4.5.0.7 |tail -1`
echo $RPMFILE > /tmp/rpmfilename
curl -v -u  unravel:WillowRoad68 https://preview.unraveldata.com/unravel/RPM/4.5.0/${RPMFILE} -o ${RPMFILE}

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
rpmfile_name=`cat /tmp/rpmfilename`
/usr/bin/rpm  -U $rpmfile_name

/usr/bin/sleep 5


# Update Unravel Lic Key into the unravel.properties file
# Obtain a valid unravel Lic Key file ; the following is just non working one
echo "com.unraveldata.lic=1p6ed4s492012j5rb242rq3x3w702z1l455g501z2z4o2o4lo675555u3h" >> /usr/local/unravel/etc/unravel.properties
echo "export CDH_CPATH="/usr/local/unravel/dlib/hdp2.6.x/*"" >> /usr/local/unravel/etc/unravel.ext.sh

# Update Azure blob storage account credential in unravel.properties file
# Update and uncomment the following lines to reflect your Azure blob storage account name and keys

if [ $BLOBSTORACCT != "NONE" ] && [ $BLOBPRIACKEY != "NONE" ] && [ $BLOBSECACKEY != "NONE" ]; then

   echo "blob storage account name is ${BLOBSTORACCT}"
   echo "blob primary access key is ${BLOBPRIACKEY}"
   echo "blob secondary access key is ${BLOBSECACKEY}"
   echo "# Adding Blob Storage Account information, Update and uncomment following lines" >> /usr/local/unravel/etc/unravel.properties
   echo "com.unraveldata.hdinsight.storage-account-name-1=fs.azure.account.key.${BLOBSTORACCT}.blob.core.windows.net" >> /usr/local/unravel/etc/unravel.properties
   echo "com.unraveldata.hdinsight.primary-access-key=${BLOBPRIACKEY}" >> /usr/local/unravel/etc/unravel.properties
   echo "com.unraveldata.hdinsight.storage-account-name-2=fs.azure.account.key.${BLOBSTORACCT}.blob.core.windows.net" >> /usr/local/unravel/etc/unravel.properties
   echo "com.unraveldata.hdinsight.secondary-access-key=${BLOBSECACKEY}" >> /usr/local/unravel/etc/unravel.properties

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
   echo "# Adding Data Lake Account information, Update and uncomment following lines" >> /usr/local/unravel/etc/unravel.properties
   echo "com.unraveldata.adl.accountFQDN=${DLKSTOREACCT}.azuredatalakestore.net" >> /usr/local/unravel/etc/unravel.properties
   echo "com.unraveldata.adl.clientId=${DLKCLIENTAID}" >> /usr/local/unravel/etc/unravel.properties
   echo "com.unraveldata.adl.clientKey=${DLKCLIENTKEY}" >> /usr/local/unravel/etc/unravel.properties
   echo "com.unraveldata.adl.accessTokenEndpoint=${DLKCLITOKEPT}" >> /usr/local/unravel/etc/unravel.properties
   echo "com.unraveldata.adl.clientRootPath=${DLKCLIROPATH}" >> /usr/local/unravel/etc/unravel.properties

else
  echo "One or more of your data lake storge parameter is invalid, please check your parameter file"
fi

# Adding unravel properties for Azure Cloud

echo "com.unraveldata.onprem=false" >> /usr/local/unravel/etc/unravel.properties
echo "com.unraveldata.spark.live.pipeline.enabled=true" >> /usr/local/unravel/etc/unravel.properties
echo "com.unraveldata.spark.appLoading.maxAttempts=10" >> /usr/local/unravel/etc/unravel.properties
echo "com.unraveldata.spark.appLoading.delayForRetry=4000" >> /usr/local/unravel/etc/unravel.properties
echo "com.unraveldata.onprem=false" >> /usr/local/unravel/etc/unravel.properties

# Switch user 
useradd hdfs
groupadd hadoop
usermod -a -G hadoop hdfs

/usr/local/unravel/install_bin/switch_to_user.sh hdfs hadoop


# Starting Unravel daemons
# uncomment below will start unravel daemon automatically but within unravel_all.sh start  will have exit status=1.
# Thus we recommend login to unravel VM and run unravel_all.sh manually
# /etc/init.d/unravel_all.sh start
