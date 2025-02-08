#!/bin/bash
# ./queue.sh enqueue 'echo hi'
# ./queue.sh worker
# ./queue.sh list
# Configuration

WORKERS_SET="active_workers"
MAX_RETRIES=10
RETRY_DELAY=3




get_redis_url() {
    echo "redis://:$REDIS_PASSWORD@35.204.103.77:6379"
}

export REDIS_URL=$(get_redis_url)
redis_cmd() {
    redis-cli -u "$REDIS_URL" --no-auth-warning "$@"
}

wipe_tpu() {
    sudo kill -9 $(sudo lsof -w /dev/accel0 | awk 'NR>1{print $2}' |uniq)
    sudo kill -9 $(sudo lsof -w /dev/accel1 | awk 'NR>1{print $2}' |uniq)
    sudo kill -9 $(sudo lsof -w /dev/accel2 | awk 'NR>1{print $2}' |uniq)
    sudo kill -9 $(sudo lsof -w /dev/accel3 | awk 'NR>1{print $2}' |uniq)
}


# sync_tpu() {
#     sleep 10
#     wipe_tpu
#     python3.10 -c "import jax; from jax.experimental.multihost_utils import sync_global_devices; sync_global_devices('bla'); print(jax.process_index())"
#     wipe_tpu
#     sleep 10
# }


# Install dependencies if missing
# while ! command -v redis-cli &>/dev/null; do
#     echo "Installing redis-tools"
#     sudo apt-get update -qq
    
#     if ! sudo apt-get install -y redis-tools; then
#         # Kill any existing apt/dpkg processes
#         sudo pkill -f apt-get
#         sudo pkill -f dpkg 
#         sudo pkill -f apt
        
#         # Remove lock files
#         sudo rm -f /var/lib/apt/lists/lock
#         sudo rm -f /var/cache/apt/archives/lock
#         sudo rm -f /var/lib/dpkg/lock
#         sudo rm -f /var/lib/dpkg/lock-frontend
        
#         sleep 5
#         sudo dpkg --configure -a
#     fi
    
#     sleep 5
# done

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
    


# Node info
get_node_info() {
    export CURRENT_IP=$(curl -s --max-time 3 https://checkip.amazonaws.com || echo "127.0.0.1")
    echo "Current IP: $CURRENT_IP"
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


# wait_until_everyone_ready() {
#     local num_workers="$1"
#     # Atomically decrement the counter and then wait until it reaches 0
#     local current_counter
#     current_counter=$(redis_cmd HINCRBY "leader_data:$HOSTNAME" "worker_counter" -1)
#     while [[ "$current_counter" -gt 0 ]]; do
#         sleep 5
#         current_counter=$(redis_cmd HGET "leader_data:$HOSTNAME" "worker_counter")
#     done
# }


wait_until_everyone_ready() {
    local num_workers="$1"
    redis_cmd HSET "leader_data:$HOSTNAME" "not_seen_by" $num_workers
    n_are_done=$(redis_cmd HINCRBY "leader_data:$HOSTNAME" "n_are_done" 1)
    while [[ "$n_are_done" -lt "$num_workers" ]]; do
        sleep 5
        echo "Waiting for everyone to be done"
        n_are_done=$(redis_cmd HGET "leader_data:$HOSTNAME" "n_are_done")
    done
    not_seen_by=$(redis_cmd HINCRBY "leader_data:$HOSTNAME" "not_seen_by" -1)
    while [[ "$not_seen_by" -ne 0 ]]; do
        sleep 5
        echo "Waiting for everyone to be seen"
        not_seen_by=$(redis_cmd HGET "leader_data:$HOSTNAME" "not_seen_by")
    done
    redis_cmd HSET "leader_data:$HOSTNAME" "n_are_done" 0

}

set_leader_data() {
    local cmd="$1"
    local cmd_counter="$2"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Set command, timestamp, leader, and initialize the counter to the number of workers
    redis_cmd HSET "leader_data:$HOSTNAME" \
        "command" "$cmd" \
        "timestamp" "$timestamp" \
        "leader" "$HOSTNAME" \
        "cmd_counter" "$cmd_counter" \
        "seen_by" 0 \
        "n_are_done" 0
}

read_leader_data() {
    local cmd_counter="$1"
    local cmd
    cmd=$(redis_cmd HGET "leader_data:$HOSTNAME" "command")
    local timestamp
    timestamp=$(redis_cmd HGET "leader_data:$HOSTNAME" "timestamp")

    if [[ -n "$cmd" && -n "$timestamp" ]]; then
        echo "$cmd"
    else
        echo ""
    fi
}

reset_leader_data() {
    redis_cmd DEL "leader_data:$HOSTNAME"
    # redis_cmd HSET "leader_data:$HOSTNAME" "worker_counter" 0
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
    reset_leader_data
    echo "Starting follower for group $GROUP_CHANNEL"
    local cmd_counter=0
    NUM_WORKERS=$(num_workers)
    wait_until_everyone_ready $NUM_WORKERS
    while true; do
        sleep 10
        echo "WAITING FOR COMMAND"
        msg=$(read_leader_data $cmd_counter)
        if [ -n "$msg" ] && [ "$msg" != "Timeout waiting for command" ]; then
            echo "Received command #$cmd_counter: $msg"
            wait_until_everyone_ready $NUM_WORKERS
            # sync_tpu
            sleep 10
            wipe_tpu
            eval "$msg"
            reset_leader_data
            cmd_counter=$((cmd_counter + 1))
        fi
    done
}

num_workers() {
    HOSTNAME=$(hostname)
    NODE_NUMBER=$(echo "$HOSTNAME" | grep -oP 'v4-\K\d+(?=-node)' || echo "0")
    NUM_WORKERS=$((NODE_NUMBER/8))
    echo $NUM_WORKERS
}
# Leader
lead_worker() {
    reset_leader_data
    NUM_WORKERS=$(num_workers)

    QUEUE_NAME="cmd_queue_${NUM_WORKERS}"
    echo "Starting leader for group $GROUP_CHANNEL in queue $QUEUE_NAME"
    register_worker
    trap 'echo "Leader exiting"; redis_cmd SREM "$WORKERS_SET" "$HOSTNAME"; exit 0' INT TERM
    local cmd_counter=0


    wait_until_everyone_ready $NUM_WORKERS

    while true; do
        echo "Waiting for next job"
        local job_id
        job_id=$(redis_cmd LPOP "queue:$QUEUE_NAME")
        if [[ -z "$job_id" ]]; then
            sleep 20
            continue
        fi

        local data=$(redis_cmd HGET "job:$job_id" "data")

        echo "Broadcasting job #$cmd_counter ($job_id) with command: $data"
        set_leader_data "$data" "$cmd_counter"
        wait_until_everyone_ready $NUM_WORKERS
        # sync_tpu
        sleep 10
        wipe_tpu
        update_job_status "$job_id" "processing" "N/A"
        if execute_command "$data"; then
            finalize_job "$job_id"
        else
            update_job_status "$job_id" "failed" "command error"
        fi
        reset_leader_data
        cmd_counter=$((cmd_counter + 1))
    done
}

# Main
main() {
    case "$1" in
        enqueue)
            redis_cmd PING
            DEFAULT_NUM_WORKERS=2
            [[ $# -lt 2 ]] && {
                echo "Usage: $0 enqueue [num_workers] \"<command>\""
                exit 1
            }
            if [[ $# -eq 3 ]]; then
                NUM_WORKERS=$2
                command=$3
            else
                NUM_WORKERS=$DEFAULT_NUM_WORKERS
                command=$2
            fi
            QUEUE_NAME="cmd_queue_${NUM_WORKERS}"
            enqueue_job "$command" "$QUEUE_NAME" >/dev/null
            echo "Enqueued: $command"
            ;;
        worker)
            # python3.10 -c "import jax; from jax.experimental.multihost_utils import sync_global_devices; sync_global_devices('bla'); print(jax.process_index())"
            get_node_info
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