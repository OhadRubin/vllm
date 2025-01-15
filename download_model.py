#!/usr/bin/env python3

import os
import sys
import importlib.util

# Import leader_election.py using importlib
spec = importlib.util.spec_from_file_location(
    "leader_election", 
    "/home/ohadr/vllm/examples/leader_election.py"
)
leader_election = importlib.util.module_from_spec(spec)
spec.loader.exec_module(leader_election)
ip_addr = leader_election.ip_addr

import more_itertools
import argparse

"""
curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | sudo bash
sudo apt-get install git-lfs
git lfs install
git clone https://iohadrubin:$HF_TOKEN@huggingface.co/meta-llama/Llama-3.1-405B

"""
# usage: python3.10 download_model.py --hf-token $HF_TOKEN --model-name meta-llama/Llama-3.1-405B --n-chunks 191
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--hf-token', type=str, required=True)
    parser.add_argument('--model-name', type=str, default="meta-llama/Llama-3.1-70B")
    parser.add_argument('--n-chunks', type=int, default=30)
    args = parser.parse_args()
    addr_list, _, my_ip = ip_addr()
    num_workers = len(addr_list)
    worker_id = addr_list.index(my_ip)
    files = [f"model-{str(i+1).zfill(5)}-of-{args.n_chunks:05d}.safetensors" for i in range(args.n_chunks)]
    chunks = list(more_itertools.chunked(files, len(files) // num_workers))
    my_files = chunks[worker_id]
    
    
    model_suffix = args.model_name.split("/")[-1]
    command = f"huggingface-cli download --token {args.hf_token} --exclude '*original*' --local-dir /mnt/gcs_bucket/models/{model_suffix}/worker_{worker_id:02d}  {args.model_name}"
    files_to_download = []
    for file in my_files:
        if os.path.exists(f"/mnt/gcs_bucket/models/{model_suffix}/worker_{worker_id:02d}/{file}"):
            print(f"Skipping {file} as it already exists")
            continue
        files_to_download.append(file)
    if len(files_to_download)>0:
        command = f"{command} {' '.join(files_to_download)}"
        print(f"Executing command: {command}")
        os.system(command)
    # Move files from worker folder to base folder
    move_command = f"mv /mnt/gcs_bucket/models/{model_suffix}/worker_{worker_id:02d}/* /mnt/gcs_bucket/models/{model_suffix}/"
    print(f"Moving files: {move_command}")
    os.system(move_command)
    
    if worker_id==0:
        # remove worker folders
        os.system(f"huggingface-cli download --token {args.hf_token} --exclude '*original*' --local-dir /mnt/gcs_bucket/models/{model_suffix}  {args.model_name} config.json generation_config.json model.safetensors.index.json special_tokens_map.json tokenizer_config.json tokenizer.json")

if __name__ == "__main__":
    main()
