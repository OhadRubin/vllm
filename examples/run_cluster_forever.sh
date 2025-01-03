#!/bin/bash
# bash /home/ohadr/vllm/examples/run_cluster.sh "vllm serve /mnt/gcs_bucket/models/Llama-3.1-70B/  --max-model-len 16384 --tensor-parallel-size 8 --pipeline_parallel_size 1 --distributed-executor-backend ray --max-num-seqs 16 --served-model-name meta-llama/Llama-3.1-70B --chat-template examples/base.jinja"
# bash /home/ohadr/vllm/examples/run_cluster.sh "vllm serve /mnt/gcs_bucket/models/Llama-3.1-8B-Instruct/  --max-model-len 16384 --tensor-parallel-size 8 --pipeline_parallel_size 1 --distributed-executor-backend ray --max-num-seqs 16 --served-model-name meta-llama/Llama-3.1-8B-Instruct"
# bash /home/ohadr/vllm/examples/run_cluster.sh
(cd ~/vllm && git pull)
# Get the current IP address
CURRENT_IP=$(curl https://checkip.amazonaws.com)
echo "Current IP address: ${CURRENT_IP}"

 
source ~/.bashrc
# Assign the first three arguments and shift them away
DOCKER_IMAGE=tpu-vm-base
HEAD_NODE_ADDRESS=$(python3.10 examples/leader_election.py)
PATH_TO_HF_HOME=~/.cache/huggingface


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

if [ "${CURRENT_IP}" == "${HEAD_NODE_ADDRESS}" ]; then
    # Wait for container to be ready
    # Convert array to space-separated string and wrap in quotes
    COMMAND="${ADDITIONAL_ARGS[*]}"
    
    sudo docker exec node /bin/bash -c "$COMMAND"
else
    while true; do
        sleep 60
    done

fi