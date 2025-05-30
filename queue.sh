#!/bin/bash
# ./queue.sh enqueue 'echo hi'
# ./queue.sh worker
# ./queue.sh list
# ./queue.sh purge [num_workers]
# ./queue.sh reset_barriers [barrier_name]
# Configuration

WORKERS_SET="active_workers"
MAX_RETRIES=10
RETRY_DELAY=3




get_redis_url() {
    echo "redis://:$REDIS_PASSWORD@34.34.31.118:6379"
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

# Purge queue
purge_queue() {
    local queue_name="${1:-default}"
    redis_cmd DEL "queue:$queue_name"
    echo "Purged queue: $queue_name"
}
    


# Node info
get_node_info() {
    export CURRENT_IP=$(hostname -I | awk '{print $1}')
    echo "Current IP: $CURRENT_IP"
    
    # export HEAD_NODE_ADDRESS=$(python3.10 ~/vllm/examples/leader_election.py 2>/dev/null || echo "$CURRENT_IP")
    HOSTNAME=$(hostname)
    export HEAD_NODE_ADDRESS=$(gcloud alpha compute tpus tpu-vm describe $HOSTNAME --zone us-central2-b --format json | jq -r '.networkEndpoints[].ipAddress' | sort | head -1)
    
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



barrier_sync() {
    local barrier_name="$1"
    local worker_count="$2"

    local arrive_key="${barrier_name}:arrive"
    local depart_key="${barrier_name}:depart"

    # Each arrival increments a global counter
    local arrive_count
    arrive_count="$(redis_cmd INCR "$arrive_key")"

    # Determine which round (0-based) this arrival belongs to
    # If arrive_count=1..N, that indicates round=0 for the first N arrivals, etc.
    local round=$(( (arrive_count - 1) / worker_count ))
    # The arrival threshold for this round
    local arrive_target=$(( (round + 1) * worker_count ))

    # Poll until the arrive counter reaches the target
    
    while :; do
        local current_arrive
        current_arrive="$(redis_cmd GET "$arrive_key")"
        [ -z "$current_arrive" ] || [ "$current_arrive" = "(nil)" ] && current_arrive=0

        if [ "$current_arrive" -ge "$arrive_target" ]; then
            break
        fi
        echo "Waiting for everyone to arrive at round $round, current arrive: $current_arrive, arrive_target: $arrive_target"
        sleep 5
    done

    # Increment global departure counter
    local depart_count
    depart_count="$(redis_cmd INCR "$depart_key")"

    # Poll until the departure counter reaches the same threshold
    local depart_target=$(( (round + 1) * worker_count ))
    while :; do
        local current_depart
        current_depart="$(redis_cmd GET "$depart_key")"
        [ -z "$current_depart" ] || [ "$current_depart" = "(nil)" ] && current_depart=0

        if [ "$current_depart" -ge "$depart_target" ]; then
            break
        fi
        echo "Waiting for everyone to depart at round $round, current depart: $current_depart, depart_target: $depart_target"
        sleep 5
    done
    echo "Everyone has departed at round $round"
}




wait_until_everyone_ready() {
    local num_workers="$1"
    barrier_sync "barrier_data:$HOSTNAME" $num_workers

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
            sleep 10
            wipe_tpu
            eval "$msg"
            wipe_tpu
            wait_until_everyone_ready $NUM_WORKERS
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
        wipe_tpu
        wait_until_everyone_ready $NUM_WORKERS
        reset_leader_data
        cmd_counter=$((cmd_counter + 1))
    done
}

# List all jobs in the queue
list_jobs() {
    local pattern="queue:cmd_queue_*"
    local queues=$(redis_cmd KEYS "$pattern")
    
    if [[ -z "$queues" ]]; then
        echo "No active queues found"
        return
    fi
    
    echo "Current jobs in queues:"
    echo "----------------------"
    
    for queue in $queues; do
        local queue_name=${queue#queue:}
        local num_workers=${queue_name#cmd_queue_}
        local job_count=$(redis_cmd LLEN "$queue")
        
        echo "Queue: $queue_name ($job_count jobs, $num_workers workers)"
        
        if [[ "$job_count" -gt 0 ]]; then
            local job_ids=$(redis_cmd LRANGE "$queue" 0 -1)
            for job_id in $job_ids; do
                local job_data=$(redis_cmd HGETALL "job:$job_id")
                local command=$(echo "$job_data" | grep -A1 "data" | tail -1)
                local status=$(echo "$job_data" | grep -A1 "status" | tail -1)
                local created_at=$(echo "$job_data" | grep -A1 "created_at" | tail -1)
                
                echo "  Job: $job_id"
                echo "    Command: $command"
                echo "    Status: $status"
                echo "    Created: $created_at"
            done
        fi
        echo ""
    done
}

# Reset barrier counters to resolve deadlocks
reset_barriers() {
    # Delete all barrier arrive/depart counters
    local arrive_keys=$(redis_cmd KEYS "*:arrive")
    local depart_keys=$(redis_cmd KEYS "*:depart")
    
    echo "Found $(echo "$arrive_keys" | wc -w) arrive barriers and $(echo "$depart_keys" | wc -w) depart barriers"
    
    for key in $arrive_keys; do
        redis_cmd DEL "$key"
        echo "Reset barrier: $key"
    done
    
    for key in $depart_keys; do
        redis_cmd DEL "$key"
        echo "Reset barrier: $key"
    done
    
    # Reset all leader data
    local leader_keys=$(redis_cmd KEYS "leader_data:*")
    for key in $leader_keys; do
        redis_cmd DEL "$key"
        echo "Reset leader data: $key"
    done
    
    echo "All barriers have been reset"
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
        list)
            list_jobs
            ;;
        purge)
            NUM_WORKERS=${2:-2}
            QUEUE_NAME="cmd_queue_${NUM_WORKERS}"
            purge_queue "$QUEUE_NAME"
            ;;
        reset_barriers)
            barrier_name="${2:-barrier_data:$HOSTNAME}"
            reset_barriers "$barrier_name"
            ;;
        *)
            echo "Distributed Command Queue Manager"
            echo "Usage:"
            echo "  $0 enqueue [num_workers] \"<command>\""
            echo "  $0 worker"
            echo "  $0 list"
            echo "  $0 purge [num_workers]"
            echo "  $0 reset_barriers [barrier_name]"
            exit 1
            ;;
    esac
}

main "$@"