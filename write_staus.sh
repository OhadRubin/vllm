# Create output directory
rm -rf tmux_outputs
mkdir -p tmux_outputs

# Function to run commands in parallel and wait for completion
run_parallel_commands() {
    local command="$1"  # First argument is the command
    shift  # Remove first argument, remaining args are node indices
    local sequence=("$@")  # Arguments are node indices
    declare -A completed_files

    # Launch commands in parallel
    for node_idx in "${sequence[@]}"; do
        output_file="tmux_outputs/node_${node_idx}_output.txt"
        gcloud alpha compute tpus tpu-vm ssh v4-16-node-${node_idx} \
            --project=tpu-project-2-379909 \
            --zone=us-central2-b \
            --worker=all \
            --command="$command" \
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
}

# Run commands for all nodes in sequence
sequence=($(seq 8 40))
run_parallel_commands "tmux capture-pane -t resume_sh -p" "${sequence[@]}"

# Function to get node IDs with matching string
get_node_ids() {
    local search_string="$1"
    local node_ids=()
    
    for file in tmux_outputs/node_*_output.txt; do
        if [ -s "$file" ] && grep -q "$search_string" "$file"; then
            # echo "=== $file:"
            # cat "$file"
            node_id=$(echo "$file" | sed -n 's/.*node_\([0-9]\+\)_output.txt/\1/p')
            node_ids+=($node_id)
        fi
    done
    
    echo "${node_ids[@]}"
}

# # Get nodes with TPU host message
node_ids=$(get_node_ids "Broadcasting")

echo "Nodes with TPU host message: ${node_ids[@]}"


# 12 13 15 17 19 20 21 22 23 25 26 27 29 31 32 33 34 36 37 38 39 40 9
# mkdir -p tmux_outputs_installation
# run_parallel_commands() {
#     local command="$1"  # First argument is the command
#     shift  # Remove first argument, remaining args are node indices
#     local sequence=("$@")  # Arguments are node indices
#     declare -A completed_files

#     # Launch commands in parallel
#     for node_idx in "${sequence[@]}"; do
#         output_file="tmux_outputs_installation/node_${node_idx}_output.txt"
#         gcloud alpha compute tpus tpu-vm ssh v4-16-node-${node_idx} \
#             --project=tpu-project-2-379909 \
#             --zone=us-central2-b \
#             --worker=all \
#             --command="$command" \
#             > "$output_file" 2>/dev/null &
        
#         # Track PID and output file
#         pid=$!
#         completed_files[$pid]=$output_file
#     done

#     # Wait for all background processes to complete
#     for pid in "${!completed_files[@]}"; do
#         wait $pid
#         if [ $? -ne 0 ]; then
#             echo "Error capturing output for ${completed_files[$pid]}"
#         fi
#     done
# }

# # Run commands for all nodes in sequence
# sequence=(11 12 17 26 30 31 33 39 8)
# run_parallel_commands "tmux capture-pane -t installation_window -p" "${sequence[@]}"