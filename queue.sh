#!/bin/bash
# ./queue.sh enqueue 'echo hi'
# Configuration
REDIS_HOST="ohadrubin.com"
REDIS_PORT=31600
QUEUE_NAME="cmd_queue"
WORKERS_SET="active_workers"
MAX_RETRIES=10
RETRY_DELAY=3

# Install dependencies if missing
if ! command -v redis-cli &>/dev/null; then
    sudo apt-get update -qq
    sudo apt-get install -y redis-tools || {
        echo "Could not install redis-tools" >&2
        exit 1
    }
fi

# Secure connection
redis_cmd() {
    redis-cli -u "redis://:${REDIS_PASSWORD}@${REDIS_HOST}:${REDIS_PORT}" --no-auth-warning "$@"
}

# Check connection
check_redis() {
    if ! ping_output=$(redis_cmd PING 2>&1); then
        echo "Redis connection error. Verify:" >&2
        echo "1. Server at ${REDIS_HOST}:${REDIS_PORT}"
        echo "2. Credentials"
        echo "3. Network"
        return 1
    fi
    if [[ "$ping_output" != "PONG" ]]; then
        echo "PING response mismatch: $ping_output" >&2
        return 1
    fi

    # Pub/Sub check
    local test_channel="connection_test_$RANDOM"
    if ! redis_cmd PUBLISH "$test_channel" "test" >/dev/null; then
        echo "Pub/Sub check error. Check server configuration." >&2
        return 1
    fi
    return 0
}

# Get node info
get_node_info() {
    export CURRENT_IP=$(curl -s --max-time 3 https://checkip.amazonaws.com || echo "127.0.0.1")
    export HEAD_NODE_ADDRESS=$(python3.10 ~/vllm/examples/leader_election.py 2>/dev/null || echo "$CURRENT_IP")
    
    if [[ ! "$HEAD_NODE_ADDRESS" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        HEAD_NODE_ADDRESS="$CURRENT_IP"
    fi
    
    GROUP_CHANNEL="group_commands:${HEAD_NODE_ADDRESS//./_}"
    WORKER_ID="${CURRENT_IP}:${RANDOM}"
    echo "Group Channel: $GROUP_CHANNEL"
    echo "Worker ID: $WORKER_ID"
}

# Register worker
register_worker() {
    redis_cmd SADD "$WORKERS_SET" "$WORKER_ID"
    trap 'redis_cmd SREM "$WORKERS_SET" "$WORKER_ID"; exit 0' INT TERM EXIT
}

# Get worker count
get_worker_count() {
    redis_cmd SCARD "$WORKERS_SET"
}

# Command execution
execute_command() {
    local cmd="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Executing: $cmd"
    if [[ -z "$cmd" ]] || [[ "$cmd" == "cmd_queue" ]]; then
        return 1
    fi
    if ! eval "$cmd"; then
        echo "[ERROR] Command error: $cmd" >&2
        return 1
    fi
}

# Follower
follow_leader() {
    echo "Starting follower for group $GROUP_CHANNEL"
    while true; do
        echo "WAITING FOR COMMAND"
        msg=$(python3.10 -c "
import os
import zmq
context = zmq.Context()
socket = context.socket(zmq.SUB)
socket.connect('tcp://' + os.getenv('HEAD_NODE_ADDRESS','127.0.0.1') + ':5556')
socket.setsockopt_string(zmq.SUBSCRIBE, '')
socket.setsockopt(zmq.RCVTIMEO, 5000)
try:
    msg = socket.recv_string()
    print(msg)
except zmq.error.Again:
    print('')  # Print empty string instead of error message
    pass
")
        if [ -n "$msg" ] && [ "$msg" != "Timeout waiting for command" ]; then
            echo "Received command: $msg"
            # sleep 5 seconds
            pkill -f -9 python3.10
            sleep 5
            eval "$msg"
        fi
        sleep 1
    done
}

# Leader
lead_worker() {
    echo "Starting leader for group $GROUP_CHANNEL"
    register_worker
    trap 'echo "Leader exiting"; redis_cmd SREM "$WORKERS_SET" "$WORKER_ID"; exit 0' INT TERM
    while true; do
        echo "WAITING FOR COMMAND"
        command=$(redis_cmd --raw BLPOP "$QUEUE_NAME" 5)  # 5 second timeout
        if [[ $? -ne 0 ]]; then
            continue
        fi
        
        # Only process if we got a real command
        if [[ -n "$command" ]] && [[ "$command" != "$QUEUE_NAME" ]]; then
            echo "command: $command"
            command=$(echo "$command" | awk 'NR==2')
            
            echo "Broadcasting: $command"
            python3.10 -c "
import os
import zmq
import time
context = zmq.Context()
socket = context.socket(zmq.PUB)
socket.bind('tcp://*:5556')
cmd = '$command'
time.sleep(1)
socket.send_string(cmd)
"
            pkill -f -9 python3.10
            sleep 5
            execute_command "$command"
        fi
    done
}

# Main
main() {
    check_redis || exit 1
    
    case "$1" in
        enqueue)
            [[ $# -lt 2 ]] && {
                echo "Usage: $0 enqueue \"<command>\""
                exit 1
            }
            if ! redis_cmd RPUSH "$QUEUE_NAME" "$2"; then
                echo "Failed to enqueue command to Redis"
                exit 1
            fi
            echo "Enqueued: $2"
            ;;
        worker)
            get_node_info
            if [[ "$CURRENT_IP" == "$HEAD_NODE_ADDRESS" ]]; then
                lead_worker
            else
                follow_leader
            fi
            ;;
        length)
            redis_cmd LLEN "$QUEUE_NAME"
            ;;
        list)
            redis_cmd LRANGE "$QUEUE_NAME" 0 -1
            ;;
        workers)
            echo "Active workers: $(get_worker_count)"
            echo "Worker IDs:"
            redis_cmd SMEMBERS "$WORKERS_SET"
            ;;
        *)
            echo "Distributed Command Queue Manager"
            echo "Usage:"
            echo "  $0 enqueue \"<command>\""
            echo "  $0 worker"
            echo "  $0 length          # Show queue length"
            echo "  $0 list            # Show all queued items"
            echo "  $0 workers         # Show active workers"
            exit 1
            ;;
    esac
}

main "$@"
