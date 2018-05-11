#!/usr/bin/python
'''
Simple Sanity test for new rpm
1. Check Unravel on CDH instrumentation
    - hive-site.xml
    - hive-env.sh
    - hadoop-env.sh
    - spark-defaults.conf
    - mapred-site.xml
2. Check Unravel Sensor Parcel State
3. Run Sample Job
    - Sample Mapreduce Pi job
    - Sample Spark Pi job
    - Sample Hive empty table select count query
4. Check Unravel UI for Sample jobs metrics
    - Mapreduce:
        - Attempts tab
        - Timeline tab
        - Resouce Usage tab
    - Spark:
        - Configuration tab
        - Execution tab
    - Hive:
        - Navigation tab
'''
import os
import re
import pwd
import json
import argparse
from glob import glob
from time import sleep
from xml.etree import ElementTree as ET
from subprocess import call, Popen, PIPE
try:
    from cm_api.api_client import ApiResource
    from cm_api.endpoints.types import ApiClusterTemplate
    from cm_api.endpoints.cms import ClouderaManager
    from termcolor import colored
    import requests
except:
    call(['sudo', 'yum' , '-y', '--enablerepo=extras', 'install', 'epel-release'])
    call(['sudo', 'yum' , '-y', 'install', 'python-pip'])
    call(['sudo', 'pip', 'install', 'cm-api'])
    call(['sudo', 'pip', 'install', 'termcolor'])
    call(['sudo', 'pip', 'install', 'requests'])
    from cm_api.api_client import ApiResource
    from cm_api.endpoints.types import ApiClusterTemplate
    from cm_api.endpoints.cms import ClouderaManager
    from termcolor import colored
    import requests

parser = argparse.ArgumentParser()
parser.add_argument("--spark-version", help="spark version e.g. 1.6 or 2.2", dest='spark_ver', default='1.6')
parser.add_argument("--cm_host", help="hostname of CM Server, default is local host", dest='cm_hostname')
parser.add_argument("--unravel-host", help="Unravel Server hostname", dest='unravel')
parser.add_argument("-user", "--user", help="CM Username", default='admin')
parser.add_argument("-pass", "--password", help="CM Password", default='admin')
parser.add_argument("-uuser", "--unravel_username", help="Unravel UI Username", default='admin')
parser.add_argument("-upass", "--unravel_password", help="Unravel UI Password", default='unraveldata')
argv = parser.parse_args()

if not argv.cm_hostname:
    argv.cm_hostname = Popen(['hostname'], stdout=PIPE).communicate()[0].strip()

if not argv.unravel:
    argv.unravel = Popen(['hostname'], stdout=PIPE).communicate()[0].strip()
    unravel_ip = re.search('[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}',
                                      Popen(['host', argv.unravel], stdout=PIPE).communicate()[0].strip()).group(0)
else:
    if re.match('[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}',argv.unravel):
        unravel_ip = argv.unravel
        try:
            if not 'not found' in Popen(['host', argv.unravel], stdout=PIPE).communicate()[0].strip():
                unravel_hostname = Popen(['host', argv.unravel], stdout=PIPE).communicate()[0].strip().split('domain name pointer ')
                argv.unravel = unravel_hostname[1][:-1]
            else:
                unravel_hostname = unravel_ip
        except:
            unravel_hostname = unravel_ip
            pass
    else:
        unravel_ip = re.search('[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}',
                                          Popen(['host', argv.unravel], stdout=PIPE).communicate()[0].strip()).group(0)

print("Unravel Hostname: %s\n" % argv.unravel)
print("Unravel IP: %s\n" % unravel_ip)

if re.search('1.[0-9]', argv.spark_ver):
    spark_ver = re.search('1.[0-9]', argv.spark_ver).group(0)
else:
    spark_ver = None
if re.search('2.[0-9]', argv.spark_ver):
    spark2_ver = re.search('2.[0-9]', argv.spark_ver).group(0)
else:
    spark2_ver = None


def generate_configs(unravel_host):
    configs = {}
    configs['hive-env'] = 'AUX_CLASSPATH=${AUX_CLASSPATH}:/opt/cloudera/parcels/UNRAVEL_SENSOR/lib/java/unravel_hive_hook.jar'

    configs['mapred-site'] = '''<property><name>mapreduce.task.profile</name><value>true</value></property>
<property><name>mapreduce.task.profile.maps</name><value>0-5</value></property>
<property><name>mapreduce.task.profile.reduces</name><value>0-5</value></property>
<property><name>mapreduce.task.profile.params</name><value>-javaagent:/opt/cloudera/parcels/UNRAVEL_SENSOR/lib/java/btrace-agent.jar=libs=mr -Dunravel.server.hostport=%s:4043</value></property>''' % unravel_host

    configs['hadoop-env'] = 'HADOOP_CLASSPATH=${HADOOP_CLASSPATH}:/opt/cloudera/parcels/UNRAVEL_SENSOR/lib/java/unravel_hive_hook.jar'

    configs['yarn-am'] = '-Djava.net.preferIPv4Stack=true -javaagent:/opt/cloudera/parcels/UNRAVEL_SENSOR/lib/java/btrace-agent.jar=libs=mr -Dunravel.server.hostport=%s:4043' % unravel_host

    configs['spark-defaults'] = '''spark.unravel.server.hostport=%s:4043
spark.driver.extraJavaOptions=-javaagent:/opt/cloudera/parcels/UNRAVEL_SENSOR/lib/java/btrace-agent.jar=config=driver,libs=spark-%s
spark.executor.extraJavaOptions=-javaagent:/opt/cloudera/parcels/UNRAVEL_SENSOR/lib/java/btrace-agent.jar=config=executor,libs=spark-%s''' % (unravel_host, spark_ver, spark_ver)

    configs['spark2-defaults'] = '''spark.unravel.server.hostport=%s:4043
spark.driver.extraJavaOptions=-javaagent:/opt/cloudera/parcels/UNRAVEL_SENSOR/lib/java/btrace-agent.jar=config=driver,libs=spark-%s
spark.executor.extraJavaOptions=-javaagent:/opt/cloudera/parcels/UNRAVEL_SENSOR/lib/java/btrace-agent.jar=config=executor,libs=spark-%s''' % (unravel_host, spark2_ver, spark2_ver)

    configs['hive-site'] = '''<property>
  <name>com.unraveldata.host</name>
  <value>%s</value>
  <description>Unravel hive-hook processing host</description>
</property>

<property>
  <name>com.unraveldata.hive.hook.tcp</name>
  <value>true</value>
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
''' % argv.unravel
    return configs

cm_username = argv.user
cm_pass = argv.password

web_api = requests.Session()
res = web_api.post("http://%s:7180/j_spring_security_check" % argv.cm_hostname, data={'j_username':cm_username,'j_password':cm_pass})
suggest_configs = generate_configs(argv.unravel)
suggest_configs_ip = generate_configs(unravel_ip)

cdh_info = web_api.get("http://%s:7180/api/v11/clusters/" % argv.cm_hostname)
cdh_version = json.loads(cdh_info.text)['items'][0]['fullVersion'].split('.')
resource = ApiResource(argv.cm_hostname, 7180, cm_username, cm_pass, version=11)
cluster_name = json.loads(cdh_info.text)['items'][0]['displayName']
cdh_version_short = '%s.%s' % (cdh_version[0], cdh_version[1])

print("CDH Version: %s" % cdh_version_short)

cluster = resource.get_all_clusters()[0]


def check_hive_config():
    hive_test_result = []
    h_groups = []
    for group in cluster.get_service('hive').get_all_role_config_groups():
        # print(group.roleType)
        if group.roleType == 'GATEWAY':
            h_groups.append(group)
            # print(h_groups)
        if group.roleType == 'HIVESERVER2':
            h_groups.append(group)

    for groups in h_groups:
        for name, config in groups.get_config(view='full').items():
            # Gateway Client Environment Advanced Configuration Snippet (Safety Valve) for hive-env.sh
            try:
                if name == 'hive_client_env_safety_valve':
                    print('------------------------------------------------------------------')
                    if suggest_configs['hive-env'] == config.value.strip() or suggest_configs_ip['hive-env'] == config.value.strip():
                        print("\nhive_client_env_safety_valve correct\n")
                        hive_test_result.append(True)
                    else:
                        print("\nError: hive_client_env_safety_valve NOT correct\n")
                        hive_test_result.append(False)
            except:
                print('\nError: Gateway Client Environment Advanced Configuration Snippet (Safety Valve) for hive-env.sh NOT found\n')
                hive_test_result.append(False)
            # Hive Client Advanced Configuration Snippet (Safety Valve) for hive-site.xml
            try:
                if name == 'hive_client_config_safety_valve':
                    print('------------------------------------------------------------------')
                    if  argv.unravel in config.value or unravel_ip in config.value:
                        print ('\nHive Client Advanced Configuration Snippet (Safety Valve) for hive-site.xml correct\n')
                        hive_test_result.append(True)
                        # print(name,hive_site_snip)
                    else:
                        hive_test_result.append(False)
                        print ('\nError: Hive Client Advanced Configuration Snippet (Safety Valve) for hive-site.xml NOT correct\n')
            except:
                print('\nError: Hive Client Advanced Configuration Snippet (Safety Valve) for hive-site.xml NOT found\n')
                hive_test_result.append(False)
            # HiveServer2 Advanced Configuration Snippet (Safety Valve) for hive-site.xml
            try:
                if name == 'hive_hs2_config_safety_valve':
                    print('------------------------------------------------------------------')
                    if argv.unravel in config.value or unravel_ip in config.value:
                        print('\nhive server 2 correct\n')
                        hive_test_result.append(True)
                    else:
                        print('\nError: hive server 2 NOT correct\n')
                        hive_test_result.append(False)
            except:
                print('\nError: Hive server 2 config NOT found\n')
                hive_test_result.append(False)
    return hive_test_result

def check_yarn_config():
    yarn_test_result = []
    y_groups = []
    for group in cluster.get_service('yarn').get_all_role_config_groups():
        if group.roleType == 'GATEWAY':
            y_groups.append(group)

    for name, config in y_groups[0].get_config(view='full').items():
        # Gateway Client Environment Advanced Configuration Snippet (Safety Valve) for hadoop-env.sh
        try:
            if name == 'mapreduce_client_env_safety_valve':
                print('------------------------------------------------------------------')
                if suggest_configs['hadoop-env'] == config.value.strip() or suggest_configs_ip['hadoop-env'] == config.value.strip():
                    print('\nYarn Hook ENV correct (hadoop-env)\n')
                    yarn_test_result.append(True)
                else:
                    print('\n[Error]: Yarn hadoop-env Hook ENV NOT correct (hadoop-env)\n')
                    yarn_test_result.append(False)
        except:
            print('\n[Error]: Yarn Hook ENV NOT found (hadoop-env)\n')
            yarn_test_result.append(False)

        # MapReduce Client Advanced Configuration Snippet (Safety Valve) for mapred-site.xml
        try:
            if name == 'mapreduce_client_config_safety_valve':
                print('------------------------------------------------------------------')
                if suggest_configs['mapred-site'].replace('\n','') == config.value.strip().replace('\n','') or suggest_configs_ip['mapred-site'].replace('\n','') == config.value.strip().replace('\n',''):
                    print('\nMapReduce Client Config for mapred-site.xml correct\n')
                    yarn_test_result.append(True)
                else:
                    print('\n[Error]: MapReduce Client Clinfig for mapred-site.xml NOT correct\n')
                    yarn_test_result.append(False)
        except:
            print('\n[Error]: MapReduce Client Clinfig for mapred-site.xml NOT found\n')
            yarn_test_result.append(False)

        # ApplicationMaster Java Opts Base
        try:
            if name == 'yarn_app_mapreduce_am_command_opts':
                print('------------------------------------------------------------------')
                if suggest_configs['yarn-am'] == config.value or suggest_configs_ip['yarn-am'] == config.value:
                    print('\nYarn Mapreduce AM command correct\n')
                    yarn_test_result.append(True)
                else:
                    print('\n[Error]: Yarn Mapreduce AM command NOT correct\n')
                    yarn_test_result.append(False)
        except:
            print('\n[Error]: Yarn Mapreduce AM command NOT found\n')
            yarn_test_result.append(False)
    return yarn_test_result

def check_spark_config():
    spark_test_result = []
    s_groups = []
    for group in cluster.get_service('spark_on_yarn').get_all_role_config_groups():
        if group.roleType == 'GATEWAY':
            s_groups.append(group)

    if spark_ver:
        for name, config in s_groups[0].get_config(view='full').items():
            # Spark Client Advanced Configuration Snippet (Safety Valve) for spark-conf/spark-defaults.conf
            try:
                if name == 'spark-conf/spark-defaults.conf_client_config_safety_valve':
                    print('------------------------------------------------------------------')
                    if suggest_configs['spark-defaults'] == config.value.strip() or suggest_configs_ip['spark-defaults'] == config.value.strip():
                        print('\nSpark-defaults correct\n')
                        spark_test_result.append(True)
                    else:
                        print('\n[Error]: Spark-defaults NOT correct\n')
                        spark_test_result.append(False)
            except:
                print('\n[Error]: Spark-defaults NOT found\n')
                spark_test_result.append(False)
        return spark_test_result


def check_spark2_config():
    spark2_test_result = []
    if spark2_ver:
        s2_groups = []
        try:
            for group in cluster.get_service('spark2_on_yarn').get_all_role_config_groups():
                if group.roleType == 'GATEWAY':
                    s2_groups.append(group)

            for name, config in s2_groups[0].get_config(view='full').items():
                # Spark Client Advanced Configuration Snippet (Safety Valve) for spark-conf/spark-defaults.conf
                if name == 'spark2-conf/spark-defaults.conf_client_config_safety_valve':
                    print('------------------------------------------------------------------')
                    if suggest_configs['spark2-defaults'] == config.value.strip().replace(' ','') or suggest_configs_ip['spark2-defaults'] == config.value.strip().replace(' ',''):
                        print('\nSpark2-defaults correct\n')
                        spark2_test_result.append(True)
                    else:
                        print('\n[Error]: Spark2-defaults NOT correct\n')
                        spark2_test_result.append(False)
        except:
            print('\n[Error]: Spark2-defaults NOT found\n')
            spark2_test_result.append(True)
        return spark2_test_result

def check_parcels():
    print('------------------------------------------------------------------')
    print('\nChecking Cloudera Manager Parcels Status\n')
    found_parcel = False
    for parcel in cluster.get_all_parcels():
        if parcel.product == 'UNRAVEL_SENSOR':
            found_parcel = True
            if cdh_version_short in parcel.version and parcel.stage == 'ACTIVATED':
                print(parcel.version + ' state: ' + parcel.stage)
            else:
                print(parcel.version + ' state: ' + parcel.stage)
    if not found_parcel:
        print('Unravel Sensor Parcel not exists')
    return [found_parcel]


def check_unravel_properties():
    unravel_properties_test_result = []
    print('------------------------------------------------------------------')
    print('\n\nChecking Unravel Properties\n')
    hive_config = cluster.get_service('hive').get_config()[0]
    hive_connection = 'jdbc:{db_type}://{host}:{port}/{db_name}'.format(db_type=hive_config['hive_metastore_database_type'],
                                                        host=hive_config['hive_metastore_database_host'],
                                                        port=hive_config['hive_metastore_database_port'],
                                                        db_name=hive_config['hive_metastore_database_name'])
    hive_password = hive_config['hive_metastore_database_password']
    try:
        file_path ='/usr/local/unravel/etc/unravel.properties'
        file_stat = os.stat(file_path)
        file_owner = pwd.getpwuid(file_stat.st_uid).pw_name

        #Unravel Folder Owner
        print('------------------------------------------------------------------')
        print('Unravel Folder Owner\n')
        if file_owner == 'hdfs':
            print(file_owner)
            unravel_properties_test_result.append(True)
        else:
            print(file_owner)
            unravel_properties_test_result.append(False)

        with open(file_path, 'r') as file:
            unravel_properties = file.read()
            file.close()

        #javax.jdo.option.ConnectionURL
        print('------------------------------------------------------------------')
        if hive_connection in unravel_properties:
            print('javax.jdo.option.ConnectionURL Correct')
        else:
            print('javax.jdo.option.ConnectionURL NOT correct')


        #javax.jdo.option.ConnectionPassword
        print('------------------------------------------------------------------')
        if hive_password in unravel_properties:
            print('javax.jdo.option.ConnectionPassword correct')
            unravel_properties_test_result.append(True)
        else:
            print('javax.jdo.option.ConnectionPassword Wrong')
            unravel_properties_test_result.append(False)
        return unravel_properties_test_result
    except Exception as e:
        print(e)
        return unravel_properties_test_result


def check_daemon_status(try_again=True):
    global login_token
    daemon_status_test_result = []
    unravel_base_url = 'http://%s:3000/api/v1/' % argv.unravel
    print('------------------------------------------------------------------')
    print('\nChecking Unravel Daemon Status\n')
    try:
        login_token = json.loads(requests.post(unravel_base_url + 'signIn', data={"username": argv.unravel_username,
                                                                                  "password": argv.unravel_password}).text)['token']
        print('Unravel Signin Token: %s\n' % login_token)
        daemon_status_test_result.append(True)
    except:
        print('[Error]: failed to get Unravel Signin token')
        daemon_status_test_result.append(False)
        return daemon_status_test_result

    try:
        daemon_status = json.loads(requests.get(unravel_base_url + 'manage/daemons_status',
                                                 headers = {'Authorization': 'JWT %s' % login_token}).text)

        for daemon in daemon_status.iteritems():
            if len(daemon[1]['errorMessages']) == 0 and len(daemon[1]['fatalMessages']) == 0:
                print(daemon[0])
            else:
                message = ''
                if daemon[1]['errorMessages']:
                    message += daemon[1]['errorMessages'][0]['msg']
                if daemon[1]['fatalMessages']:
                    message += daemon[1]['fatalMessages'][0]['msg']
                print(daemon[0] + ': %s' % message )
        daemon_status_test_result.append(True)
    except Exception as e:
        print(e)
        daemon_status_test_result.append(False)
        if requests.get(unravel_base_url + 'clusters').status_code == 200 and login_token and try_again:
            print('\nAble to connect to UI but unable to get Daemon Status try again in 30s')
            sleep(30)
            daemon_status_test_result = check_daemon_status(tru_again=False)
        else:
            print('\n[Error]: Couldn\'t connect to Unravel Daemons UI\nPlease Check /usr/local/unravel/logs/ and /var/log/ for unravel_*.log')
        # raise requests.exceptions.ConnectionError('Unable to connect to Unravel host: %s \nCheck Unravel Server Status or /usr/local/unravel/logs for more details' % argv.unravel)
    return daemon_status_test_result


def test_spark_example():
    print("\nRunning Sample Spark Job\n")
    spark_example_jar = '/opt/cloudera/parcels/CDH/lib/spark/lib/spark-examples.jar'
    command = 'spark-submit  --class org.apache.spark.examples.SparkPi /opt/cloudera/parcels/CDH/lib/spark/lib/spark-examples.jar 10 2> /tmp/sparktest.log'
    child_process = Popen(command ,shell=True, stdout=PIPE)
    result = child_process.communicate()[0]
    print(result)
    if child_process.returncode == 0:
        print("Spark Job run successfully")
        return [True]
    else:
        print("Sample Spark job run fail")
        return [False]


def test_spark_ui():
    print("\nChecking unravel spark UI\n")
    spark_ui_test_result = []
    unravel_base_url = 'http://%s:3000/api/v1/' % argv.unravel
    #find spark example application ID
    try:
        with open('/tmp/sparktest.log', 'r') as f:
            file = f.read()
            f.close()
        application_id = re.search('application_[0-9]{1,}_[0-9]{1,6}', file).group(0)
        print(application_id)

        sleep(20)
        job_annotation =  requests.get(unravel_base_url + 'spark/%s/annotation' % application_id, headers = {'Authorization': 'JWT %s' % login_token}).json()
        try_attemp = 0
        while len(job_annotation) > 0 and job_annotation['finished'] != True and try_attemp < 6:
            print("Waiting for log collection complete")
            sleep(10)
            try_attemp += 1
            job_annotation =  requests.get(unravel_base_url + 'spark/%s/annotation' % application_id, headers = {'Authorization': 'JWT %s' % login_token}).json()

        job_conf =  requests.get(unravel_base_url + 'spark/%s/conf' % application_id, headers = {'Authorization': 'JWT %s' % login_token}).json()
        job_dag = requests.get(unravel_base_url + 'spark/%s/dag' % application_id, headers = {'Authorization': 'JWT %s' % login_token}).json()

        if not len(job_conf) > 0:
            print("Spark conf record missing")
            spark_ui_test_result.append(False)
        else:
            spark_ui_test_result.append(True)
        if not len(job_dag) > 0:
            print("Spark execution record missing")
            spark_ui_test_result.append(False)
        else:
            spark_ui_test_result.append(True)
        return spark_ui_test_result
    except:
        return [False]


def test_mapr_example():
    print("\nRunning Sample MR Job\n")
    command = 'sudo -u hdfs hadoop jar /opt/cloudera/parcels/CDH/lib/hadoop-mapreduce/hadoop-mapreduce-examples.jar pi 20 100 2> /tmp/mrtest.log'
    child_process = Popen(command ,shell=True, stdout=PIPE)
    result = child_process.communicate()[0]
    print(result)
    if child_process.returncode == 0:
        print("MR Job run successfully")
        return [True]
    else:
        print("Sample MR job run fail")
        return [False]


def test_mapr_ui():
    print("\nChecking unravel MR UI\n")
    mapr_test_result=[]
    unravel_base_url = 'http://%s:3000/api/v1/' % argv.unravel
    #find spark example application ID
    try:
        with open('/tmp/mrtest.log', 'r') as f:
            file = f.read()
            f.close()
        application_id = re.search('job_[0-9]{1,}_[0-9]{1,6}', file).group(0)
        print(application_id)

        sleep(35)
        job_annotation =  requests.get(unravel_base_url + 'jobs/%s/annotation' % application_id, headers = {'Authorization': 'JWT %s' % login_token}).json()
        try_attemp = 0
        while len(job_annotation) > 0 and job_annotation['status'] != 'S' and try_attemp < 6:
            print("Waiting for log collection complete")
            sleep(30)
            try_attemp += 1
            job_annotation =  requests.get(unravel_base_url + 'jobs/%s/annotation' % application_id, headers = {'Authorization': 'JWT %s' % login_token}).json()

        job_timeline =  requests.get(unravel_base_url + 'jobs/%s/timeline' % application_id, headers = {'Authorization': 'JWT %s' % login_token}).text
        job_conf = requests.get(unravel_base_url + 'jobs/%s/configuration' % application_id, headers = {'Authorization': 'JWT %s' % login_token}).text
        job_usage = requests.get(unravel_base_url + 'apps/%s/resource_usage?metric_id=135' % application_id, headers = {'Authorization': 'JWT %s' % login_token}).json()
        if not job_annotation['totalMapTasks'] > 0:
            print("Map task attempts missing")
            mapr_test_result.append(False)
        else:
            mapr_test_result.append(True)
        if not len(job_timeline) > 0:
            print("Mapr timeline record missing")
            mapr_test_result.append(False)
        else:
            mapr_test_result.append(True)
        if not len(job_conf) > 0:
            print("MR configuration record missing")
            mapr_test_result.append(False)
        else:
            mapr_test_result.append(True)
        if not len(job_usage) > 0:
            print("MR resource usage record missing")
            mapr_test_result.append(False)
        else:
            mapr_test_result.append(True)
        return mapr_test_result
    except:
        return [False]


def test_hive_example():
    print("\nRunning Sample Hive Job\n")
    command = 'hive -e "create table if not exists default.test (eid int, name String); select count(*) from default.test" 2>/tmp/hivetest.log'
    child_process = Popen(command ,shell=True, stdout=PIPE)
    result = child_process.communicate()[0]
    print(result)
    if child_process.returncode == 0:
        print("Hive Job run successfully")
        return [True]
    else:
        print("Sample Spark job run fail")
        return [False]


def test_hive_ui():
    print("\nChecking unravel Hive UI\n")
    hive_ui_test_result = []
    unravel_base_url = 'http://%s:3000/api/v1/' % argv.unravel
    try:
        with open('/tmp/hivetest.log', 'r') as f:
            file = f.read()
            f.close()
        application_id = re.search('job_[0-9]{1,}_[0-9]{1,6}', file).group(0)
        print(application_id)
        sleep(35)
        job_annotation =  requests.get(unravel_base_url + 'jobs/%s/annotation' % application_id, headers = {'Authorization': 'JWT %s' % login_token}).json()
        try_attemp = 0
        while len(job_annotation) > 0 and job_annotation['status'] != 'S' and try_attemp < 6:
            print("Waiting for log collection complete")
            sleep(30)
            try_attemp += 1
            job_annotation =  requests.get(unravel_base_url + 'jobs/%s/annotation' % application_id, headers = {'Authorization': 'JWT %s' % login_token}).json()

        query_id = job_annotation['appid']

        try_attemp = 0
        hive_query_annotation = requests.get(unravel_base_url + 'hive_queries/%s/annotation' % query_id, headers = {'Authorization': 'JWT %s' % login_token}).json()
        while hive_query_annotation['status'] != "S" and hive_query_annotation['totalMRJobs'] == 0 and try_attemp < 6:
            print("Waiting for hive query to complete")
            sleep(20)
            hive_query_annotation = requests.get(unravel_base_url + 'hive_queries/%s/annotation' % query_id, headers = {'Authorization': 'JWT %s' % login_token})

        if not hive_query_annotation['totalMRJobs'] > 0:
            hive_ui_test_result.append(False)
        else:
            hive_ui_test_result.append(True)
        return hive_ui_test_result
    except Exception as e:
        return [False]


def main():
    hive_config_test =  'failed'
    yarn_config_test =  'failed'
    spark_config_test = 'failed'
    parcel_test =       'failed'
    daemon_test =       'failed'
    spark_test =        'failed'
    mapr_test =         'failed'
    mapr_ui_test =      'failed'
    spark_ui_test =     'failed'
    hive_test =         'failed'
    hive_ui_test =      'failed'

    if all(x == True for x in check_hive_config()):
        hive_config_test = 'passed'

    if all(x == True for x in check_yarn_config()):
        yarn_config_test = 'passed'

    if all(x == True for x in check_spark_config()):
        spark_config_test = 'passed'

    if all(x == True for x in check_parcels()):
        parcel_test = 'passed'

    if all(x == True for x in check_daemon_status()):
        daemon_test = 'passed'

    if all(x == True for x in test_mapr_example()):
        mapr_test = 'passed'

    if all(x == True for x in test_hive_example()):
        hive_test = 'passed'

    if all(x == True for x in test_spark_example()):
        spark_test = 'passed'

    if all(x == True for x in test_spark_ui()):
        spark_ui_test = 'passed'

    if all(x == True for x in test_mapr_ui()):
        mapr_ui_test = 'passed'

    if all(x == True for x in test_hive_ui()):
        hive_ui_test = 'passed'

    print("\nTest Result:")
    print("Hive Configuration Test: \t"     + hive_config_test)
    print("YARN Configuration Test: \t"     + yarn_config_test)
    print("SPARK Configuration Test: \t"    + spark_config_test)
    print("Parcel Test: \t\t\t"             + parcel_test)
    print("Dameon Test: \t\t\t"             + daemon_test)
    print("Spark Job Test: \t\t"            + spark_test)
    print("Spark Job UI Test: \t\t"         + spark_ui_test)
    print("Mapreduce Job Test: \t\t"        + mapr_test)
    print("Mapreduce Job UI Test: \t\t"     + mapr_ui_test)
    print("Hive Job Test: \t\t\t"           + hive_test)
    print("Hive Job UI Test: \t\t"          + hive_ui_test)


if __name__ == '__main__':
    main()
