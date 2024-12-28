
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
    return hostname,addr_list

if __name__ == "__main__":
    print(ip_addr())