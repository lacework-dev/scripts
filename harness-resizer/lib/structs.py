#!/usr/bin/env python3

from typing import Optional, ClassVar, Union
from enum import Enum

import re
from functools import cache
from dataclasses import dataclass

from dataclasses_json import dataclass_json
import oyaml as yaml

class ClusterType(Enum):
    US_PROD = "US_PROD"
    EU_PROD = "EU_PROD"
    PROD_REPLICA = "PROD_REPLICA"
    PREPROD = "PRE_PROD"
    SPORK = "SPORK"
    DEV = "DEV"
    QA = "QA"
    OTHER = "OTHER"

@dataclass_json()
@dataclass
class ResourceCount:
    MEMORY_UNITS: ClassVar[str] = {
        "T": 10**12,
        "G": 10**9,
        "M": 10**6,
        "k": 10**3,
        "Ti": 2**40,
        "Gi": 2**30,
        "Mi": 2**20,
        "Ki": 2**10,
    }

    cpu: Optional[str] = None
    memory: Optional[str] = None

    @property
    def cpu_val(self) -> Union[int, str]:
        try:
            return int(self.cpu)
        except:
            return self.cpu

    @property
    def cpu_cores(self) -> Optional[float]:
        """
        Parse millicpu
        https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/#resource-units-in-kubernetes
        """
        if self.cpu is None:
            return None
        if match := re.search("([0-9]+)m", self.cpu, re.IGNORECASE):
            return float(match.group(1)) / 1000
        return float(self.cpu)
    
    @classmethod
    def pretty_cpu(cls, num_cores : float) -> Union[float, str]:
        if num_cores < 2:
            return f"{(num_cores * 1000):.0f}m"
        return round(num_cores, 2)

    @classmethod
    @cache
    def _memory_pattern(cls):
        return "(" + ("|".join(cls.MEMORY_UNITS.keys())) + ")"

    @property
    def memory_val(self) -> Union[int, str]:
        try:
            return int(self.memory)
        except:
            return self.memory

    @property
    def memory_bytes(self) -> Optional[int]:
        """
        Parse memory spec
        https://kubernetes.io/docs/reference/kubernetes-api/common-definitions/quantity/
        """
        if self.memory is None:
            return None
        if match := re.search(f"([0-9]+){self._memory_pattern()}", self.memory):
            return int(match.group(1)) * self.MEMORY_UNITS[match.group(2)]
        return int(self.memory)

    @classmethod
    def pretty_memory(cls, num_bytes : int) -> str:
        if num_bytes > cls.MEMORY_UNITS['Gi']:
            return f"{num_bytes / cls.MEMORY_UNITS['Gi']:.2f}Gi"
        if num_bytes > cls.MEMORY_UNITS['Mi']:
            return f"{num_bytes / cls.MEMORY_UNITS['Mi']:.2f}Mi"
        return f"{num_bytes // cls.MEMORY_UNITS['Ki']}Ki"

    def to_yaml(self):
        return yaml.dump(self.to_dict(), default_flow_style=False)


@dataclass_json()
@dataclass
class ResourceSpecification:
    requests: ResourceCount
    limits: ResourceCount
