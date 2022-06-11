#!/usr/bin/env python3

from asyncio import Task
from typing import Dict, List, Optional

from functools import cache
from datetime import datetime, timedelta
from dataclasses import dataclass

from dataclasses_json import dataclass_json, Undefined

import aiohttp

from .utils import coalesce
from .structs import ResourceCount, ResourceSpecification, ClusterType


class HarnessException(Exception):
    http_status_code: str
    message: str

    def __init__(self, message: str, http_status_code=200):
        self.message = message
        self.http_status_code = http_status_code

        if not 200 <= http_status_code <= 299:
            super().__init__(
                f"Harness API returned status {http_status_code}: {message}"
            )
        else:
            super().__init__(f"Harness API error: {message}")


@dataclass_json(undefined=Undefined.EXCLUDE)
@dataclass
class HarnessRecommendation:
    id: str
    clusterName: str
    namespace: str
    resourceName: str
    monthlySaving: float
    monthlyCost: float
    resourceType: str


@dataclass
class BufferPct:
    cpu_pct: int
    memory_pct: int


@dataclass_json()
@dataclass
class HarnessRecommendationDetail_ForContainer:
    current: ResourceSpecification
    p99: ResourceSpecification

    def get_buffer_pct(self) -> int:
        """
        Returns the percentage of buffer over the P99 currently allocated.

        Ex. If current was 2GB and recommended is 1GB, buffer pct is 100%.

        This is an indicator of **how overallocated** a container is.
        """
        cur_cpu = max(
            coalesce(self.current.limits.cpu_cores),
            coalesce(self.current.requests.cpu_cores),
        )
        cur_mem = max(
            coalesce(self.current.limits.memory_bytes),
            coalesce(self.current.requests.memory_bytes),
        )
        rec_cpu = self.p99.limits.cpu_cores
        rec_mem = self.p99.limits.memory_bytes

        return BufferPct(
            cpu_pct=((cur_cpu - rec_cpu) / rec_cpu) * 100,
            memory_pct=((cur_mem - rec_mem) / rec_mem) * 100,
        )

@dataclass_json()
@dataclass
class HarnessRecommendationDetail:
    id: str
    recommendation: HarnessRecommendation
    containers: Dict[str, HarnessRecommendationDetail_ForContainer]

    def get_worst_case_buffer_pct(self) -> int:
        for_containers = [c.get_buffer_pct() for c in self.containers.values()]
        return BufferPct(
            cpu_pct=max(bp.cpu_pct for bp in for_containers),
            memory_pct=max(bp.memory_pct for bp in for_containers),
        )

    def get_url(self, account_identifier: str) -> str:
        return f"https://app.harness.io/ng/#/account/{account_identifier}/ce/recommendations/{self.id}"

    def get_cluster_type(self) -> ClusterType:
        cluster_str = self.recommendation.clusterName
        if cluster_str == "dev2-Cost-access":
            return ClusterType.OTHER
        if "euprod" in cluster_str:
            return ClusterType.EU_PROD
        if "preprod" in cluster_str:
            return ClusterType.PREPROD
        if "perf" in cluster_str:
            return ClusterType.PROD_REPLICA
        if "prod" in cluster_str:
            return ClusterType.US_PROD
        if "spork" in cluster_str:
            return ClusterType.SPORK
        if ("dev" in cluster_str) or ("autopush" in cluster_str):
            return ClusterType.DEV
        return ClusterType.OTHER

class HarnessClient:
    account_identifier: str
    api_key: str

    def __init__(self, account_identifier: str, api_key: str) -> None:
        self.account_identifier = account_identifier
        self.api_key = api_key

    @cache
    def get_headers(self) -> Dict[str, str]:
        return {"x-api-key": self.api_key}

    async def list_recommendations(
        self, limit: int = 100, offset: int = 0, minimum_savings: Optional[int] = None
    ) -> List[HarnessRecommendation]:
        params = {"accountIdentifier": self.account_identifier}
        json = {
            "resourceTypes": ["WORKLOAD"],
            "limit": limit,
            "offset": offset,
        }
        if minimum_savings is not None:
            json["minSavings"] = minimum_savings

        async with aiohttp.ClientSession(headers=self.get_headers()) as session:
            async with session.post(
                "https://app.harness.io/gateway/ccm/api/recommendation/overview/list",
                params=params,
                json=json,
            ) as resp:

                # Check HTTP Status
                if resp.status != 200:
                    raise HarnessException(
                        message=f"Unexpected response: {resp.text()}",
                        http_status_code=resp.status,
                    )

                # Check API Success
                json = await resp.json()
                if json["status"] != "SUCCESS":
                    raise HarnessException(
                        message=f"Unexpected response: {resp.text()}"
                    )

                # Parse Items
                return [
                    HarnessRecommendation.from_dict(item)
                    for item in json["data"]["items"]
                ]

    async def get_recommendation_detail(
        self,
        recommendation: HarnessRecommendation,
        data_range: Optional[timedelta] = None,
    ) -> Task[HarnessRecommendationDetail]:
        from_delta = timedelta(30) if data_range is None else data_range
        from_date = datetime.now() - from_delta

        params = {
            "accountIdentifier": self.account_identifier,
            "id": recommendation.id,
            "from": from_date.isoformat(),
        }

        async with aiohttp.ClientSession(headers=self.get_headers()) as session:
            async with session.get(
                "https://app.harness.io/gateway/ccm/api/recommendation/details/workload",
                params=params,
            ) as resp:
                # Check HTTP Status
                if resp.status != 200:
                    raise HarnessException(
                        message=f"Unexpected response: {resp.text()}",
                        http_status_code=resp.status,
                    )

                # Check API Success
                json = await resp.json()
                if json["status"] != "SUCCESS":
                    raise HarnessException(
                        message=f"Unexpected response: {resp.text()}"
                    )

                # Parse
                containers: Dict[str, HarnessRecommendationDetail_ForContainer] = {}
                for container, recommendations in json["data"][
                    "containerRecommendations"
                ].items():
                    containers[container] = HarnessRecommendationDetail_ForContainer(
                        current=ResourceSpecification(
                            requests=ResourceCount.from_dict(
                                recommendations["current"]["requests"]
                            ),
                            limits=ResourceCount.from_dict(
                                recommendations["current"]["limits"]
                            ),
                        ),
                        p99=ResourceSpecification(
                            requests=ResourceCount.from_dict(
                                recommendations["percentileBased"]["p99"]["requests"]
                            ),
                            limits=ResourceCount.from_dict(
                                recommendations["percentileBased"]["p99"]["limits"]
                            ),
                        ),
                    )
                return HarnessRecommendationDetail(
                    id=json["data"]["id"],
                    recommendation=recommendation,
                    containers=containers,
                )
