#!/bin/bash

# Configuration
REDIS_HOST="ohadrubin.com"
REDIS_PORT=31600
QUEUE_NAME="cmd_queue"
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
    echo "Group Channel: $GROUP_CHANNEL"
}

# Command execution
execute_command() {
    local cmd="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Executing: $cmd"
    if ! eval "$cmd"; then
        echo "[ERROR] Command error: $cmd" >&2
        return 1
    fi
}

# Dequeue with backoff
dequeue() {
    while true; do
        result=$(redis_cmd --raw BRPOP "$QUEUE_NAME" 0)
        [[ -n "$result" ]] && break
        sleep $RETRY_DELAY
    done
    echo "$result" | tail -n1
}

# Follower
follow_leader() {
    echo "Starting follower for group $GROUP_CHANNEL"
    echo "Checking channel subscription"
    if [[ ! "$GROUP_CHANNEL" =~ ^group_commands:[0-9_]+$ ]]; then
        echo "Group channel format error: $GROUP_CHANNEL" >&2
        return 1
    fi

    # Subscription test
    local test_channel="test_$RANDOM"
    (
        sleep 1
        redis_cmd PUBLISH "$test_channel" "test_message" >/dev/null
    ) &

    redis_cmd SUBSCRIBE "$test_channel" | {
        while read -r type; do
            read -r channel
            read -r message
            if [[ "$message" == "test_message" ]]; then
                echo "Channel test passed"
                break
            fi
        done
    }

    echo "Subscribing to $GROUP_CHANNEL"
    redis_cmd SUBSCRIBE "$GROUP_CHANNEL" | {
        while true; do
            read -r type || break
            read -r channel || break
            read -r message || break
            echo "Received [$type] on [$channel]: $message"
            case "$type" in
                message)
                    echo "Executing: $message"
                    eval "$message"
                    ;;
                subscribe)
                    echo "Subscribed to $channel"
                    ;;
                *)
                    echo "Unknown message type: $type"
                    ;;
            esac
        done
    }
    
    echo "Subscription lost. Reconnecting..."
    sleep $RETRY_DELAY
    follow_leader
}

# Leader
lead_worker() {
    echo "Starting leader for group $GROUP_CHANNEL"
    trap 'echo "Leader exiting"; exit 0' INT TERM
    while true; do
        command=$(dequeue)
        echo "Broadcasting: $command"
        redis_cmd PUBLISH "$GROUP_CHANNEL" "$command"
        execute_command "$command"
    done
}

# Main
main() {
    check_redis || exit 1
    get_node_info
    
    case "$1" in
        enqueue)
            [[ $# -lt 2 ]] && {
                echo "Usage: $0 enqueue \"<command>\""
                exit 1
            }
            redis_cmd LPUSH "$QUEUE_NAME" "$2" || exit 1
            echo "Enqueued: $2"
            ;;
        worker)
            if [[ "$CURRENT_IP" == "$HEAD_NODE_ADDRESS" ]]; then
                lead_worker
            else
                follow_leader
            fi
            ;;
        *)
            echo "Distributed Command Queue Manager"
            echo "Usage:"
            echo "  $0 enqueue \"<command>\""
            echo "  $0 worker"
            exit 1
            ;;
    esac
}

main "$@"
