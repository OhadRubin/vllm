#!/bin/bash
# bash /home/ohadr/vllm/examples/run_cluster.sh "vllm serve /mnt/gcs_bucket/models/Llama-3.1-70B/  --max-model-len 16384 --tensor-parallel-size 8 --pipeline_parallel_size 1 --distributed-executor-backend ray --max-num-seqs 16 --served-model-name meta-llama/Llama-3.1-70B --chat-template examples/base.jinja"
# bash /home/ohadr/vllm/examples/run_cluster.sh "vllm serve /mnt/gcs_bucket/models/Llama-3.1-8B-Instruct/  --max-model-len 16384 --tensor-parallel-size 8 --pipeline_parallel_size 1 --distributed-executor-backend ray --max-num-seqs 16 --served-model-name meta-llama/Llama-3.1-8B-Instruct"
# bash examples/run_cluster_forever.sh "vllm serve /mnt/gcs_bucket/AI2_EasyLM/v18_use_cachingFalse_seq_length4096_num_epochs2_size8b/streaming_params_248/  --max-model-len 16384 --tensor-parallel-size 8 --pipeline_parallel_size 1 --distributed-executor-backend ray --max-num-seqs 16 --served-model-name meta-llama/Llama-3.1-8B-Instruct"
# bash examples/run_cluster_forever.sh "vllm serve /mnt/gcs_bucket/AI2_EasyLM/v37_remat_blockTrue_seq_length8192_stsTrue_size8b  --max-model-len 16384 --tensor-parallel-size 8 --pipeline_parallel_size 1 --distributed-executor-backend ray --max-num-seqs 16 --served-model-name meta-llama/Llama-3.1-8B-Instruct"

# bash /home/ohadr/vllm/examples/run_cluster.sh
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
ADDITIONAL_ARGS=("$@")
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
if [ "${CURRENT_IP}" == "${HEAD_NODE_ADDRESS}" ]; then
    # Wait for container to be ready
    # Convert array to space-separated string and wrap in quotes
    COMMAND="${ADDITIONAL_ARGS[*]}"
    # sudo docker exec -it node /bin/bash -c "$COMMAND"
    sudo docker exec -d node /bin/bash -c "$COMMAND"
    cd ~/vllm
    # python3.10 examples/run_on_dataset.py --dataset_name iohadrubin/gpqa --config_name gold_sft_0 --max_seq_length 16384 --num_workers 16 --max_tokens 2048 --suffix _v0  --verbose True --temperature 0.8
    python3.10 examples/run_on_dataset_async.py --dataset_name iohadrubin/reorder_thoughts_v1 --config_name default  --num_workers 16 \
        --max_tokens 4096 --suffix _v3  --verbose True --temperature 0 --split train --drop_last_msg True
fi
(cd ~/redis_queue && python3.10 -m src.barrier finish)
sudo docker stop node
sudo docker rm node

# bash /home/ohadr/vllm/examples/run_cluster.sh "vllm serve /mnt/gcs_bucket/models/Llama-3.1-8B-Instruct/  --max-model-len 16384 --tensor-parallel-size 8 --pipeline_parallel_size 1 --distributed-executor-backend ray --max-num-seqs 16 --served-model-name meta-llama/Llama-3.1-8B-Instruct"
# gsutil cp script.sh gs://meliad2_us2_backup/scripts/script.sh
# python3.10 -m src.enqueue  "gsutil cat gs://meliad2_us2_backup/scripts/script.sh | bash"