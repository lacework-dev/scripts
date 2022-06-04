#!/usr/bin/env python3

from typing import Optional, ClassVar, Union

import re
from functools import cache
from dataclasses import dataclass

from dataclasses_json import dataclass_json
import oyaml as yaml


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
    def memory_val(self) -> Union[int, str]:
        try:
            return int(self.memory)
        except:
            return self.memory

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
    @cache
    def _memory_pattern(cls):
        return "(" + ("|".join(cls.MEMORY_UNITS.keys())) + ")"

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

    def to_yaml(self):
        return yaml.dump(self.to_dict(), default_flow_style=False)


@dataclass_json()
@dataclass
class ResourceSpecification:
    requests: ResourceCount
    limits: ResourceCount
