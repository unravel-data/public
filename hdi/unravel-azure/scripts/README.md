## Unravel HDInsight Application Startup Scripts

### hdi_premises_sensor_deploy.sh
Requirement: All head, worker, edge node need to run this script either via HDInsight Script Action or manually

Usage: `sudo ./hdi_premises_sensor_deploy_.sh`
1. Download Sensor tar.gz file from https://unravelstorage01.blob.core.windows.net/unravel-app-blob-2018-04-13/unravel-sensor.tar.gz
2. Extract Sensor tar.gz file to /usr/local/


### unravel-instrumentation.sh
Requirement: The script need to be ran as sudo

Usage: `sudo ./hdi_onpremises_bootstrap.sh` or `sudo ./hdi_onpremises_bootstrap.sh uninstall`
1. `hdi_onpremises_setup.py` in /usr/local/unravel/
2. Run `hdi_onpremises_setup.py` in the background (either install or uninstall)


### hdi_onpremises_setup.py
Requirement: The script need to be ran as sudo

Usage: `sudo python hdi_onpremises_setup.py` or `sudo python hdi_onpremises_setup.py -uninstall`
1. Get Hive and Spark version from `/usr/bin/hive --version` and `spark-submit --version` based on what spark service is installed in Ambari
2. Get Edge node IP from `hostname -i`
3. Fill in all the configurations and compare with Ambari Configuration, update configuration if not exist/correct
4. For uninstall, Unravel Configuration will be removed from Ambari Configuration

### configs.py
Put/Get Ambari Configuration
For usage check:  https://cwiki.apache.org/confluence/display/AMBARI/Modify+configurations#Modifyconfigurations-Editconfigurationusingconfigs.py
