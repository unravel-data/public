"""
 Unravel Auto Scaling on HDInsight
 v0.2.3
"""
import json
import logging
import subprocess
from time import sleep
try:
    import requests
except Exception as e:
    print(e)
    print('requests module is missing')

#############################################################
#                                                           #
#   Modify the variables below                              #
#                                                           #
#############################################################

unravel_base_url = 'http://52.170.202.86:3000'
memory_threshold = 80              #%
cpu_threshold = 80                 #%
min_nodes = 1                      # Min workerNodes
max_nodes = 3                      # Max workernodes Allowed
resource_group = 'UNRAVEL01'
cluster_name = 'autoscaling1'

#Unravel Log in credentials
login_data = {'user':{'login':'admin','password':'unraveldata'}}

#############################################################
#                                                           #
#   DO NOT Modify the variables below                       #
#                                                           #
#############################################################
try:
    login_uri = unravel_base_url + '/users/sign_in'
    app_search_uri = unravel_base_url + '/api/v1/apps/search'
    total_cores_across_hosts = unravel_base_url + '/api/v1/clusters/resources/cpu/total'
    total_memory_across_hosts = unravel_base_url + '/api/v1/clusters/resources/memory/total'
    allocated_cores_across_hosts = unravel_base_url + '/api/v1/clusters/resources/cpu/allocated'
    allocated_memory_across_hosts = unravel_base_url + '/api/v1/clusters/resources/memory/allocated'
except:
    LOGGER.error("Unravel Url is not exist")
    exit()

threshold_count_limit = 5

s = requests.Session()

def check_login():
    try:
        response = s.post(login_uri,json=login_data)
        # res = s.post(cdh_login, data=cdh_secret)
    except Exception as e:
        print(e)

    if response.status_code == 200:
        return True
    else:
        return True


def check_threshold(threshold_count, resources_usage):
    threshold_tolerance = 0.2
    cpu_usage = resources_usage['cpu_usage']
    memory_usage = resources_usage['memory_usage']
    total_cores = resources_usage['total_cores']
    total_memory = resources_usage['total_memory']
    nodes_count = resources_usage['nodes_count']
    if cpu_usage > cpu_threshold or memory_usage > memory_threshold:
        if threshold_count < threshold_count_limit:
            return ('Up Scale threshold reach')
        # if threshold_count >= threshold_count_limit and (total_cores < max_cpu_allow or total_memory < max_memory_allow):
        if threshold_count >= threshold_count_limit and nodes_count < max_nodes:
            return ('Up Scaling')
    elif cpu_usage < (cpu_threshold - (cpu_threshold * threshold_tolerance)) and memory_usage < (memory_threshold - (memory_threshold * threshold_tolerance)):
        # if threshold_count > -threshold_count_limit and (total_cores > min_cpu_allow or total_memory > min_memory_allow):
        if threshold_count > -threshold_count_limit and nodes_count > min_nodes:
            return ('Down Scale threshold reach')
        if threshold_count <= -threshold_count_limit :
            return ('Down Scaling')
    return ('No Action Needed')

# Get Cluster Workdernode Count
def get_workdernode():
    try:
        cluster_info = subprocess.check_output(['azure', 'hdinsight', 'cluster', 'show', '-g', resource_group, '-c', cluster_name, '--json'])
        cluster = json.loads(cluster_info)
        if cluster['name'] == cluster_name:
    		if cluster['properties']['computeProfile']['roles'][1]['name'] == 'workernode':
    			workerNodes = cluster['properties']['computeProfile']['roles'][1]['targetInstanceCount']
        return workerNodes
    except:
        return 0


def elastic_search():
    query_url = unravel_base_url + '/search/q/rm-search/cm'
    query_str = """{"sort":[{"startedTime":{"order":"desc"}}],
                    "from":0,
                    "size":0,
                    "query":{
                        "bool":{
                            "must":[{
                                        "range":{
                                            "date":{
                                                "gte":"now-2m/m","lt":"now"
                                            }
                                        }
                                    },
                                    {
                                        "term":{
                                            "clusterName": "%s"
                                        }
                                    }
                            ]
                        }
                    },
                    "aggs":{
                        "apps_over_time":{
                            "date_histogram":{"field":"date","interval":"30s"},
                                "aggs":{
                                    "avg_totalmb":{"avg":{"field":"totalMB"}},
                                    "avg_totalvc":{"avg":{"field":"totalVCores"}},
                                    "avg_allocatedmb":{"avg":{"field":"allocatedMB"}},
                                    "avg_allocatedvc":{"avg":{"field":"allocatedVCores"}}
                                }
                            }
                        }
                }""" % cluster_name
    res = s.post(query_url, data=str(query_str))
    search_result = json.loads(res.text).get("aggregations", "None")
    if search_result != "None":
        search_result = search_result['apps_over_time']['buckets'][-1]
        total_cores = search_result['avg_totalvc']['value']
        total_memory = search_result['avg_totalmb']['value']
        cores_allocated = search_result['avg_allocatedvc']['value']
        memory_allocated = search_result['avg_allocatedmb']['value']
        try:
            cpu_percent_usage = cores_allocated / total_cores  * 100
            memory_percent_usage = memory_allocated / total_memory  * 100
        except:
            cpu_percent_usage = 1.0
            memory_percent_usage = 1.0
        nodes_count = get_workdernode()

    return({'cpu_usage' : cpu_percent_usage,
            'memory_usage' : memory_percent_usage,
            'total_memory': total_memory,
            'total_cores': total_cores,
            'nodes_count' : nodes_count
           })

# Retrieve Allocated resources
def get_resources():
    try:
        # Current cpu percentage
        res = s.get(total_cores_across_hosts)
        res1 = s.get(allocated_cores_across_hosts)
        total_cores = float(json.loads(res.text)[-1]['avg_totalvc'])
        cores_allocated = float(json.loads(res1.text)[-1]['avg_allocatedvcores'])
        cpu_percent_usage = cores_allocated / total_cores  * 100

        # Current memory percentage and total_memory
        res = s.get(total_memory_across_hosts)
        res1 = s.get(allocated_memory_across_hosts)
        total_memory = float(json.loads(res.text)[-1]['avg_totalmb'])
        memory_allocated = float(json.loads(res1.text)[-1]['avg_allocatedmb'])
        memory_percent_usage = memory_allocated / total_memory  * 100

        # Get the number of workerNodes in cluster
        nodes_count = get_workdernode()

        return {'cpu_usage' : cpu_percent_usage,
                'memory_usage' : memory_percent_usage,
                'total_memory': total_memory,
                'total_cores': total_cores,
                'nodes_count' : nodes_count
               }
    except Exception as e:
        LOGGER.error("Get Resource Usage from Unravel Failed")
        print(e)
        exit()


# Retrieve Running Jobs
def get_run():
    search_input = {
                    "appStatus":["R"],
                    "from":0,
                    "appTypes":["mr","hive","spark","cascading","pig"]
                   }

    try:
        response = s.post(login_uri,json=login_data)
        res = s.post(app_search_uri,json=search_input)
    except requests.exceptions.RequestException as e:
        LOGGER.error("Unable to connect to Unravel Server\n")
        print(e)
        exit()

    if res.status_code == 200:
            parsed = json.loads(res.text)
            if parsed:
                for job_num in range(len(parsed['results'])):
                    duration = parsed['results'][job_num]['duration_long']
                    app_id = parsed['results'][job_num]['id'].encode('utf-8')
                    # print(app_id,duration,len(parsed['results']))
                    jobs_dict[app_id] = duration
                # print(json.dumps(parsed, indent=4, sort_keys=True))
                return (jobs_dict)
    else:
        LOGGER.error("Unravel Search endpoint failed")


def main():
    threshold_count = 0
    while True:
        if check_login:
            resources_usage = elastic_search()
            LOGGER.debug(resources_usage)

            decision = check_threshold(threshold_count, resources_usage)
            LOGGER.info(str("\ndecision: " + decision + "\nthreshold_count: " + str(threshold_count) + '\nWorkdernode: '+ str(resources_usage['nodes_count'])))
            if decision == 'Up Scale threshold reach':
                LOGGER.info('Threshold reach')
                threshold_count += 1
            elif decision == 'Up Scaling':
                LOGGER.info('More Resources Needed')
                #Adding more resources command goes here
                try:
                    resizing = subprocess.Popen(['azure', 'hdinsight', 'cluster', 'resize', '-g', resource_group, '-c', cluster_name, str(resources_usage['nodes_count']+1)],stdout=subprocess.PIPE, bufsize=1)
                except:
                    pass

                for line in iter(resizing.stdout.readline, b''):
                    if (line.find('Operation state:  Succeeded') > -1):
                    	resizing_err = 1
                    LOGGER.info(line)
                resizing.stdout.close()
                resizing.wait()

                if resizing_err:
                	LOGGER.info('Resizing Success')
                else:
                	LOGGER.error('Resizing Fail')

                #Adding more resources command goes here
                threshold_count = 0
            elif decision == 'Down Scale threshold reach':
                threshold_count -= 1
            elif decision == 'Down Scaling':
                LOGGER.info('No Extra Resources Needed')
                #Removing extra resources command goes here
                try:
                    resizing = subprocess.Popen(['azure', 'hdinsight', 'cluster', 'resize', '-g', resource_group, '-c', cluster_name, str(resources_usage['nodes_count']-1)],stdout=subprocess.PIPE, bufsize=1)
                except:
                    pass

                for line in iter(resizing.stdout.readline, b''):
                    if (line.find('Operation state:  Succeeded') > -1):
                    	resizing_err = 1
                    LOGGER.info(line)
                resizing.stdout.close()
                resizing.wait()

                if resizing_err:
                    LOGGER.info('Resizing Success')
                else:
                    LOGGER.error('Resizing Fail')

                #Removing extra resources command goes here
                threshold_count = 0
            elif decision == 'No Action Needed':
                threshold_count = 0
        else:
            LOGGER.error('Login Fail')

        sleep(120)

if __name__ == '__main__':
    LOGGER = logging.getLogger('hdinsight_autoscaling')
    LOGGER.setLevel(logging.DEBUG)
    LOGFILE = 'hdinsight_autoscaling.log'
    fileHandler = logging.FileHandler(LOGFILE)
    ch = logging.StreamHandler()
    ch.setLevel(logging.DEBUG)
    LOGFORMAT = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s : %(message)s')
    ch.setFormatter(LOGFORMAT)
    fileHandler.setFormatter(LOGFORMAT)
    LOGGER.addHandler(fileHandler)
    LOGGER.addHandler(ch)

    main()
