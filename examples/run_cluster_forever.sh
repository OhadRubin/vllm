#!/bin/bash
# bash examples/run_cluster_forever.sh "vllm serve /mnt/gcs_bucket/models/Llama-3.1-70B/  --max-model-len 16384 --tensor-parallel-size 8 --pipeline_parallel_size 1 --distributed-executor-backend ray --max-num-seqs 16 --served-model-name meta-llama/Llama-3.1-70B --chat-template examples/base.jinja"
# bash examples/run_cluster_forever.sh "vllm serve /mnt/gcs_bucket/models/Llama-3.1-8B-Instruct/  --max-model-len 16384 --tensor-parallel-size 8 --pipeline_parallel_size 1 --distributed-executor-backend ray --max-num-seqs 16 --served-model-name meta-llama/Llama-3.1-8B-Instruct"
# bash examples/run_cluster_forever.sh "vllm serve /mnt/gcs_bucket/AI2_EasyLM/v6_use_cachingTrue_seq_length4096_num_epochs1_size8b/huggingface_params  --max-model-len 16384 --tensor-parallel-size 8 --pipeline_parallel_size 1 --distributed-executor-backend ray --max-num-seqs 16 --served-model-name meta-llama/Llama-3.1-8B-Instruct"

# bash examples/run_cluster_forever.sh "vllm serve /mnt/gcs_bucket/AI2_EasyLM/v18_use_cachingFalse_seq_length4096_num_epochs2_size8b/streaming_params_248/  --max-model-len 16384 --tensor-parallel-size 8 --pipeline_parallel_size 1 --distributed-executor-backend ray --max-num-seqs 16 --served-model-name meta-llama/Llama-3.1-8B-Instruct"

# bash examples/run_cluster_forever.sh "vllm serve /mnt/gcs_bucket/AI2_EasyLM/v38_remat_blockTrue_seq_length8192_stsTrue_size8b  --max-model-len 16384 --tensor-parallel-size 8 --pipeline_parallel_size 1 --distributed-executor-backend ray --max-num-seqs 16 --served-model-name meta-llama/Llama-3.1-8B-Instruct"


# bash examples/run_cluster_forever.sh
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

if ! sudo docker images | grep -q tpu-vm-base; then
    echo "tpu-vm-base image not found, building..."
    (cd ~/vllm && sudo docker build -t tpu-vm-base -f Dockerfile.tpu .)
fi

# Additional arguments are passed directly to the Docker command
ADDITIONAL_ARGS=("$@")

# rm -rf ~/.cache/huggingface
# Define a function to cleanup on EXIT signal
cleanup() {
    sudo docker stop node
    sudo docker rm node
}
trap cleanup EXIT

sudo docker stop node
sudo docker rm node
# Kill any existing start_tunnel processes

# Command setup for head or worker node
RAY_START_CMD="ray start --block --num-cpus=220 --resources='{\"TPU\": 4}'"
if [ "${CURRENT_IP}" == "${HEAD_NODE_ADDRESS}" ]; then
    RAY_START_CMD+=" --head --port=6379"
    pkill -f -9 start_tunnel.sh
    pkill -f -9 portr

else
    RAY_START_CMD+=" --address=${HEAD_NODE_ADDRESS}:6379"
fi

python3.10 -c "import jax; from jax.experimental.multihost_utils import sync_global_devices; sync_global_devices('bla'); print(jax.process_index())"

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

if [ "${CURRENT_IP}" == "${HEAD_NODE_ADDRESS}" ]; then
    # Wait for container to be ready
    # Convert array to space-separated string and wrap in quotes
    COMMAND="${ADDITIONAL_ARGS[*]}"
    (bash start_tunnel.sh &)
    sudo docker exec node /bin/bash -c "$COMMAND"
else
    while true; do
        sleep 60
    done

fi