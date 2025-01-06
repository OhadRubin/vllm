import asyncio
import json
import time
import pathlib
import requests
from typing import Optional

from datasets import load_dataset
from dotenv import dotenv_values
from dotenv.main import logger
import logging
from openai import OpenAI
from tqdm import tqdm
from ml_collections import ConfigDict
import fire
from transformers import AutoTokenizer
logger.setLevel(logging.ERROR)

class Worker:
    def __init__(self, config):
        self.config = config
        self.client = OpenAI(
            api_key=config.api_key,
            base_url=config.base_url,
        )
        self.drop_last_msg = config.drop_last_msg
        self.max_tokens = config.max_tokens
        self.model_name = config.model_name
        self.temperature = config.temperature
        self.tokenizer = AutoTokenizer.from_pretrained("meta-llama/Llama-3.1-70B-Instruct")
        self.verbose = config.verbose
        self.max_seq_length = config.max_seq_length

    async def process_example(self, example_id, example):
        if self.drop_last_msg:
            messages = example["messages"][:-1]
        else:
            messages = example["messages"]

        # Simulate async call with run_in_executor or a library that supports async requests
        # For demonstration, using a simple wrapper
        L = len(self.tokenizer.apply_chat_template(messages))
        if (L+self.max_tokens) > self.max_seq_length:
            example["prediction"] = ""
            return example
        response = await asyncio.get_event_loop().run_in_executor(
            None,
            lambda: self.client.chat.completions.create(
                model=self.model_name,
                temperature=self.temperature,
                messages=messages,
                max_tokens=self.max_tokens,
            ),
        )

        prediction = response.choices[0].message.content
        example["prediction"] = prediction
        if self.verbose:
            print(prediction)
        return example


async def run_files(config):
    ds = load_dataset(config.dataset_name, config.config_name)[config.split]

    if config.max_examples != -1:
        max_examples = min(config.max_examples, len(ds))
    else:
        max_examples = len(ds)

    worker = Worker(config)

    tasks = []
    semaphore = asyncio.Semaphore(config.num_workers)

    async def sem_task(i):
        async with semaphore:
            return await worker.process_example(i, ds[i])

    for i in range(max_examples):
        tasks.append(asyncio.create_task(sem_task(i)))

    pathlib.Path("outputs").mkdir(exist_ok=True)
    with open(config.output_file, "w") as f:
        for future in tqdm(asyncio.as_completed(tasks), total=len(tasks)):
            result = await future
            f.write(json.dumps(result) + "\n")


def main(dataset_name: str="iohadrubin/gpqa",
         config_name: str="gold_sft_0",
         split: str = "validation",
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
         ):
    if model_name is None:
        while True:
            try:
                response = requests.get(f"{base_url}/models")
                if response.status_code == 200:
                    models = response.json().get("data", [])
                    if len(models) > 0:
                        model_name = models[0]["id"]
                        break
                    else:
                        raise ValueError("No models found.")
                else:
                    raise ValueError(f"Failed to get models. Status code: {response.status_code}")
            except Exception as e:
                print(f"Failed to get models. Error: {e}")
                time.sleep(1)

    output_file = f"outputs/{dataset_name.replace('/', '_')}_{config_name}_{model_name.replace('/', '_')}{suffix}.jsonl"

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
            max_seq_length=16384,
        )
    )

    asyncio.run(run_files(config))


if __name__ == "__main__":
    fire.Fire(main)
