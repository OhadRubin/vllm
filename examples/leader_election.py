import os
import subprocess
import json

def ip_addr():
    hostname = os.uname().nodename
    DESCRIBE = "gcloud alpha compute tpus tpu-vm describe {hostname}  --zone us-central2-b --format json"
    res = subprocess.getoutput(DESCRIBE.format(hostname=hostname))
    addr_list = []
    for endpoint in json.loads(res)['networkEndpoints']:
        ip_address = endpoint["accessConfig"]['externalIp']
        addr_list.append(ip_address)
    my_ip =  subprocess.getoutput("curl https://checkip.amazonaws.com").split("\n")[-1]
    leader_ip = min(addr_list)
    return addr_list, leader_ip, my_ip

def get_leader_ip():
    addr_list, leader_ip, my_ip = ip_addr()
    return leader_ip

# Keep this for command line usage
if __name__ == "__main__":
    print(get_leader_ip())