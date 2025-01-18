#python3.10 gen_inf.py
# int_start 20 128 "echo bye && sleep 30"
# int_start 20 128 gsutil cat gs://meliad2_us2_backup/scripts/15_01_2025/v35_scan_layersTrue_bf16momTrue_seq_length2048_num_epochs2_size405b31_128.sh > /tmp/script.sh; bash /tmp/script.sh
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
OUTPUT_DIR, output_dir, /workspace/vllm/blabla
MAX_EXAMPLES, max_examples, -1
NUM_WORKERS, num_workers, 16
MAX_TOKENS, max_tokens, 4096
SUFFIX, suffix, _v3
""")


with dag.DAG() as experiment:
    model("70b_reorder") >> suffix("_v1") >> max_examples(100)
  
    
task_dict, odict = dag.get_all_experiments(experiment, config, EXP_COUNTi)


def construct_command(bash_args_dict):
    if bash_args_dict["MODEL"] == "8b_instruct":
        bash_args_dict.update(MODEL_PATH="/mnt/gcs_bucket/models/Llama-3.1-8B-Instruct/",
                            MODEL_NAME="meta-llama/Llama-3.1-8B-Instruct")
    elif bash_args_dict["MODEL"] == "70b_reorder":
        bash_args_dict.update(MODEL_PATH="/mnt/gcs_bucket/AI2_EasyLM/v48_remat_blockTrue_seq_length4096_stsFalse_size70b",
                            MODEL_NAME="meta-llama/Llama-3.3-70B-Instruct_reorderer1")
    else:
        raise ValueError(f"Invalid model: {bash_args_dict['MODEL']}")
    
    bash_args_dict["DATASET_NAME"] = f"{bash_args_dict['ENTITY_NAME']}/{bash_args_dict['DS_NAME']}"
    
    return bash_args_dict

vllm_cmd_args = (
    "vllm serve {MODEL_PATH} ",
    "--max-model-len 16384 ",
    "--tensor-parallel-size 8 ",
    "--pipeline_parallel_size 1 ",
    "--distributed-executor-backend ray ",
    "--max-num-seqs 16 ",
    "--served-model-name {MODEL_NAME}",
)


dataset_cmd_args = (
        "python3.10 examples/run_on_dataset.py ",
        "--dataset_name {DATASET_NAME} ",
        "--config_name default ",
        "--num_workers {NUM_WORKERS} ",
        "--max_tokens {MAX_TOKENS} ",
        "--suffix {SUFFIX} ",
        "--verbose True ",
        "--temperature 0 ",
        "--split train ",
        "--base_url http://localhost:8000/v1",
        "--drop_last_msg True ",
        "--output_dir {OUTPUT_DIR} ",
        "--max_examples {MAX_EXAMPLES}",
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
# python3.10 gen_script3.py "int_start {node_idx} 64 '{s}' &" --nodes [3,4,5,8]
def main(format_str:str = '{s}', nodes: Optional[list[int]]  = None):
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



if __name__ == "__main__":
    fire.Fire(main)
# run_on_queue(tpu_dict)
