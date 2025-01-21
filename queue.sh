#!/bin/bash

# Distributed Redis Queue Manager - Follower/Leader Communication Test

# Configuration
REDIS_HOST="ohadrubin.com"
REDIS_PORT=31600
QUEUE_NAME="cmd_queue"
RETRY_DELAY=3

# Secure connection wrapper
redis_cmd() {
    redis-cli -u "redis://:${REDIS_PASSWORD}@${REDIS_HOST}:${REDIS_PORT}" --no-auth-warning "$@"
}

# Connection test with Pub/Sub verification
check_redis() {
    if ! ping_output=$(redis_cmd PING 2>&1); then
        echo "Redis connection failed. Verify:" >&2
        echo "1. Server running at ${REDIS_HOST}:${REDIS_PORT}"
        echo "2. Authentication credentials"
        echo "3. Network connectivity"
        return 1
    fi
    
    # Verify Pub/Sub capabilities
    local test_channel="connection_test_$RANDOM"
    if ! redis_cmd PUBLISH "$test_channel" "test" >/dev/null; then
        echo "Redis Pub/Sub test failed. Check server configuration."
        return 1
    fi
    return 0
}

get_node_info() {
    export CURRENT_IP=$(curl -s --max-time 3 https://checkip.amazonaws.com || echo "127.0.0.1")
    export HEAD_NODE_ADDRESS=$(python3.10 ~/vllm/examples/leader_election.py 2>/dev/null || echo "$CURRENT_IP")
    
    # Validate IP format
    if [[ ! "$HEAD_NODE_ADDRESS" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        HEAD_NODE_ADDRESS="$CURRENT_IP"
    fi
    
    GROUP_CHANNEL="group_commands:${HEAD_NODE_ADDRESS//./_}"
    echo "Group Channel: $GROUP_CHANNEL"
}

# Follower subscription handler
follow_leader() {
    echo "Starting follower for group $GROUP_CHANNEL"
    while true; do
        echo "Initiating subscription to $GROUP_CHANNEL"
        redis_cmd SUBSCRIBE "$GROUP_CHANNEL" | {
            while read -r type; do
                read -r channel
                read -r message
                case "$type" in
                    message)
                        echo "Leader command received: $message"
                        eval "$message"
                        ;;
                    subscribe)
                        echo "Successfully subscribed to $channel"
                        ;;
                    *) 
                        echo "Received $type message"
                        ;;
                esac
            done
        }
        echo "Connection lost. Retrying in $RETRY_DELAY seconds..."
        sleep $RETRY_DELAY
    done
}

# Leader command broadcaster
lead_worker() {
    echo "Starting leader for group $GROUP_CHANNEL"
    trap 'echo "Leader exiting"; exit 0' INT TERM
    while true; do
        command=$(redis_cmd BRPOP "$QUEUE_NAME" 0 | tail -n1)
        echo "Broadcasting command: $command"
        redis_cmd PUBLISH "$GROUP_CHANNEL" "$command"
    done
}

# Main execution flow
main() {
    # Dependency check
    if ! command -v redis-cli &>/dev/null; then
        echo "ERROR: redis-cli required - install with: sudo apt-get install redis-tools" >&2
        exit 1
    fi

    check_redis || exit 1
    get_node_info

    case "$1" in
        enqueue)
            [[ $# -lt 2 ]] && {
                echo "Usage: $0 enqueue \"<command>\""
                exit 1
            }
            redis_cmd LPUSH "$QUEUE_NAME" "$2" || exit 1
            echo "Command enqueued: $2"
            ;;
        worker)
            if [[ "$CURRENT_IP" == "$HEAD_NODE_ADDRESS" ]]; then
                lead_worker
            else
                follow_leader
            fi
            ;;
        *)
            echo "Usage:"
            echo "  $0 enqueue \"<command>\"  # Leader will broadcast commands from queue"
            echo "  $0 worker                # Start as leader/follower based on election"
            exit 1
            ;;
    esac
}

main "$@"