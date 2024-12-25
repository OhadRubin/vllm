#!/usr/bin/env python3

import os
import sys
import more_itertools
import argparse

# usage: python3.10 download_model.py --num-workers 2 --worker-id $MY_WORKER_ID --hf-token <>
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

    command = f"huggingface-cli download --token {args.hf_token} --exclude '*original*' --local-dir /mnt/gcs_bucket/models/Llama-3.1-70B/worker_{args.worker_id:02d}  meta-llama/Llama-3.1-70B"
    files_to_download = []
    for file in my_files:
        if os.path.exists(f"/mnt/gcs_bucket/models/Llama-3.1-70B/worker_{args.worker_id:02d}/{file}"):
            print(f"Skipping {file} as it already exists")
            continue
        files_to_download.append(file)
    if len(files_to_download)>0:
        command = f"{command} {' '.join(files_to_download)}"
        print(f"Executing command: {command}")
        os.system(command)
    # Move files from worker folder to base folder
    move_command = f"mv /mnt/gcs_bucket/models/Llama-3.1-70B/worker_{args.worker_id:02d}/* /mnt/gcs_bucket/models/Llama-3.1-70B/"
    print(f"Moving files: {move_command}")
    os.system(move_command)
    
    if args.worker_id==0:
        # remove worker folders
        os.system(f"huggingface-cli download --token {args.hf_token} --exclude '*original*' --local-dir /mnt/gcs_bucket/models/Llama-3.1-70B  meta-llama/Llama-3.1-70B config.json generation_config.json model.safetensors.index.json special_tokens_map.json tokenizer_config.json tokenizer.json")

if __name__ == "__main__":
    main()
