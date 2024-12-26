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
    parser.add_argument('--model-name', type=str, default="meta-llama/Llama-3.1-70B")
    parser.add_argument('--n-chunks', type=int, default=30)
    args = parser.parse_args()

    files = [f"model-{str(i+1).zfill(5)}-of-{args.n_chunks:05d}.safetensors" for i in range(args.n_chunks)]
    chunks = list(more_itertools.chunked(files, len(files) // args.num_workers))
    my_files = chunks[args.worker_id]
    
    
    model_suffix = args.model_name.split("/")[-1]
    command = f"huggingface-cli download --token {args.hf_token} --exclude '*original*' --local-dir /mnt/gcs_bucket/models/{model_suffix}/worker_{args.worker_id:02d}  {args.model_name}"
    files_to_download = []
    for file in my_files:
        if os.path.exists(f"/mnt/gcs_bucket/models/{model_suffix}/worker_{args.worker_id:02d}/{file}"):
            print(f"Skipping {file} as it already exists")
            continue
        files_to_download.append(file)
    if len(files_to_download)>0:
        command = f"{command} {' '.join(files_to_download)}"
        print(f"Executing command: {command}")
        os.system(command)
    # Move files from worker folder to base folder
    move_command = f"mv /mnt/gcs_bucket/models/{model_suffix}/worker_{args.worker_id:02d}/* /mnt/gcs_bucket/models/{model_suffix}/"
    print(f"Moving files: {move_command}")
    os.system(move_command)
    
    if args.worker_id==0:
        # remove worker folders
        os.system(f"huggingface-cli download --token {args.hf_token} --exclude '*original*' --local-dir /mnt/gcs_bucket/models/{model_suffix}  {args.model_name} config.json generation_config.json model.safetensors.index.json special_tokens_map.json tokenizer_config.json tokenizer.json")

if __name__ == "__main__":
    main()
