# Download unravel rpm
/usr/bin/wget http://preview.unraveldata.com/img/unravel-4.2-1075.x86_64.EMR.rpm

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

#echo "/dev/${DATADISK}1  /srv  ext4 defaults 0 0" >> /etc/fstab
echo "/dev/${DATADISK}1" > /tmp/dataprap

echo "Partitioning Disk ${DATADISK}"
echo -e "o\nn\np\n1\n\n\nw" | fdisk /dev/${DATADISK}



DATAPRAP=`cat /tmp/dataprap`
/usr/sbin/mkfs -t ext4 ${DATAPRAP}

DISKUUID=`/usr/sbin/blkid |grep ext4 | awk '{ print $2}' |sed -e 's/"//g'`
echo "${DISKUUID}    /srv   ext4 defaults  0 0" >> /etc/fstab

/usr/bin/mount -a

# install unravel rpm
/usr/bin/rpm  -U unravel-4.2-1075.x86_64.EMR.rpm

/usr/bin/sleep 5


# Update Unravel Lic Key into the unravel.properties file
# Obtain a valid unravel Lic Key file ; the following is just non working one
echo "com.unraveldata.lic=1p6ed4s492012j5rb242rq3x3w702z1l455g501z2z4o2o4lo675555u3h" >> /usr/local/unravel/etc/unravel.properties

echo "export CDH_CPATH="/usr/local/unravel/dlib/hdp2.6.x/*"" >> /usr/local/unravel/etc/unravel.ext.sh

# Update Azure blob storage account credential in unravel.properties file
# Update and uncomment the following lines to reflect your Azure blob storage account name and keys
echo "# Adding Blob Storage Account information, Update and uncomment following lines" >> /usr/local/unravel/etc/unravel.properties
echo "# com.unraveldata.hdinsight.storage-account-name-1=fs.azure.account.key.STORAGEACCOUNTNAME.blob.core.windows.net" >> /usr/local/unravel/etc/unravel.properties
echo "# com.unraveldata.hdinsight.primary-access-key=" >> /usr/local/unravel/etc/unravel.properties
echo "# com.unraveldata.hdinsight.storage-account-name-2=fs.azure.account.key.STORAGEACCOUNTNAME.blob.core.windows.net" >> /usr/local/unravel/etc/unravel.properties
echo "# com.unraveldata.hdinsight.secondary-access-key=" >> /usr/local/unravel/etc/unravel.properties

echo "# Adding Data Lake Account information, Update and uncomment following lines" >> /usr/local/unravel/etc/unravel.properties
echo "# com.unraveldata.adl.accountFQDN=DATALAKESTORE.azuredatalakestore.net" >> /usr/local/unravel/etc/unravel.properties
echo "# com.unraveldata.adl.clientId=" >> /usr/local/unravel/etc/unravel.properties
echo "# com.unraveldata.adl.clientKey=" >> /usr/local/unravel/etc/unravel.properties
echo "# com.unraveldata.adl.accessTokenEndpoint=" >> /usr/local/unravel/etc/unravel.properties
echo "# com.unraveldata.adl.clientRootPath=" >> /usr/local/unravel/etc/unravel.properties

# Starting Unravel daemons
# uncomment below will start unravel daemon automatically but within unravel_all.sh start  will have exit status=1.
# Thus we recommend login to unravel VM and run unravel_all.sh manually
# /etc/init.d/unravel_all.sh start
