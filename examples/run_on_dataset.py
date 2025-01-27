
from datasets import load_dataset
from multiprocessing import Pool
import os
from dotenv import dotenv_values
from dotenv.main import logger
import logging
from openai import OpenAI
import multiprocessing
import datasets
import pathlib
import fire
import json
from itertools import islice
from tqdm import tqdm  # Add this import

logger.setLevel(logging.ERROR)


from transformers import AutoTokenizer
print("loading tokenizer")

from anthropic import AnthropicBedrock

import pathlib
from ml_collections import ConfigDict


class OAIClient:
    def __init__(self, config):
        self.config = config
        self.client = OpenAI(
            api_key=config.api_key,
            base_url=config.base_url,
        )
    def __call__(self, messages):
        response = self.client.chat.completions.create(
            model=self.config.model_name,
            temperature=self.config.temperature,
            messages=messages,
            max_tokens=self.config.max_tokens,
        )
        prediction = response.choices[0].message.content
        return prediction
    

class AnthropicClient:
    def __init__(self, config):
        self.config = config
        self.client = AnthropicBedrock(
            aws_region="us-west-2",
        )
    def __call__(self, messages):
        try:
            response = self.client.messages.create(
                model=self.config.model_name,
                temperature=self.config.temperature,
                messages=messages,
                max_tokens=self.config.max_tokens,
            )
            return response.content[0].text
        except Exception as e:
            print(f"Error getting prediction: {e}")
            return ""


class Worker:
    def __init__(self, config):
        self.config = config
        if "claude" in config.model_name:
            self.client = AnthropicClient(config)
        else:
            self.client = OAIClient(config)
        self.max_tokens = config.max_tokens
        self.verbose = self.config.verbose
        self.drop_last_msg = config.drop_last_msg
        self.tokenizer = AutoTokenizer.from_pretrained("meta-llama/Llama-3.1-70B-Instruct")
        self.max_seq_length = config.max_seq_length

    def __call__(self, tup):
        print("running generate")
        example_id, example = tup
        example["index"] = example_id
        if self.drop_last_msg:
            messages = example["messages"][:-1]
        else:
            messages = example["messages"]
        L = len(self.tokenizer.apply_chat_template(messages))
        if (L+self.max_tokens) > self.max_seq_length:
            example["prediction"] = ""
            return example

        example["prediction"] = self.client(messages)
        return example


def init_worker(config):
    global worker
    worker = Worker(config)


def process_example(tup):
    global worker
    return worker(tup)


def start_pool(config, processed_indices):
    # Load dataset
    if config.from_disk:
        ds = datasets.load_from_disk(config.dataset_name)[config.split]
    else:
        ds = datasets.load_dataset(
            config.dataset_name,
            config.config_name
        )[config.split]
    
    # Handle sharding
    if config.shard_id is not None:
        assert config.num_shards is not None, "num_shards must be provided if shard_id is provided"
        ds = ds.shard(config.num_shards, config.shard_id)
    
    # Calculate max examples
    max_examples = min(config.max_examples, len(ds)) if config.max_examples != -1 else len(ds)
    
    # Generate remaining indices to process
    remaining_indices = [i for i in range(max_examples) if i not in processed_indices]
    
    # Create generator for examples
    tups = ((i, ds[i]) for i in remaining_indices)
    cnt = 0
    # Process examples
    with Pool(
        config.num_workers,
        initializer=init_worker,
        initargs=(config,),
    ) as pool:
        with tqdm(total=len(remaining_indices), desc="Processing examples") as pbar:
            for example in pool.imap_unordered(process_example, tups):
                if config.verbose or (cnt % config.verbose_every == 0):
                    print("Prediction:")
                    print("---")
                    print(example["prediction"])
                yield example
                pbar.update(1)
                cnt +=1

from more_itertools import chunked
def run_files(config):
    processed_indices = set()
    
    # Check for existing progress if not overwriting
    if not config.force_overwrite and os.path.exists(config.output_file):
        try:
            with open(config.output_file, 'r') as f:
                for line in f:
                    try:
                        example = json.loads(line)
                        processed_indices.add(example['index'])
                    except json.JSONDecodeError:
                        continue  # Skip invalid/corrupted lines
        except FileNotFoundError:
            pass
    
    # Get processed examples
    outputs = start_pool(config, processed_indices)
    
    # Write results
    mode = "w" if config.force_overwrite else "a"
    count = 0
    try:
        for chunk in chunked(outputs, 10):
            bytes_written = 0
            with open(config.output_file, mode) as f:
                for example in chunk:
                    line = json.dumps(example) + "\n"
                    bytes_written += f.write(line)
                    count += 1
            print(f"Wrote {bytes_written / (1024 * 1024):.2f} MB into {config.output_file}")
            mode = "a"
    except Exception as e:
        print(f"Error writing to file: {e}")
        raise
    print(f"Wrote {count} examples to {config.output_file}")




import time
import pathlib


import requests

from typing import Optional

def main(dataset_name: Optional[str]=None,
         config_name: Optional[str]="default",
         split: Optional[str] = None,
         from_disk: bool = False,
         base_url: str = "http://localhost:8000/v1",
         suffix: str = "",
         num_workers: int = 1,
         max_tokens: int = 1024,
         model_name: Optional[str] = None,
         max_examples:int = -1,
         verbose:bool = False,
         temperature:float = 0.7,
         api_key: str = "bla",
         drop_last_msg:bool = False,
         output_dir: str = "outputs",
         output_file: Optional[str] = None,
         shard_id: Optional[int] = None,
         num_shards: Optional[int] = None,
         max_seq_length: int = 16384,
         save_online: bool = False,
         force_overwrite: bool = False,
         verbose_every: int = 100,
         ):
    # model_name: str
    pathlib.Path(output_dir).mkdir(exist_ok=True)
    assert model_name is not None, "model_name must be provided"
    # if model_name is None:
    #     while True:
    #         try:
    #             response = requests.get(f"{base_url}/models")
    #             if response.status_code == 200:
    #                 models = response.json()["data"]
    #                 if len(models) > 0:
    #                     model_name = models[0]["id"]
    #                     break
    #                 else:
    #                     raise ValueError("No models found in the server response")
    #             else:
    #                 raise ValueError(f"Failed to get models from server. Status code: {response.status_code}")
    #         except Exception as e:
    #             print(f"Failed to get models from server. Error: {e}")
    #             time.sleep(1)

    
    if output_file is None:
        output_file = f"{output_dir}/{dataset_name.replace('/', '_')}_{config_name}_{model_name.replace('/', '_')}{suffix}.jsonl"
        if shard_id is not None:
            output_file = f"{output_file}.{shard_id}"
    else:
        output_file = f"{output_dir}/{output_file}"
    

    
    config = ConfigDict(
        dict(
            dataset_name=dataset_name,
            config_name=config_name,
            split=split,
            base_url=base_url,
            output_file=output_file,
            num_workers=num_workers,
            max_tokens=max_tokens,
            model_name=model_name,
            max_examples=max_examples,
            verbose=verbose,
            temperature=temperature,
            api_key=api_key,
            drop_last_msg=drop_last_msg,
            max_seq_length=max_seq_length,
            output_dir=output_dir,
            shard_id=shard_id,
            num_shards=num_shards,
            save_online=save_online,
            force_overwrite=force_overwrite,
            from_disk=from_disk,
            verbose_every=verbose_every,
        )
    )
    run_files(config)




# python3.10 gen_examples.py --model_name meta-llama/Llama-3.1-70B --base_url https://v4-32-node-11.ohadrubin.com/v1  --prompt_folder prompts/v5 --num_workers 16 --max_tokens 2048 --suffix _v8 --max_steps 1 --verbose True --temperature 0.8 --shard_id 1
# python3.10 examples/run_on_dataset.py --dataset_name iohadrubin/gpqa --config_name gold_sft_0  --num_workers 16 --max_tokens 2048 --suffix _v0  --verbose True --temperature 0.8
# python3.10 examples/run_on_dataset.py --dataset_name iohadrubin/example_to_realign_v1 --config_name default  --num_workers 16 --max_tokens 4096 --suffix _v0  --verbose True --temperature 0.6 --split train --base_url https://api.openai.com/v1 --model_name gpt-4o-mini  --api_key $OPENAI_API_KEY 

# python3.10 examples/run_on_dataset.py --dataset_name iohadrubin/thought_catagory_tagging --config_name default  --num_workers 16 --max_tokens 4096 --max_seq_length 32768 --suffix _v0  --verbose True --temperature 1 --split test --base_url https://api.openai.com/v1 --model_name gpt-4o-mini  --api_key $OPENAI_API_KEY --drop_last_msg False 


# python3.10 examples/run_on_dataset.py --dataset_name iohadrubin/thought_catagory_tagging_all --config_name default  --num_workers 32 --max_tokens 8192 --max_seq_length 32768 --suffix _v0  --verbose True --temperature 1 --split test --base_url https://api.openai.com/v1 --model_name gpt-4o  --api_key $OPENAI_API_KEY --drop_last_msg False  --verbose True 


# python3.10 examples/run_on_dataset.py --dataset_name iohadrubin/bridging_prompt_input_v1 --config_name default  --num_workers 32 --max_tokens 8192 --max_seq_length 32768 --suffix _v0  --verbose True --temperature 1 --split train --model_name anthropic.claude-3-5-sonnet-20241022-v2:0 --verbose True


#python3.10 examples/run_on_dataset.py --dataset_name iohadrubin/correct_usage_v1 --config_name default  --num_workers 32 --max_tokens 8192 --max_seq_length 32768 --suffix _v0  --verbose True --temperature 1 --split train --model_name anthropic.claude-3-5-sonnet-20241022-v2:0 --verbose True

# python3.10 examples/run_on_dataset.py --dataset_name iohadrubin/thought_catagory_tagging_all_v2 --config_name default  --num_workers 32 --max_tokens 8192 --max_seq_length 32768 --suffix _v2  --verbose True --temperature 0 --split test --base_url https://api.openai.com/v1 --model_name gpt-4o  --api_key $OPENAI_API_KEY --drop_last_msg False  --save_online True

# give file path and output_file 

# python3.10 examples/run_on_dataset.py --dataset_name /home/ohadr/general_o1/outputs/tagging_dataset_leftover  --num_workers 32 --max_tokens 8192 --max_seq_length 32768 --suffix _v2  --verbose True --temperature 0 --split test --base_url https://api.openai.com/v1 --model_name gpt-4o  --api_key $OPENAI_API_KEY --drop_last_msg False  --save_online True --output_file leftovers_thought_catagory_tagging_all_v2_gpt-4o.jsonl --from_disk True

# python3.10 examples/run_on_dataset.py --dataset_name iohadrubin/reorder_thoughts_v1 --config_name default  --num_workers 16 --max_tokens 4096 --suffix _v2  --verbose True --temperature 0.1 --split test --base_url https://v4-16-node-20.ohadrubin.com/v1 --max_examples 100 --drop_last_msg True

# python3.10 examples/run_on_dataset_async.py --dataset_name iohadrubin/reorder_thoughts_v1 --config_name default  --num_workers 16 --max_tokens 4096 --suffix _v3  --verbose True --temperature 0 --split train --base_url https://v4-16-node-20.ohadrubin.com/v1 --drop_last_msg True
# python3.10 examples/run_on_dataset.py --dataset_name iohadrubin/reorder_thoughts_v1 --config_name default  --num_workers 16 --max_tokens 4096 --suffix _v3  --verbose True --temperature 0 --split train --base_url http://localhost:8000/v1 --drop_last_msg True



if __name__ == "__main__":
    """
    Usage:
        python3.10 gen_examples.py --output_file llama3-3-70b-instruct_v1.jsonl

    Args:
        output_file: Path to save the generated examples in JSONL format
    """
    fire.Fire(main)
