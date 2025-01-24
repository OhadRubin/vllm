
# this creates the server and listens to relay_session
(cd ~/vllm && git pull)

cleanup() {
    pkill -f -9 wspipe
    tmux pipe-pane -t relay_session
}
trap cleanup EXIT INT TERM

python3.10 /home/ohadr/vllm/wspipe.py server  &
tmux pipe-pane -t relay_session -oIO 'cat | python3.10 /home/ohadr/vllm/wspipe.py client'
while true; do sleep 1; done