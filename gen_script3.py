# python3.10 gen_script3.py
from import_from_gist import import_from_gist
import mlxu
import datetime
from collections import defaultdict
import sys
import os
sys.path.append(os.path.expanduser("~/redis_queue"))
from src.redis_queue import RedisQueue


preramble=r"""
#!/bin/bash
cd ~/vllm
(cd ~/vllm && git pull)
# Get the current IP address
CURRENT_IP=$(curl https://checkip.amazonaws.com)
echo "Current IP address: ${CURRENT_IP}"

 
source ~/.bashrc
# Assign the first three arguments and shift them away
DOCKER_IMAGE=tpu-vm-base
HEAD_NODE_ADDRESS=$(python3.10 examples/leader_election.py)
PATH_TO_HF_HOME=~/.cache/huggingface


# Check if tpu-vm-base image exists
if ! sudo docker images | grep -q tpu-vm-base; then
    echo "tpu-vm-base image not found, building..."
    (cd ~/vllm && sudo docker build -t tpu-vm-base -f Dockerfile.tpu .)
fi


# Additional arguments are passed directly to the Docker command
python3.10 -m pip install openai==1.17.0 huggingface-hub
# rm -rf ~/.cache/huggingface
# Define a function to cleanup on EXIT signal
cleanup() {
    sudo docker stop node
    sudo docker rm node
}
trap cleanup EXIT
pkill -f -9 start_tunnel.sh
pkill -f -9 portr
sudo docker stop node
sudo docker rm node

export HOSTNAME=$(hostname)

export HF_TOKEN=$(bash -ic 'source ~/.bashrc; echo $HF_TOKEN')

sudo mkdir -p /dev/shm/gcs_cache
sudo chmod 777 /dev/shm/gcs_cache
sudo chown -R $USER:$USER /dev/shm/gcs_cache
sudo umount -l /mnt/gcs_bucket
sleep 1
gcsfuse \
        --implicit-dirs \
        --file-cache-enable-parallel-downloads \
        --file-cache-parallel-downloads-per-file 100 \
        --file-cache-max-parallel-downloads -1 \
        --file-cache-download-chunk-size-mb 10 \
        --file-cache-max-size-mb 153600 \
        --dir-mode 0777 \
        -o allow_other --foreground \
        --cache-dir /dev/shm/gcs_cache  \
        meliad2_us2_backup /mnt/gcs_bucket &> ~/gcs_log.log &
sleep 1


# Command setup for head or worker node
RAY_START_CMD="ray start --block --num-cpus=220 --resources='{\"TPU\": 4}'"
if [ "${CURRENT_IP}" == "${HEAD_NODE_ADDRESS}" ]; then
    RAY_START_CMD+=" --head --port=6379"
else
    RAY_START_CMD+=" --address=${HEAD_NODE_ADDRESS}:6379"
fi

sudo docker run  \
    -d \
    -v /home/$USER/vllm:/workspace/vllm \
    --entrypoint /bin/bash \
    --network host \
    --name node \
    --shm-size 10.24g \
    --privileged \
    -e HF_TOKEN="${HF_TOKEN}" \
    -e GLOO_SOCKET_IFNAME=ens8 \
    -e VLLM_XLA_CACHE_PATH=/mnt/gcs_bucket/xla_cache \
    -v "/dev/shm/gcs_cache:/dev/shm/gcs_cache" \
    "${DOCKER_IMAGE}" -c "cd /workspace/vllm && git config --global --add safe.directory /workspace/vllm  && git pull  &&  bash gcs_fuse_install.sh && ${RAY_START_CMD}"


echo "done loading ray process"
(cd ~/redis_queue && python3.10 -m src.barrier start)
"""




exec_str=r"""
if [ "${CURRENT_IP}" == "${HEAD_NODE_ADDRESS}" ]; then
    # Wait for container to be ready
    # Convert array to space-separated string and wrap in quotes
    # sudo docker exec -it node /bin/bash -c "$COMMAND"
    sudo docker exec -d node /bin/bash -c "vllm serve $MODEL_PATH  --max-model-len $MAX_MODEL_LEN --tensor-parallel-size 8 --pipeline_parallel_size 1 --distributed-executor-backend ray --max-num-seqs $MAX_NUM_SEQS --served-model-name $SERVED_MODEL_NAME"
    cd ~/vllm
    # python3.10 examples/run_on_dataset.py --dataset_name iohadrubin/gpqa --config_name gold_sft_0 --max_seq_length 16384 --num_workers 16 --max_tokens 2048 --suffix _v0  --verbose True --temperature 0.8
    python3.10 examples/run_on_dataset.py --dataset_name $DATASET_NAME --config_name default  --num_workers 16 \
        --max_tokens 4096 --suffix $SUFFIX  --verbose True --temperature 0 --split train --drop_last_msg True \
        --output_dir /mnt/gcs_bucket/generated_data/$HOSTNAME --shard_id $SHARD_ID --num_shards $NUM_SHARDS
fi
(cd ~/redis_queue && python3.10 -m src.barrier finish)
sudo docker stop node
sudo docker rm node
"""

EXP_COUNTi = 20
dag = import_from_gist("a94e76aedf3d02bde2f50d799d12ec5b")
Branch = dag.Branch
Node = dag.Node

# size can be 1b or 8b
config =dag.load_config("""
---
TPU, tpu, 16
DATASET_NAME, dataset_name, iohadrubin/reorder_thoughts_v1
SUFFIX, suffix, _v3
SHARD_ID, shard_id, 2
NUM_SHARDS, num_shards, 16
MODEL_PATH, model_path, /mnt/gcs_bucket/AI2_EasyLM/v18_use_cachingFalse_seq_length4096_num_epochs2_size8b/streaming_params_248/
MAX_MODEL_LEN, max_model_len, 16384
MAX_NUM_SEQS, max_num_seqs, 16
SERVED_MODEL_NAME, served_model_name, meta-llama/Llama-3.1-8B-Instruct
""")


with dag.DAG() as experiment:
  num_shards(16) >> shard_id(*range(2, 16)) >> suffix("_v4")
#   size("8b") >> num_epochs(4) >> dt("gold_sft") >> cvi(0)

        

task_dict, odict = dag.get_all_experiments(experiment, config, EXP_COUNTi)

now = datetime.datetime.now()
path_prefix = "gs://meliad2_us2_backup/scripts"
formatted_date = now.strftime("%d_%m_%Y")
tpu_dict = defaultdict(list)
for k, v in task_dict.items():
    file_path = f"{path_prefix}/{formatted_date}/{k}.sh"
    
    tpu_dict[odict[k]["TPU"]].append(file_path)
    cmds = [preramble, v, exec_str]
        
    script = "\n".join(cmds)
    # print(f"writing {k} into {file_path}")
    print(f"gsutil cat {file_path} > /tmp/script.sh; bash /tmp/script.sh")
    with mlxu.open_file(file_path, 'w') as fin:
        fin.write(script)
# if False:
for k in tpu_dict.keys():
    q_name = f"v4-{k}"
    queue = RedisQueue(name=q_name)
    for v in tpu_dict[k]:
        cmd = f"gsutil cat {v} > /tmp/script.sh; bash /tmp/script.sh"
        print(f"adding {cmd} to {q_name}")
        queue.put(cmd)