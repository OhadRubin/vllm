#!/bin/bash
# Distributed Redis Queue Manager - Authenticated Version

# Configuration
REDIS_HOST="ohadrubin.com"
REDIS_PORT=31600
QUEUE_NAME="cmd_queue"
MAX_RETRIES=10
RETRY_DELAY=3

# Secure connection wrapper
redis_cmd() {
    redis-cli -u "redis://:${REDIS_PASSWORD}@${REDIS_HOST}:${REDIS_PORT}" --no-auth-warning "$@"
}

# Connection test with authentication
check_redis() {
    if ! ping_output=$(redis_cmd PING 2>&1); then
        echo "Redis connection failed. Verify:" >&2
        echo "1. Server running at ${REDIS_HOST}:${REDIS_PORT}"
        echo "2. Authentication credentials"
        echo "3. Network connectivity"
        return 1
    fi
    [[ "$ping_output" != "PONG" ]] && {
        echo "Unexpected PING response: $ping_output" >&2
        return 1
    }
    return 0
}

# Get node info with validation
get_node_info() {
    export CURRENT_IP=$(curl -s --connect-timeout 3 https://checkip.amazonaws.com || echo "127.0.0.1")
    export HEAD_NODE_ADDRESS=$(python3.10 ~/vllm/examples/leader_election.py 2>/dev/null || echo "$CURRENT_IP")
    [[ -z "$HEAD_NODE_ADDRESS" ]] && HEAD_NODE_ADDRESS="$CURRENT_IP"
    GROUP_CHANNEL="group_commands:${HEAD_NODE_ADDRESS//./_}"
}

# Rest of the functions remain the same as previous version but use redis_cmd

# Command execution with logging
execute_command() {
    local cmd="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Executing: $cmd"
    if ! eval "$cmd"; then
        echo "[ERROR] Command failed: $cmd" >&2
        return 1
    fi
}

# Dequeue with connection resilience
dequeue() {
    while true; do
        result=$(redis_cmd --raw BRPOP "$QUEUE_NAME" 0)
        [[ -n "$result" ]] && break
        sleep $RETRY_DELAY
    done
    echo "$result" | tail -n1
}

# Follower listener
follow_leader() {
    echo "Starting follower for group $GROUP_CHANNEL"
    redis_cmd SUBSCRIBE "$GROUP_CHANNEL" | {
        while read -r type; do
            read -r channel
            read -r message
            case "$type" in
                message) execute_command "$message" ;;
                subscribe) echo "Subscribed to $channel" ;;
                *) echo "Unknown message type: $type" >&2 ;;
            esac
        done
    }
}

# Leader worker
lead_worker() {
    echo "Starting leader for group $GROUP_CHANNEL"
    trap 'echo "Leader exiting gracefully"; exit 0' INT TERM
    while true; do
        command=$(dequeue)
        echo "Broadcasting: $command"
        redis_cmd PUBLISH "$GROUP_CHANNEL" "$command"
        execute_command "$command"
    done
}

# Main entry point
main() {
    # Dependency check
    if ! command -v redis-cli &>/dev/null; then
        echo "Installing redis-tools..."
        sudo apt-get update -qq && sudo apt-get install -y redis-tools || {
            echo "Failed to install redis-cli" >&2
            exit 1
        }
    fi

    # Validate connection
    check_redis || exit 1

    # Get node info
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