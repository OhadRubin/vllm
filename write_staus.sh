# Create output directory
mkdir -p tmux_outputs

# --command='tmux capture-pane -t test_session -p -S -' \
# Loop through node indices and capture tmux output to files

sequence=(18 40 28 25 27 11 33 19 13 9 22 39 24 17 29 32 30 12 8 34 26 38 31 21 14 15 37 10)

# Create array to track completed files
declare -A completed_files

# Launch commands in parallel
for node_idx in ${sequence[@]}; do
    output_file="tmux_outputs/node_${node_idx}_output.txt"
    gcloud alpha compute tpus tpu-vm ssh v4-16-node-${node_idx} \
        --project=tpu-project-2-379909 \
        --zone=us-central2-b \
        --worker=all \
        --command='tmux capture-pane -t resume_sh -p' \
        > "$output_file" 2>/dev/null &
    
    # Track PID and output file
    pid=$!
    completed_files[$pid]=$output_file
done

# Wait for all background processes to complete
for pid in "${!completed_files[@]}"; do
    wait $pid
    if [ $? -ne 0 ]; then
        echo "Error capturing output for ${completed_files[$pid]}"
    fi
done

# Check contents of output files
for file in tmux_outputs/node_*_output.txt; do
    if [ -s "$file" ] && grep -q "on all TPU hosts" "$file"; then
        echo "=== $file:"
        echo "file contains: on all TPU hosts"
    fi
done
