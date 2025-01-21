#!/bin/bash

# Redis Configuration
REDIS_HOST="redis.ohadrubin.com"
REDIS_PORT=6379
QUEUE_NAME="cmd_queue"

# Build Redis connection arguments
redis_args=(-h "$REDIS_HOST" -p "$REDIS_PORT")
[ -n "$REDIS_PASSWORD" ] && redis_args+=(-a "$REDIS_PASSWORD")

# Install dependencies if missing
if ! command -v redis-cli &> /dev/null; then
    sudo apt-get install -y redis-tools
fi

# Get node information
export HEAD_NODE_ADDRESS="$(python3.10 ~/vllm/examples/leader_election.py 2>/dev/null || echo '127.0.0.1')"
export CURRENT_IP="$(curl -s https://checkip.amazonaws.com)"

# Channel name based on leader's group
GROUP_CHANNEL="group_commands:${HEAD_NODE_ADDRESS}"

# Dequeue function
dequeue() {
    local result
    result=$(redis-cli "${redis_args[@]}" --raw BRPOP "$QUEUE_NAME" 0 2>/dev/null)
    echo "$result" | tail -n 1
}

# Command executor with error handling
execute_command() {
    local cmd="$1"
    echo "Executing: $cmd"
    if ! eval "$cmd"; then
        echo "Error executing command: $cmd" >&2
    fi
}

# Follower subscription handler
follow_leader() {
    echo "Worker on follower node. Waiting for commands from leader..."
    redis-cli "${redis_args[@]}" --raw SUBSCRIBE "$GROUP_CHANNEL" | {
        while true; do
            read -r line
            # Pub/Sub message format: message\nchannel\ncontent
            if [[ "$line" == "message" ]]; then
                read -r channel  # Read channel name line
                read -r command  # Read actual command
                execute_command "$command"
            fi
        done
    }
}

# Leader worker function
lead_worker() {
    echo "Worker started as leader. Ctrl+C to exit."
    trap 'echo "Leader stopped"; exit' INT
    while true; do
        command=$(dequeue)
        # Broadcast to followers and execute locally
        redis-cli "${redis_args[@]}" PUBLISH "$GROUP_CHANNEL" "$command" >/dev/null
        execute_command "$command"
    done
}

# Main worker function
worker() {
    if [ "$CURRENT_IP" = "$HEAD_NODE_ADDRESS" ]; then
        lead_worker
    else
        follow_leader
    fi
}

usage() {
    echo "Distributed Redis Queue Manager"
    echo "Usage:"
    echo "  Enqueue: $0 enqueue \"<command>\""
    echo "  Start worker: $0 worker"
    exit 1
}

# Argument handling
case "$1" in
    enqueue)
        [ $# -lt 2 ] && { echo "Missing command"; usage; }
        redis-cli "${redis_args[@]}" LPUSH "$QUEUE_NAME" "$2" >/dev/null
        echo "Enqueued: $2"
        ;;
    worker)
        worker
        ;;
    *)
        usage
        ;;
esac