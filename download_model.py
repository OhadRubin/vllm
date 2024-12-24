#!/usr/bin/env python3

import os
import sys
import more_itertools
import argparse

# usage: python3.10 download_model.py --num-workers 2 --worker-id $MY_WORKER_ID --hf-token <>
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--num-workers', type=int, default=2)
    parser.add_argument('--worker-id', type=int, default=0)
    parser.add_argument('--hf-token', type=str, required=True)
    args = parser.parse_args()

    files = [f"model-{str(i+1).zfill(5)}-of-00030.safetensors" for i in range(30)]
    chunks = list(more_itertools.chunked(files, len(files) // args.num_workers))
    my_files = chunks[args.worker_id]

    command = f"huggingface-cli download --token {args.hf_token} --exclude '*original*' --local-dir /mnt/gcs_bucket/models/Llama-3.3-70B-Instruct/worker_{args.worker_id:02d}  meta-llama/Llama-3.3-70B-Instruct"
    for file in my_files:
        command += f" {file}"
    
    print(f"Executing command: {command}")
    os.system(command)

if __name__ == "__main__":
    main()
