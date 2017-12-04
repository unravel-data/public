# Download unravel rpm
/usr/bin/wget http://preview.unraveldata.com/img/unravel-4.2-1064.x86_64.EMR.rpm

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
echo "/dev/${DATADISK}1  /srv  ext4 defaults 0 0" >> /etc/fstab
echo "/dev/${DATADISK}1" > /tmp/dataprap

echo "Partitioning Disk ${DATADISK}"
echo -e "o\nn\np\n1\n\n\nw" | fdisk /dev/${DATADISK}

DATAPRAP=`cat /tmp/dataprap`

/usr/sbin/mkfs -t ext4 ${DATAPRAP}
/usr/bin/mount -a

# install unravel rpm
/usr/bin/rpm  -U unravel-4.2-1064.x86_64.EMR.rpm

/usr/bin/sleep 5


# Update Unravel Lic Key into the unravel.properties file
# Obtain a valid unravel Lic Key file ; the following is just non working one
echo "com.unraveldata.lic=1p6ed4s492012j5rb242rq3x3w702z1l455g501z2z4o2o4lo675555u3h" >> /usr/local/unravel/etc/unravel.properties


# Update Azure blob storage account credential in unravel.properties file
# Update and uncomment the following lines to reflect your Azure blob storage account name and keys
# echo "com.unraveldata.hdinsight.storage-account-name-1=fs.azure.account.key.STORAGEACCOUNTNAME.blob.core.windows.net" >> /usr/local/unravel/etc/unravel.properties
# echo "com.unraveldata.hdinsight.primary-access-key=Ondaq2aYMpJf8pCdvtFJ/zARJvMP1DsoFzBKp//4DVQi+hcL5+XsW2XFNI7ppLottPdAi6KwFQ==" >> /usr/local/unravel/etc/unravel.properties
# echo "com.unraveldata.hdinsight.storage-account-name-2=fs.azure.account.key.STORAGEACCOUNTNAME.blob.core.windows.net" >> /usr/local/unravel/etc/unravel.properties
# echo "com.unraveldata.hdinsight.secondary-access-key=aL3MFZ/5hP4k1AZkFZzCmWjgEMqe0o6F33gJZxwfQABLaynxpatWY71YnH35LuTeVm6CP1w==#" >> /usr/local/unravel/etc/unravel.properties

# Starting Unravel daemons
# uncomment below will start unravel daemon automatically but within unravel_all.sh start  will have exit status=1.
# Thus we recommend login to unravel VM and run unravel_all.sh manually
# /etc/init.d/unravel_all.sh start
