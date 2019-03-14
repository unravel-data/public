#!/bin/bash
DATE=$(date +"%Y%m%d%H%M")
UVERSION="4.4.3.0"
UFOLDER=$(echo $UVERSION |cut -d"." -f1-3)
DOWNLOADUSER="Unravel-4430"
DOWNLOADPASSWD="YzWY2mxzur"
MD5STRING="4b2b777224c0a2b746bad1ff73063fcb"
UNRAVEL_IP=$(hostname -i |awk '{print $2}')

# Backup previous unravel.properties
sudo cp /usr/local/unravel/etc/unravel.properties /tmp/unravel.properties_$DATE

# Uninstall previous version of Unravel
sudo rpm -e unravel
sudo /bin/rm -rf /usr/local/unravel /srv/unravel /etc/unravel_ctl

# Clean up unravel 4.2 files
sudo rm -rf /tmp/mysql.unravel
sudo rm -rf /tmp/unravel.db.include
sudo rm -rf /root/unravel.upgrade
sudo rm -rf /tmp/hsperfdata_unravel

# Install unravel Cloud version
# Please download the unravel Cloud version rpm into the /tmp folder

# Checking unravel rpm md5sum
if [ -f /tmp/unravel-${UVERSION}-EMR-latest.rpm ]; then
    echo "unravel ${UVERSION} rpm exists"
	CHKSUM=`md5sum /tmp/unravel-${UVERSION}-EMR-latest.rpm | awk '{ print $1}'` 
	if [ "$CHKSUM" = "$MD5STRING" ]; then 
	    echo "md5sum match, downloaded unravel rpm file is OK to use"
	else
	    echo "md5sum mismatch, downloaded unravel rpm file is bad"
		echo "please re-download the unravel ${UVERSION} file into /tmp folder and re-run the script"
		echo "To download unravel ${UVERSION} rpm file, use the following command"
		echo "curl -v https://preview.unraveldata.com/unravel/RPM/$UFOLDER/unravel-${UVERSION}-EMR-latest.rpm -o /tmp/unravel-${UVERSION}-EMR-latest.rpm -u ${DOWNLOADUSER}:${DOWNLOADPASSWD}"
		exit 1
	fi
else
    echo "unravel 4.4.3.0 rpm doesn't exists in /tmp folder"
    echo "please download the unravel 4.4.3.0 file into /tmp folder and re-run the script"
	echo "To download unravel ${UVERSION} rpm file, use the following command"
	echo "curl -v https://preview.unraveldata.com/unravel/RPM/$UFOLDER/unravel-${UVERSION}-EMR-latest.rpm -o /tmp/unravel-${UVERSION}-EMR-latest.rpm -u ${DOWNLOADUSER}:${DOWNLOADPASSWD}"	
	exit 1
fi

# Install unravel 4.4.3.0
# The rpm install output will shown in console and log file in /tmp/unravel_${UVERSION}_install_${DATE}.log

sudo rpm -Uvh /tmp/unravel-4.4.3.0-EMR-latest.rpm 2>&1 | tee  /tmp/unravel_${UVERSION}_install_${DATE}.log
sleep 10
/usr/local/unravel/install_bin/await_fixups.sh

# Update unravel environment template file
# Append this classpath based on the version you found
echo "export CDH_CPATH=/usr/local/unravel/dlib/hdp2.6.x/*" | sudo tee --append /usr/local/unravel/etc/unravel.ext.sh

# Update /usr/local/unravel/etc/unravel.properties
# Follow the following example and add additional unravel.property entries if needed
echo "com.unraveldata.onprem=false" |sudo tee --append /usr/local/unravel/etc/unravel.properties


# Checking if hdfs user and hadoop group exist or not
getent passwd hdfs  > /dev/null 2&>1
if [ $? -eq 0 ]; then
    echo "hdfs user exists"
else
    echo "hdfs user doesn't exist and creating"
	sudo useradd hdfs
fi

getent group  hadoop > /dev/null 2&>1
if [ $? -eq 0 ]; then
    echo "group hadoop exists"
else
    echo "group hadoop doesn't exist and creating"
	sudo groupadd hadoop
fi

# ensure hdfs user also belong to group hadoop
sudo usermod -a -G hadoop hdfs

# switching unravel daemons running user to hdfs

sudo /usr/local/unravel/install_bin/switch_to_user.sh hdfs hadoop


# Start unravel
sudo /etc/init.d/unravel_all.sh start
sleep 60
echo "Unravel UI portal is below"
echo "http://${UNRAVEL_IP}:3000/"

