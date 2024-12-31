# system_message = system_message.split("\n")[0]
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
# import islice
from itertools import islice
from tqdm import tqdm  # Add this import

logger.setLevel(logging.ERROR)
# env_vars = dotenv_values(os.path.expanduser("~/.bashrc"))
# OPENROUTER_API_KEY = env_vars.get("OPENROUTER_API_KEY")

from transformers import AutoTokenizer
print("loading tokenizer")


import pathlib
from tenacity import retry, stop_after_attempt, wait_exponential
from ml_collections import ConfigDict

class Worker:
    def __init__(self, config):
        self.config = config
        self.max_seq_length = config.max_seq_length
        self.client = OpenAI(
            api_key="EMPTY",
            base_url=config.base_url,
        )
        self.max_tokens = config.max_tokens
        self.verbose = self.config.verbose

    @retry(
        stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=4, max=10)
    )
    def __call__(self, tup):
        print("running generate")
        example_id, example = tup

        response = self.client.chat.completions.create(
            model=self.config.model_name,
            temperature=self.config.temperature,
            messages=example["messages"],
            max_tokens=self.config.max_tokens,
            # extra_body={
            # "min_tokens": max_tokens,
            # "stop": ['\nExpert: "I\'m done."']
            # }
        )
        prediction = response.choices[0].message.content
        example["prediction"] = prediction
        return example






def init_worker(config):
    global worker
    worker = Worker(config)


def process_example(example_id):
    global worker
    return worker(example_id)



def run_files(config):

    ds = datasets.load_dataset(config.dataset_name,
                               config.config_name
                               )[config.split]
    
    if config.max_examples != -1:
        max_examples = min(config.max_examples, len(ds))
    else:
        max_examples = len(ds)

    tups = range(max_examples)

    print(tups)
    tups = ((i, ds[i]) for i in tups)

    with Pool(
        config.num_workers,
        initializer=init_worker,
        initargs=(config,),
    ) as pool:
        outputs = []
        with tqdm.tqdm(total=len(tups)) as pbar:
            for example in pool.imap_unordered(process_example, tups):
                outputs.append(example)
                pbar.update(1)
    with open(config.output_file, "w") as f:
        for example in outputs:
            f.write(json.dumps(example) + "\n")



import time
import pathlib


# python3.10 gen_examples.py --model_name meta-llama/Llama-3.1-70B --base_url https://v4-32-node-11.ohadrubin.com/v1 --max_seq_length 16384 --prompt_folder prompts/v5 --num_workers 16 --max_tokens 2048 --suffix _v8 --max_steps 1 --verbose True --temperature 0.8 --shard_id 1
# python3.10 examples/run_on_dataset.py --dataset_name iohadrubin/gpqa --config_name gold_sft_0 --max_seq_length 16384 --num_workers 16 --max_tokens 2048 --suffix _v0 --max_examples 1 --verbose True --temperature 0.8
import requests

def main(dataset_name: str="iohadrubin/gpqa",
         config_name: str="gold_sft_0",
         split: str = "validation",
         base_url: str = "http://localhost:8000/v1",
         max_seq_length: int = 16384,
         suffix: str = "",
         num_workers: int = 1,
         max_tokens: int = 1024,
         max_steps:int = -1,
         max_examples:int = -1,
         verbose:bool = False,
         temperature:float = 0.7,
         ):
    # model_name: str
    while True:
        response = requests.get(f"{base_url}/models")
        if response.status_code == 200:
            models = response.json()["data"]
            if len(models) > 0:
                model_name = models[0]["id"]
                break
            else:
                raise ValueError("No models found in the server response")
        else:
            raise ValueError(f"Failed to get models from server. Status code: {response.status_code}")

    output_file = f"outputs/{dataset_name.replace('/', '_')}_{config_name}_{model_name.replace('/', '_')}{suffix}.jsonl"
    pathlib.Path("outputs").mkdir(exist_ok=True)
    

    
    config = ConfigDict(
        dict(
            dataset_name=dataset_name,
            config_name=config_name,
            split=split,
            max_seq_length=max_seq_length,
            base_url=base_url,
            output_file=output_file,
            num_workers=num_workers,
            max_tokens=max_tokens,
            model_name=model_name,
            max_examples=max_examples,
            verbose=verbose,
            temperature=temperature,

        )
    )
    run_files(config)


if __name__ == "__main__":
    """
    Usage:
        python3.10 gen_examples.py --output_file llama3-3-70b-instruct_v1.jsonl

    Args:
        output_file: Path to save the generated examples in JSONL format
    """
    fire.Fire(main)
