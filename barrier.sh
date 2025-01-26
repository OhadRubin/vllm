#!/usr/bin/env bash
# barrier.sh - Simplified Redis Barrier
# Usage:
#   Follower: ./barrier.sh start <MY_IP> <LEADER_IP>
#   Leader:   ./barrier.sh finish <LEADER_IP>
KEY_EXPIRE=300  # 5 minutes

HOSTNAME=$(hostname)
NODE_NUMBER=$(echo "$HOSTNAME" | grep -oP 'v4-\K\d+(?=-node)' || echo "0")
NUM_WORKERS=$((NODE_NUMBER/8))
NUM_FOLLOWERS=$((NUM_WORKERS-1))
get_redis_url() {
    echo "redis://:$REDIS_PASSWORD@35.204.103.77:6379"
}

export REDIS_URL=$(get_redis_url)
redis_cmd() {
    redis-cli -u "$REDIS_URL" --no-auth-warning "$@"
}

wait_for_everyone(){
    leader_ip=$1
    while :; do
        should_exit=$(redis_cmd GET "barrier:done:$leader_ip")
        if [[ -z "$should_exit" ]]; then
            break
        fi
        sleep 5
    done
    echo "[$(date +%T)] ✅ All followers ready, proceeding."
}

finish() {
    local leader_ip="$1"
    echo "👑 Leader $leader_ip finishing"
    redis_cmd SET "barrier:done:$leader_ip" 1 EX $KEY_EXPIRE
    redis_cmd SET "barrier:counter:$leader_ip" "$NUM_FOLLOWERS" EX $KEY_EXPIRE
    # Leader waits for barrier completion
    wait_for_everyone "$leader_ip"
    
}

barrier_wait() {
    local leader_ip="$1"
    echo "[$(date +%T)] ⏳ Waiting for leader $leader_ip"
    while :; do
        if redis_cmd EXISTS "barrier:done:$leader_ip" | grep -q 1; then
            break
        fi
        sleep 10
        echo "[$(date +%T)] ⏳ Waiting for leader $leader_ip"
    done
    redis_cmd DECR "barrier:counter:$leader_ip"
    
    # Last follower cleans up when counter hits 0
    if [[ "$(redis_cmd GET "barrier:counter:$leader_ip")" == "0" ]]; then
        redis_cmd DEL "barrier:counter:$leader_ip" "barrier:done:$leader_ip"
        echo "🧹 Cleaned up barrier counter"
    fi
    wait_for_everyone "$leader_ip"



}

start() {
    local my_ip="$1"
    local leader_ip="$2"

    if [[ "$my_ip" != "$leader_ip" ]]; then
        echo "🧑💻 Follower $my_ip starting"
        barrier_wait "$leader_ip"
        echo "follower $my_ip finished"
    else
        echo "leader $my_ip does other stuff now"
        # Leader does not wait here, it can call 'finish' later
    fi
}



case "$1" in
    start)
        [[ $# -lt 3 ]] && { echo "Usage: $0 start <MY_IP> <LEADER_IP>"; exit 1; }
        start "$2" "$3"
        ;;
    finish)
        [[ $# -lt 2 ]] && { echo "Usage: $0 finish <LEADER_IP>"; exit 1; }
        finish "$2"
        ;;
    *)
        echo "Redis Barrier System"
        echo "Usage:"
        echo "  Follower: $0 start <YOUR_IP> <LEADER_IP>"
        echo "  Leader:   $0 finish <LEADER_IP>"
        exit 1
        ;;
esac