import os

import torch
import torch.distributed as dist
from torch.distributed import ProcessGroup

from vllm.platforms import current_platform

if current_platform.is_tpu():
    import torch_xla.core.xla_model as xm
    import torch_xla.runtime as xr
    from torch_xla._internal import pjrt

    from vllm.executor import ray_utils

from typing import List
class TpuCommunicator:

    def __init__(self, group: ProcessGroup, group_ranks: List[List[int]], ranks: List[int]):
        if not current_platform.is_tpu():
            self.disabled = True
            return
        self.disabled = False
        self.group_ranks = [tuple(x) for x in group_ranks]
        self.ranks = tuple(ranks)

        # NOTE(woosuk): When using TP > 1 on TPUs, every TPU on the same node
        # must be used together. Therefore, the local rank and world size can
        # be simply calculated as follows.
        global_rank = dist.get_rank(group)
        global_world_size = dist.get_world_size(group)
        num_nodes_get_num_tpu_nodes = ray_utils.get_num_tpu_nodes()
        num_nodes_in_pg = ray_utils.get_num_nodes_in_placement_group()
        if num_nodes_in_pg > 0:
            num_nodes = num_nodes_in_pg
        else:
            num_nodes = num_nodes_get_num_tpu_nodes
        local_world_size = global_world_size // num_nodes
        
        local_rank = global_rank % local_world_size
        # global_rank = self.ranks[dist.get_rank(group)]
        # global_world_size = sum(len(x) for x in self.group_ranks)
        # local_world_size = global_world_size//4
        print(f"{global_rank=}")
        print(f"{global_world_size=}")
        print(f"{local_world_size=}")
        print(f"{local_rank=}")

        # Calculate how many TPU nodes are in the current deployment. This
        # is the Ray placement group if it is deployed with Ray. Default
        # to the number of TPU nodes in the Ray cluster. The number of TPU
        # nodes is computed by the total number of TPUs divided by the
        # number of TPU accelerators per node, to account for clusters
        # with both CPUs and TPUs.
        
        # try:
        #     local_rank = global_rank % local_world_size
        # except Exception as e:
        #     print(f"{global_world_size=}")
        #     print(f"{global_rank=}")
        #     print(f"{local_world_size=}")
        #     print(f"{num_nodes_get_num_tpu_nodes=}")
        #     print(f"{num_nodes_in_pg=}")
        #     print(f"{ranks=}")
        #     print(f"{group_ranks=}")
        #     print(f"{e=}")
        #     raise AssertionError(f"Failed to calculate local rank: {global_world_size=}, {global_rank=}, {local_world_size=}")

        # global_rank = dist.get_rank(group)
        # global_world_size = dist.get_world_size(group)
        # Ensure environment variables are set for multihost deployments.
        # On GKE, this is needed for libtpu and TPU driver to know which TPU
        # chip is actually visible. Otherwise the TPU driver will fail to
        # initialize because the number of devices would be different from
        # the number of visible worker addresses.
        os.environ["CLOUD_TPU_TASK_ID"] = str(global_rank)
        os.environ["TPU_VISIBLE_CHIPS"] = str(local_rank)

        pjrt.initialize_multiprocess(local_rank, local_world_size)
        xr._init_world_size_ordinal()

    def all_reduce(self, x: torch.Tensor) -> torch.Tensor:
        return xm.all_reduce(xm.REDUCE_SUM, x)

    def all_gather(self, x: torch.Tensor, dim: int = -1) -> torch.Tensor:
        assert dim == -1, "TPUs only support dim=-1 for all-gather."
        return xm.all_gather(x, dim=dim)
