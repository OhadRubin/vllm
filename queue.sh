#!/bin/bash
# Distributed Redis Queue Manager with Group Execution

# Configuration
REDIS_HOST="ohadrubin.com"
REDIS_PORT=31600
QUEUE_NAME="cmd_queue"
REDISCLI_AUTH=${REDIS_PASSWORD:-""}  # Set via environment variable
MAX_CONN_RETRIES=5
CONN_RETRY_DELAY=2


# Secure Redis connection wrapper
redis_connect() {
    local args=(-h "$REDIS_HOST" -p "$REDIS_PORT")
    [ -n "$REDISCLI_AUTH" ] && args+=(--no-auth-warning)
    redis-cli "${args[@]}" "$@"
}

# Check Redis connection with retries
check_redis_connection() {
    local retries=0
    while [ $retries -lt $MAX_CONN_RETRIES ]; do
        if redis_connect PING | grep -q "PONG"; then
            return 0
        fi
        echo "Connection attempt $((retries+1))/$MAX_CONN_RETRIES failed"
        sleep $CONN_RETRY_DELAY
        ((retries++))
    done
    echo "ERROR: Could not connect to Redis at $REDIS_HOST:$REDIS_PORT" >&2
    return 1
}

# Install dependencies safely
install_deps() {
    if ! command -v redis-cli &> /dev/null; then
        echo "Installing redis-tools..."
        sudo apt-get update -qq && sudo apt-get install -y redis-tools || {
            echo "Failed to install redis-tools" >&2
            return 1
        }
    fi
}

# Get node information with fallbacks
get_node_info() {
    export CURRENT_IP="$(curl -s --max-time 3 https://checkip.amazonaws.com || echo '127.0.0.1')"
    export HEAD_NODE_ADDRESS="$({
        python3.10 ~/vllm/examples/leader_election.py 2>/dev/null \
        || echo "$CURRENT_IP"
    })"
    GROUP_CHANNEL="group_commands:${HEAD_NODE_ADDRESS}"
}

# Command execution with error handling
execute_command() {
    local cmd="$1"
    echo "[$(date '+%T')] Executing: $cmd"
    if ! eval "$cmd"; then
        echo "[ERROR] Failed to execute: $cmd" >&2
        return 1
    fi
}

# Dequeue with connection resilience
dequeue() {
    while true; do
        result=$(redis_connect --raw BRPOP "$QUEUE_NAME" 0 2>/dev/null)
        [ -n "$result" ] && break
        echo "Reconnecting to Redis..."
        sleep $CONN_RETRY_DELAY
    done
    echo "$result" | tail -n 1
}

# Follower command listener
follow_leader() {
    echo "Starting as follower in group $HEAD_NODE_ADDRESS"
    redis_connect --raw SUBSCRIBE "$GROUP_CHANNEL" | {
        while read -r line; do
            case "$line" in
                "message")
                    read -r channel
                    read -r command
                    execute_command "$command"
                    ;;
                "subscribe")
                    read -r channel
                    read -r count
                    echo "Subscribed to $GROUP_CHANNEL"
                    ;;
            esac
        done
    }
}

# Leader worker process
lead_worker() {
    echo "Starting as leader for group $HEAD_NODE_ADDRESS"
    trap 'echo "Leader shutting down"; exit 0' INT TERM
    while true; do
        command=$(dequeue)
        echo "Broadcasting: $command"
        redis_connect PUBLISH "$GROUP_CHANNEL" "$command" >/dev/null
        execute_command "$command"
    done
}

# Main worker function
start_worker() {
    if [ "$CURRENT_IP" = "$HEAD_NODE_ADDRESS" ]; then
        lead_worker
    else
        follow_leader
    fi
}

# Script entry point
main() {
    install_deps || exit 1
    check_redis_connection || exit 1
    get_node_info

    case "$1" in
        enqueue)
            [ $# -lt 2 ] && {
                echo "Usage: $0 enqueue \"<command>\""
                exit 1
            }
            redis_connect LPUSH "$QUEUE_NAME" "$2" >/dev/null
            echo "Enqueued: $2"
            ;;
        worker)
            start_worker
            ;;
        *)
            echo "Distributed Queue Manager"
            echo "Usage:"
            echo "  $0 enqueue \"<command>\""
            echo "  $0 worker"
            exit 1
            ;;
    esac
}

main "$@"