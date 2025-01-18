#!/bin/bash
# bash examples/run_cluster_forever.sh "vllm serve /mnt/gcs_bucket/models/Llama-3.1-70B/  --max-model-len 16384 --tensor-parallel-size 8 --pipeline_parallel_size 1 --distributed-executor-backend ray --max-num-seqs 16 --served-model-name meta-llama/Llama-3.1-70B --chat-template examples/base.jinja"

# stsTrue!!
# bash examples/run_cluster_forever.sh "vllm serve /mnt/gcs_bucket/AI2_EasyLM/v46_remat_blockTrue_seq_length4096_stsTrue_size70b  --max-model-len 16384 --tensor-parallel-size 8 --pipeline_parallel_size 1 --distributed-executor-backend ray --max-num-seqs 16 --served-model-name meta-llama/Llama-3.1-70B-Instruct"
# False!!
# bash examples/run_cluster_forever.sh "vllm serve /mnt/gcs_bucket/AI2_EasyLM/v48_remat_blockTrue_seq_length4096_stsFalse_size70b  --max-model-len 16384 --tensor-parallel-size 8 --pipeline_parallel_size 1 --distributed-executor-backend ray --max-num-seqs 16 --served-model-name meta-llama/Llama-3.1-70B-Instruct"

# bash examples/run_cluster_forever.sh "vllm serve /mnt/gcs_bucket/models/Llama-3.1-8B-Instruct/  --max-model-len 16384 --tensor-parallel-size 8 --pipeline_parallel_size 1 --distributed-executor-backend ray --max-num-seqs 16 --served-model-name meta-llama/Llama-3.1-8B-Instruct"
# bash examples/run_cluster_forever.sh "vllm serve /mnt/gcs_bucket/AI2_EasyLM/v6_use_cachingTrue_seq_length4096_num_epochs1_size8b/huggingface_params  --max-model-len 16384 --tensor-parallel-size 8 --pipeline_parallel_size 1 --distributed-executor-backend ray --max-num-seqs 16 --served-model-name meta-llama/Llama-3.1-8B-Instruct"

# bash examples/run_cluster_forever.sh "vllm serve /mnt/gcs_bucket/AI2_EasyLM/v18_use_cachingFalse_seq_length4096_num_epochs2_size8b/streaming_params_248/  --max-model-len 16384 --tensor-parallel-size 8 --pipeline_parallel_size 1 --distributed-executor-backend ray --max-num-seqs 16 --served-model-name meta-llama/Llama-3.1-8B-Instruct"

# bash examples/run_cluster_forever.sh "vllm serve /mnt/gcs_bucket/AI2_EasyLM/v38_remat_blockTrue_seq_length8192_stsTrue_size8b  --max-model-len 16384 --tensor-parallel-size 8 --pipeline_parallel_size 1 --distributed-executor-backend ray --max-num-seqs 16 --served-model-name meta-llama/Llama-3.1-8B-Instruct"
# bash examples/run_cluster_forever.sh "vllm serve /mnt/gcs_bucket/AI2_EasyLM/v46_remat_blockFalse_use_raTrue_seq_length2048_size8b  --max-model-len 16384 --tensor-parallel-size 8 --pipeline_parallel_size 1 --distributed-executor-backend ray --max-num-seqs 16 --served-model-name meta-llama/Llama-3.1-8B-Instruct"


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


sync_devices() {
  # Sync devices if needed
  python3.10 -c "
import jax
from jax.experimental.multihost_utils import sync_global_devices
sync_global_devices('bla')
print('Process index:', jax.process_index())
"
}

build_docker_image() {
  local image="$1"
  if ! sudo docker images | grep -q "$image"; then
    echo "Building image: $image"
    (cd ~/vllm && sudo docker build -t "$image" -f Dockerfile.tpu .)
  fi
}


maybe_install_packages() {
  if [ "$MODE" = "dataset" ]; then
    python3.10 -m pip install openai==1.17.0 huggingface-hub
  fi
}

maybe_clear_cache() {
  # If gcs_cache is bigger than 150GB
  if [ -d "/dev/shm/gcs_cache" ] && [ "$(du -s /dev/shm/gcs_cache | cut -f1)" -gt 137957972 ]; then
    sudo rm -rf /dev/shm/gcs_cache
    sudo mkdir -p /dev/shm/gcs_cache
    sudo chmod 777 /dev/shm/gcs_cache
    sudo chown -R "$USER":"$USER" /dev/shm/gcs_cache
  fi
}


build_docker_image "$DOCKER_IMAGE"


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

sync_devices
maybe_clear_cache


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