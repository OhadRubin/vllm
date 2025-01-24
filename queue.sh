#!/bin/bash
# ./queue.sh enqueue 'echo hi'
# ./queue.sh worker
# ./queue.sh list
# Configuration
REDIS_PORT=38979
QUEUE_NAME="cmd_queue"
WORKERS_SET="active_workers"
MAX_RETRIES=10
RETRY_DELAY=3

# Install dependencies if missing
while ! command -v redis-cli &>/dev/null; do
    echo "Installing redis-tools"
    sudo apt-get update -qq
    
    if ! sudo apt-get install -y redis-tools; then
        # Kill any existing apt/dpkg processes
        sudo pkill -f apt-get
        sudo pkill -f dpkg 
        sudo pkill -f apt
        
        # Remove lock files
        sudo rm -f /var/lib/apt/lists/lock
        sudo rm -f /var/cache/apt/archives/lock
        sudo rm -f /var/lib/dpkg/lock
        sudo rm -f /var/lib/dpkg/lock-frontend
        
        sleep 5
        sudo dpkg --configure -a
    fi
    
    sleep 5
done

# Bookkeeping functions
update_job_status() {
    local job_id="$1"
    local status="$2"
    local result="$3"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    redis_cmd HSET "job:$job_id" \
        "status" "$status" \
        "result" "$result" \
        "updated_at" "$timestamp" \
        "worker" "$HOSTNAME"
}

finalize_job() {
    local job_id="$1"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    redis_cmd HSET "job:$job_id" \
        "status" "completed" \
        "completed_at" "$timestamp" \
        "worker" "$HOSTNAME"
}

set_heartbeat() {
    local job_id="$1"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    redis_cmd HSET "job:$job_id" \
        "last_heartbeat" "$timestamp" \
        "worker" "$HOSTNAME"
}


# Add job to queue
enqueue_job() {
    local data="$1"
    local queue_name="${2:-default}"
    local job_id
    job_id=$(uuidgen)
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    redis_cmd HSET "job:$job_id" \
        "id" "$job_id" \
        "data" "$data" \
        "status" "queued" \
        "created_at" "$timestamp" \
        "queue" "$queue_name"

    redis_cmd RPUSH "queue:$queue_name" "$job_id"
    echo "$job_id"
}
    
# Check if queue is empty
is_queue_empty() {
    local queue_name="${1:-default}"
    local len
    len=$(redis_cmd LLEN "queue:$queue_name")
    [[ "$len" -eq 0 ]]
}
    
get_redis_url() {
    echo "redis://:$REDIS_PASSWORD@35.204.103.77:6379"
}

export REDIS_URL=$(get_redis_url)
redis_cmd() {
    redis-cli -u "$REDIS_URL" --no-auth-warning "$@"
}

# Node info
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
    redis_cmd SADD "$WORKERS_SET" "$HOSTNAME"
    trap 'redis_cmd SREM "$WORKERS_SET" "$HOSTNAME"; exit 0' INT TERM EXIT
}

# Get worker count
get_worker_count() {
    redis_cmd SCARD "$WORKERS_SET"
}

# BEGIN FIX
# BEGIN FIX
wait_until_everyone_ready() {
    # Atomically decrement the counter and then wait until it reaches 0
    local current_counter
    current_counter=$(redis_cmd HINCRBY "leader_data" "counter" -1)
    while [[ "$current_counter" -gt 0 ]]; do
        sleep 1
        current_counter=$(redis_cmd HGET "leader_data" "counter")
    done
}

set_leader_data() {
    local cmd="$1"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Set command, timestamp, leader, and initialize the counter to the number of workers
    redis_cmd HSET "leader_data" \
        "command" "$cmd" \
        "timestamp" "$timestamp" \
        "leader" "$HOSTNAME" \
        "counter" "2"
}

read_leader_data() {
    local cmd
    cmd=$(redis_cmd HGET "leader_data" "command")
    local timestamp
    timestamp=$(redis_cmd HGET "leader_data" "timestamp")

    if [[ -n "$cmd" && -n "$timestamp" ]]; then
        echo "$cmd"
    else
        echo ""
    fi
}

reset_leader_data() {
    redis_cmd DEL "leader_data"
    redis_cmd HSET "leader_data" "counter" 0
}
# END FIX


# END FIX

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

wipe_tpu() {
    sudo kill -9 $(sudo lsof -w /dev/accel0 | awk 'NR>1{print $2}' |uniq)
    sudo kill -9 $(sudo lsof -w /dev/accel1 | awk 'NR>1{print $2}' |uniq)
    sudo kill -9 $(sudo lsof -w /dev/accel2 | awk 'NR>1{print $2}' |uniq)
    sudo kill -9 $(sudo lsof -w /dev/accel3 | awk 'NR>1{print $2}' |uniq)
}


sync_tpu() {
    sleep 10
    wipe_tpu
    python3.10 -c "import jax; from jax.experimental.multihost_utils import sync_global_devices; sync_global_devices('bla'); print(jax.process_index())"
    wipe_tpu
    sleep 10
}


# Follower
follow_leader() {
    echo "Starting follower for group $GROUP_CHANNEL"
    while true; do
        sleep 10
        echo "WAITING FOR COMMAND"
        msg=$(read_leader_data)
        if [ -n "$msg" ] && [ "$msg" != "Timeout waiting for command" ]; then
            echo "Received command: $msg"
            wait_until_everyone_ready
            sync_tpu
            eval "$msg"
            reset_leader_data
        fi
    done
}

# Leader
lead_worker() {
    echo "Starting leader for group $GROUP_CHANNEL"
    register_worker
    trap 'echo "Leader exiting"; redis_cmd SREM "$WORKERS_SET" "$HOSTNAME"; exit 0' INT TERM
    while true; do
        echo "Waiting for next job"
        local job_id
        job_id=$(redis_cmd LPOP "queue:$QUEUE_NAME")
        if [[ -z "$job_id" ]]; then
            sleep 10
            continue
        fi

        local data=$(redis_cmd HGET "job:$job_id" "data")

        echo "Broadcasting job $job_id with command: $data"
        set_leader_data "$data"
        wait_until_everyone_ready
        sync_tpu
        update_job_status "$job_id" "processing" "N/A"
        if execute_command "$data"; then
            finalize_job "$job_id"
        else
            update_job_status "$job_id" "failed" "command error"
        fi
        reset_leader_data
    done
}

# Main
main() {
    case "$1" in
        enqueue)
            redis_cmd PING
            [[ $# -lt 2 ]] && {
                echo "Usage: $0 enqueue \"<command>\""
                exit 1
            }
            enqueue_job "$2" "$QUEUE_NAME" >/dev/null
            echo "Enqueued: $2"
            ;;
        worker)
            python3.10 -c "import jax; from jax.experimental.multihost_utils import sync_global_devices; sync_global_devices('bla'); print(jax.process_index())"
            get_node_info
            if [[ "$CURRENT_IP" == "$HEAD_NODE_ADDRESS" ]]; then
                lead_worker
            else
                follow_leader
            fi
            ;;
        length)
            redis_cmd LLEN "queue:$QUEUE_NAME"
            ;;
        list)
            redis_cmd PING
            redis_cmd LRANGE "queue:$QUEUE_NAME" 0 -1
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