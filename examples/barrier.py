import zmq
import os
import subprocess
import json
import fire
import time
from typing import Optional
def ip_addr(zone: str):
    hostname = os.uname().nodename
    DESCRIBE = "gcloud alpha compute tpus tpu-vm describe {hostname}  --zone {zone} --format json"
    res = subprocess.getoutput(DESCRIBE.format(hostname=hostname, zone=zone))
    addr_list = []
    for endpoint in json.loads(res)['networkEndpoints']:
        ip_address = endpoint["accessConfig"]['externalIp']
        addr_list.append(ip_address)
    my_ip =  subprocess.getoutput("curl https://checkip.amazonaws.com").split("\n")[-1]
    sorted_addr_list = sorted(addr_list)
    leader_ip = sorted_addr_list[0]
    return sorted_addr_list, leader_ip, my_ip





# connects to leader and listens for commands
def follower_loop(my_ip: str, leader_ip: str):
    while True:
        try:
            print(f"follower {my_ip} waiting for leader {leader_ip} to finish")
            context = zmq.Context()
            socket = context.socket(zmq.SUB)
            socket.connect(f"tcp://{leader_ip}:5556")
            socket.setsockopt_string(zmq.SUBSCRIBE, "")  # Subscribe to all messages
            socket.setsockopt(zmq.RCVTIMEO, 5000)  # 5 second timeout
            try:
                return socket.recv_string()
            except zmq.error.Again:
                raise Exception(f"Timeout waiting for leader {leader_ip} to publish")
            
            
            # we only receive the command once the leader finishes
        except Exception as e:
            time.sleep(1)


# python3.10 examples/barrier.py finish
def finish():
    context = zmq.Context()
    socket = context.socket(zmq.PUB)
    socket.bind("tcp://*:5556")
    # Give time for subscribers to connect
    time.sleep(1)
    socket.send_string("finish")
    socket.close()
    
# python3.10 examples/barrier.py start
# only the leader passes the barrier, the rest wait for the leader to finish
def start(my_ip:Optional[str]=None, leader_ip:Optional[str]=None, zone: str="us-central2-b"):
    
    if my_ip is None and leader_ip is None:
        _, leader_ip, my_ip = ip_addr(zone)
    else:
        assert my_ip is not None
        assert leader_ip is not None

    if my_ip != leader_ip:
        follower_loop(my_ip, leader_ip)
        print(f"follower {my_ip} finished")
    else:
        print(f"leader {my_ip} does other stuff now")
    
    
if __name__ == "__main__":
    fire.Fire()
