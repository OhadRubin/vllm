#python3.10 gen_inf.py --queue True
# int_start 20 128 "echo bye && sleep 30"
# int_start 20 128 gsutil cat gs://meliad2_us2_backup/scripts/15_01_2025/v35_scan_layersTrue_bf16momTrue_seq_length2048_num_epochs2_size405b31_128.sh > /tmp/script.sh; bash /tmp/script.sh
# gsutil ls gs://meliad2_us2_backup/generated_data/*_01_2025 | grep shard5 | grep jsonl | sed -n 's/.*jsonl\.\([0-9]\+\).*/\1/p'
import mlxu
import datetime
from collections import defaultdict
import sys
import re
import fire
import os
sys.path.append(os.path.expanduser("~/redis_queue"))
from src.redis_queue import RedisQueue

preramble=r"""
cd ~/vllm
git pull
"""

def one_liner(path):
    return f"gsutil cat {path} > /tmp/script.sh; bash /tmp/script.sh"

def run_on_queue(tpu_dict):
    for k in tpu_dict.keys():
        q_name = f"v4-{k}"
        queue = RedisQueue(name=q_name)
        for v in tpu_dict[k]:
            cmd = one_liner(v)
            print(f"adding {cmd} to {q_name}")
            queue.put(cmd)


import dag
EXP_COUNTi = 48
Branch = dag.Branch
Node = dag.Node

# size can be 1b or 8b
config =dag.load_config("""
---
TPU, tpu, 16
MODEL, model, 8b_instruct 
ENTITY_NAME, entity_name, iohadrubin
DS_NAME, ds_name, reorder_thoughts_v1
OUTPUT_DIR, output_dir, /mnt/gcs_bucket/generated_data
MAX_EXAMPLES, max_examples, -1
NUM_WORKERS, num_workers, 16
MAX_TOKENS, max_tokens, 4096
SUFFIX, suffix, _v3
SPLIT, split, train
SHARD_ID, shard_id, 0
NUM_SHARDS, num_shards, 1
TEMPERATURE, temperature, 0
CONFIG_NAME, config_name, default
""")



with dag.DAG() as experiment:
    # shards_ids = [52, 56, 58, 64, 67, 68, 75, 76, 78, 79, 84, 86, 92, 94, 96, 98, 104, 105, 107, 108, 110, 111, 122, 123, 126, 127]
    # model("70b_enhance1") >> suffix("_v3") >> \
    # ds_name("thought_enhancement_task_v1") >> split("test") >> \
    # shard_id(*shards_ids) >> num_shards(128) >> temperature(1)


    model("70b_cond1.1") >> suffix("_v0") >> \
    ds_name("diverse_thinking_out_loud_v2.0_test") >> split("train") >> \
    shard_id(*list(range(373))[::-1]) >> num_shards(373) >> temperature(1) >> num_workers(16) >> max_tokens(8192)
    # model("8b_tagging1") >> suffix("_v1") >> \
    # ds_name("thought_catagory_tagging_v1") >> split("test") >> \
    # shard_id(*range(32)) >> num_shards(32) >> temperature(0) >> num_workers(32)
  
    
task_dict, odict = dag.get_all_experiments(experiment, config, EXP_COUNTi)


def construct_command(bash_args_dict):
    if bash_args_dict["MODEL"] == "8b_instruct":
        bash_args_dict.update(MODEL_PATH="/mnt/gcs_bucket/models/Llama-3.1-8B-Instruct/",
                            MODEL_NAME="meta-llama/Llama-3.1-8B-Instruct")
    elif bash_args_dict["MODEL"] == "70b_reorder":
        bash_args_dict.update(MODEL_PATH="/mnt/gcs_bucket/AI2_EasyLM/v48_remat_blockTrue_seq_length4096_stsFalse_size70b",
                            MODEL_NAME="meta-llama/Llama-3.3-70B-Instruct_reorderer1")
    elif bash_args_dict["MODEL"] == "70b_enhance1":
        bash_args_dict.update(MODEL_PATH="/mnt/gcs_bucket/AI2_EasyLM/v49_ds_nameenhance_seq_length8192_size70b",
                            MODEL_NAME="meta-llama/Llama-3.3-70B-Instruct_enhance1")
    elif bash_args_dict["MODEL"] == "8b_tagging1":
        bash_args_dict.update(MODEL_PATH="/mnt/gcs_bucket/AI2_EasyLM/v50_ds_nametag_ags8_seq_length16384_num_epochs4_size8b",
                            MODEL_NAME="meta-llama/Llama-3.1-8B-Instruct")
    elif bash_args_dict["MODEL"] == "70b_multi1":
        bash_args_dict.update(MODEL_PATH="/mnt/gcs_bucket/AI2_EasyLM/v52_ds_namemultitask2_ags4_seq_length8192_num_epochs1_size70b",
                            MODEL_NAME="meta-llama/Llama-3.1-8B-Instruct")
    elif bash_args_dict["MODEL"] == "70b_multi2":
        bash_args_dict.update(MODEL_PATH="/mnt/gcs_bucket/AI2_EasyLM/v52_ds_namemultitask2_ags4_seq_length8192_num_epochs1_size70b",
                            MODEL_NAME="meta-llama/Llama-3.1-8B-Instruct")
    elif bash_args_dict["MODEL"] == "70b_enhance4":
        bash_args_dict.update(MODEL_PATH="/mnt/gcs_bucket/AI2_EasyLM/v52_ds_nameenhance4_ags4_seq_length8192_num_epochs1_size70b",
                            MODEL_NAME="meta-llama/Llama-3.1-8B-Instruct")
    elif bash_args_dict["MODEL"] == "70b_cond1.1":
        bash_args_dict.update(MODEL_PATH="/mnt/gcs_bucket/saved_models/01_02_2025/v60_ds_namecond1.1_ags8_seq_length8192_num_epochs1_size70b",
                            MODEL_NAME="meta-llama/Llama-3.1-8B-Instruct")
    else:
        raise ValueError(f"Invalid model: {bash_args_dict['MODEL']}")

    bash_args_dict["DATASET_NAME"] = f"{bash_args_dict['ENTITY_NAME']}/{bash_args_dict['DS_NAME']}"
    

    now = datetime.datetime.now()
    formatted_date = now.strftime("%d_%m_%Y")
    bash_args_dict["OUTPUT_DIR"] = f"{bash_args_dict['OUTPUT_DIR']}/{formatted_date}"
    
    SHARD_ID = str(bash_args_dict['SHARD_ID'])
    OUTPUT_FILE = f"{bash_args_dict['WANDB_NAME']}.jsonl".replace(f"_shard_id{SHARD_ID}_", "_")
    bash_args_dict["OUTPUT_FILE"] = f"{OUTPUT_FILE}.{SHARD_ID}"
    bash_args_dict["DROP_LAST_MSG"] = str(bash_args_dict["SPLIT"]=="train")

    # Add shard args construction
    shard_args = ""
    if bash_args_dict["SHARD_ID"] != "None" and bash_args_dict["NUM_SHARDS"] != "None":
        shard_args = f"--shard_id {bash_args_dict['SHARD_ID']} --num_shards {bash_args_dict['NUM_SHARDS']}"
    bash_args_dict["SHARD_ARGS"] = shard_args

    return bash_args_dict

vllm_cmd_args = (
    "vllm serve {MODEL_PATH} ",
    "--max-model-len 16384 ",
    "--tensor-parallel-size 8 ",
    "--pipeline_parallel_size 1 ",
    "--distributed-executor-backend ray ",
    "--max-num-seqs {NUM_WORKERS} ",
    "--served-model-name {MODEL_NAME}",
)


dataset_cmd_args = (
        "python3.10 examples/run_on_dataset.py ",
        "--model_name {MODEL_NAME} ",
        "--dataset_name {DATASET_NAME} ",
        "--config_name {CONFIG_NAME} ",
        "--num_workers {NUM_WORKERS} ",
        "--max_tokens {MAX_TOKENS} ",
        "--suffix {SUFFIX} ",
        "--verbose False ",
        "--temperature {TEMPERATURE} ",
        "--split {SPLIT} ",
        "--base_url http://localhost:8000/v1",
        "--drop_last_msg {DROP_LAST_MSG}",
        "--output_dir {OUTPUT_DIR} ",
        "--output_file {OUTPUT_FILE} ",
        "--max_examples {MAX_EXAMPLES}",
        "{SHARD_ARGS}",
    )




dataset_cmd = " \\\n\t".join(dataset_cmd_args)
vllm_cmd = " \\\n\t".join(vllm_cmd_args)

final_cmd = f'bash run_cluster_compose.sh launch dataset "{vllm_cmd}" "{dataset_cmd}"'

suffix = """
echo "Done with $OUTPUT_DIR"

"""

import fire
from typing import Optional
# usage: python3.10 gen_script3.py "int_start 3 64 '{s}'"

# python3.10 gen_inf.py "int_start {node_idx} 16 '{s}' &" --nodes [14,16,17,21]
# Example usage:
# python3.10 gen_inf.py "int_start {node_idx} 16 '{s}' &" --node_range "14,31"
# python3.10 gen_inf.py "int_start {node_idx} 16 '{s}' &" --node_range "14,31" --queue True

# gcloud alpha compute tpus tpu-vm ssh v4-16-node-17 \
#   --project=tpu-project-2-379909 \
#   --batch-size 2 \
#   --zone=us-central2-b \
#   --worker=all \
#   --command='tmux new-session -d -s test_session "echo hi && sleep 10"'

# python3.10 gen_inf.py --exclude_nodes 15 --node_range "14,31" --format_str "gcloud alpha compute tpus tpu-vm ssh v4-16-node-{node_idx} --project=tpu-project-2-379909 --zone=us-central2-b --worker=all --command='tmux kill-server 2>/dev/null || true; sleep 5; tmux new-session -d -s test_session \"{s}\"' &"
# python3.10 gen_inf.py --nodes 14,15,16,21,26,28,29,30 --format_str "./queue.sh enqueue \"{s}\" &"
# python3.10 gen_inf.py --format_str "./queue.sh enqueue \"{s}\" &"


# 14,15,16,21,26,28,29,30
# gcloud alpha compute tpus tpu-vm ssh v4-16-node-{node_idx} --project=tpu-project-2-379909 --zone=us-central2-b --worker=all --command='tmux capture-pane -t test_session -p -S -' &
import tempfile

def main(
        #  format_str:str = '{s}',
         format_str:str = 'queue.sh enqueue "{s}" &',
         nodes: Optional[list[int]]  = None,
         node_range: str = None,
         queue: bool = False,
         exclude_nodes: Optional[str] = None,
         ):
    if node_range is not None:
        node_range = range(node_range[0], node_range[1])
        nodes = list(node_range)
    if exclude_nodes is not None:
        if isinstance(exclude_nodes, str):
            exclude_nodes = [int(node) for node in exclude_nodes.split(",")]
        elif isinstance(exclude_nodes, int):
            exclude_nodes = [exclude_nodes]
        nodes = [node for node in nodes if node not in exclude_nodes]
    
    now = datetime.datetime.now()
    path_prefix = "gs://meliad2_us2_backup/scripts"
    formatted_date = now.strftime("%d_%m_%Y")
    tpu_dict = defaultdict(list)
    list_of_cmds = []
    for node_idx , (wandb_name, bash_args_str) in enumerate(task_dict.items()):
        bash_args_dict = odict[wandb_name]
        file_path = f"{path_prefix}/{formatted_date}/{wandb_name}.sh"
        
        
        tpu_dict[bash_args_dict["TPU"]].append(file_path)
        
        bash_args_dict = construct_command(bash_args_dict)
        cmds = [preramble, bash_args_str, final_cmd, suffix]
        
        
            
        script = "\n".join(cmds)
        for k,v in {**bash_args_dict}.items():
            script = script.replace("{"+k+"}", str(v))    
        assert not re.search(r'\{[A-Z_]+\}', script)
            
        one_liner_str = one_liner(file_path)
        if nodes is not None:
            cmd = format_str.format(s=one_liner_str, node_idx=nodes[node_idx])
        else:
            cmd = format_str.format(s=one_liner_str)
        print(cmd)
        # print(cmd)
        list_of_cmds.append(cmd)
        with mlxu.open_file(file_path, 'w') as fin:
            fin.write(script)
        if queue:
            os.system(cmd)

    # Write commands to temp file
    with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.txt') as tmp:
        for cmd in list_of_cmds:
            tmp.write(cmd + '\n')
        print(f"Commands written to: {tmp.name}")


if __name__ == "__main__":
    fire.Fire(main)

