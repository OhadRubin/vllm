
HEAD_NODE_ADDRESS="$1"
CURRENT_IP=$(curl https://checkip.amazonaws.com)
echo "Current IP address: ${CURRENT_IP}"


# Command setup for head or worker node
RAY_START_CMD="ray start --block"

if [ "${CURRENT_IP}" == "${HEAD_NODE_ADDRESS}" ]; then
    RAY_START_CMD_AUX=" --head --port=6379"
else
    RAY_START_CMD_AUX=" --address=${HEAD_NODE_ADDRESS}:6379"
fi

# echo "Starting Ray with command: ${RAY_START_CMD}"
# ${RAY_START_CMD}

ray start --block --num-cpus=220 --resources="{\"tpu\": 4}" $RAY_START_CMD_AUX 