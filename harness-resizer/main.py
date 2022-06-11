#!/usr/bin/env python3

import asyncio
from asyncio import Task
import re
from typing import List, Optional, Dict, AsyncGenerator, Tuple, Iterable, Set
from collections import defaultdict

import click
from prettytable import PrettyTable
from lib.structs import ResourceCount, ResourceSpecification, ClusterType

from lib.utils import coro, generate_chunk
from lib.harness import (
    HarnessClient,
    HarnessRecommendation,
    HarnessRecommendationDetail,
)
from lib.helm_repo import HelmRepository, HelmResourcesFile


class HarnessRecommenderBot:
    harness_client: HarnessClient
    helm_repository: HelmRepository

    def __init__(
        self, harness_client: HarnessClient, helm_repository: HelmRepository
    ) -> None:
        self.harness_client = harness_client
        self.helm_repository = helm_repository

    @classmethod
    def normalize_cluster_name(cls, name: str) -> str:
        if name == "lacework-perf-enng-perf":
            return "prodperf1"
        if name == "lacework-eng-perf":
            return "prodperf1"
        if match := re.search("lacework-[^-]*-(.*)", name, re.IGNORECASE):
            return match.group(1)
        return name

    @classmethod
    def normalize_resource_name(cls, name: str) -> str:
        return name.replace("-", "_")

    def get_grafana_link(self, cluster: str, workload: str) -> str:
        return f"https://grafana.lacework.teleport.sh/d/maWI3lA7z/resource-utilization?orgId=1&refresh=1m&var-datasource={cluster}&var-namespace=default&var-workload={workload}&from=1653367120733&to=1653410320733"

    def get_branch_name(self, workload: str, cluster_type: str) -> str:
        return f"harness_resizer_{workload}_{cluster_type.lower()}"

    async def gen_all_recommendations(
        self,
        minimum_savings: Optional[int] = None,
        batch_size: int = 1000,
        resource_pattern: Optional[str] = None,
    ) -> AsyncGenerator[HarnessRecommendation, None]:
        offset = 0
        while True:
            recommendations = await self.harness_client.list_recommendations(
                limit=batch_size, minimum_savings=minimum_savings, offset=offset
            )
            offset += len(recommendations)
            if len(recommendations) == 0:
                break
            for rec in recommendations:
                if (resource_pattern is not None) and (
                    not re.match(resource_pattern, rec.resourceName)
                ):
                    click.echo(
                        f"Per resource pattern, skipping {rec.resourceName} in {rec.clusterName}"
                    )
                    continue
                yield rec

    async def get_recommendations_by_resource(
        self,
        resource_pattern: Optional[str] = None,
        cluster_pattern: Optional[str] = None,
    ) -> Task[Dict[str, List[HarnessRecommendation]]]:
        recs_by_resource = defaultdict(list)
        async for rec in self.gen_all_recommendations(
            resource_pattern=resource_pattern
        ):
            if (cluster_pattern is not None) and (
                not re.match(cluster_pattern, rec.clusterName)
            ):
                continue
            recs_by_resource[rec.resourceName].append(rec)
        return recs_by_resource

    async def gen_recommendation_details_by_resource(
        self,
        resource_pattern: Optional[str] = None,
        cluster_pattern: Optional[str] = None,
    ) -> AsyncGenerator[Tuple[str, List[HarnessRecommendationDetail]], None]:
        """
        Generates recommendation details by resource, sorted by savings
        """
        recs_by_resource = await self.get_recommendations_by_resource(
            resource_pattern=resource_pattern, cluster_pattern=cluster_pattern
        )

        def total_savings(recommendations: Iterable[HarnessRecommendation]) -> int:
            return sum((rec.monthlySaving for rec in recommendations))

        for resource, recs in sorted(
            recs_by_resource.items(), key=lambda x: total_savings(x[1]), reverse=True
        ):
            recommendation_details = await asyncio.gather(
                *[self.harness_client.get_recommendation_detail(rec) for rec in recs]
            )
            yield (resource, recommendation_details)

    def get_auto_proposed_changes(
        self,
        recommendations: List[HarnessRecommendationDetail],
        mem_buf_pct: int,
        cpu_buf_pct: int,
    ) -> Dict[ClusterType, ResourceSpecification]:
        # TODO Support multiple containers
        containers = {
            container for rec in recommendations for container in rec.containers.keys()
        }
        assert len(containers) == 1
        container = next(iter(containers))

        # Sort according to cluster type
        rec_by_cluster_type: Dict[str, List[HarnessRecommendationDetail]] = defaultdict(
            list
        )
        for rec in recommendations:
            rec_by_cluster_type[rec.get_cluster_type()].append(rec)

        def max_cpu_rec(counts: Iterable[ResourceCount]) -> str:
            counts = sorted(counts, key=lambda c: c.cpu_cores, reverse=True)
            max_cpu = next(iter(counts)).cpu_cores * (1 + (cpu_buf_pct / 100))
            return ResourceCount.pretty_cpu(max_cpu)

        def max_mem_rec(counts: Iterable[ResourceCount]) -> str:
            counts = sorted(counts, key=lambda c: c.memory_bytes, reverse=True)
            max_mem = next(iter(counts)).memory_bytes * (1 + (mem_buf_pct / 100))
            return ResourceCount.pretty_memory(max_mem)

        # Get the maximum for each cluster type
        result = {}
        for cluster_type, recs in rec_by_cluster_type.items():
            result[cluster_type] = ResourceSpecification(
                requests=ResourceCount(
                    cpu=max_cpu_rec(
                        rec.containers[container].p99.requests for rec in recs
                    ),
                    memory=max_mem_rec(
                        rec.containers[container].p99.requests for rec in recs
                    ),
                ),
                limits=ResourceCount(
                    cpu=max_cpu_rec(
                        rec.containers[container].p99.limits for rec in recs
                    ),
                    memory=max_mem_rec(
                        rec.containers[container].p99.limits for rec in recs
                    ),
                ),
            )

        return result


@click.group
@click.option(
    "--github-helm-repository",
    default="lacework-dev/helm3-platform",
    help="Name of helm repository on GitHub.",
)
@click.option(
    "--github-token",
    envvar="GITHUB_TOKEN",
    help="GitHub personal access token. See https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token",
)
@click.option(
    "--harness-api-key",
    envvar="HARNESS_API_KEY",
    help="Harness API Key. See https://docs.harness.io/article/smloyragsm-api-keys#create_an_api_key",
)
@click.option(
    "--harness-account-identifier",
    default="aZGxPkBMSKOYOweJuLcCYg",
    help="Harness account identifier.",
)
@click.pass_context
def cli(
    ctx,
    github_helm_repository: str,
    github_token: str,
    harness_api_key: str,
    harness_account_identifier: str,
):
    harness_client = HarnessClient(
        account_identifier=harness_account_identifier, api_key=harness_api_key
    )

    helm_repository = HelmRepository(
        personal_token=github_token,
        repo=github_helm_repository,
    )

    ctx.obj = HarnessRecommenderBot(
        harness_client=harness_client, helm_repository=helm_repository
    )


def get_recommendation_table(
    bot: HarnessRecommenderBot,
    container: str,
    recommendations: Iterable[HarnessRecommendationDetail],
) -> PrettyTable:
    rec_rable = PrettyTable()
    rec_rable.align = "l"
    rec_rable.field_names = [
        "Cluster Type",
        "Cluster",
        "Savings",
        "Memory Limit",
        "Memory P99 30D",
        "CPU Limit",
        "CPU P99 30D",
        "Harness",
        "Grafana",
    ]
    rec_rable.sortby = "Savings"
    rec_rable.reversesort = True
    for rec in recommendations:
        harness_link = rec.get_url(bot.harness_client.account_identifier)
        grafana_link = bot.get_grafana_link(
            HarnessRecommenderBot.normalize_cluster_name(
                rec.recommendation.clusterName
            ),
            rec.recommendation.resourceName,
        )

        rec_rable.add_row(
            [
                rec.get_cluster_type().value,
                rec.recommendation.clusterName,
                rec.recommendation.monthlySaving,
                rec.containers[container].current.limits.memory,
                rec.containers[container].p99.limits.memory,
                rec.containers[container].current.limits.cpu,
                rec.containers[container].p99.limits.cpu,
                f"[Harness]({harness_link})",
                f"[Grafana]({grafana_link})",
            ]
        )
    return rec_rable


def prompt_cluster_changes() -> Set[ClusterType]:
    clusters_to_apply_changes: Set[ClusterType] = set()
    while True:
        print("\n")
        resp = click.prompt(
            "Which changes would you like to apply? (ex. 'all', or 'us_prod eu_prod') Defaults to none",
            default="none",
            type=str,
        )
        try:
            if resp == "none":
                return set()
            if resp == "all":
                return set(ClusterType)
            return {ClusterType(choice.upper()) for choice in resp.split()}
        except Exception as e:
            click.echo(f"Unable to parse response. Got: {e}")
            pass


@cli.command()
@click.option("--minimum_savings", default=100)
@click.option("--resource_pattern", type=str, default=None)
@click.option("--cluster_pattern", type=str, default=None)
@click.option("--cpu_buf_pct", type=int, default=0)
@click.option("--mem_buf_pct", type=int, default=0)
@click.pass_obj
@coro
async def generate_prs_by_resource(
    bot: HarnessRecommenderBot,
    minimum_savings: int,
    resource_pattern: str,
    cluster_pattern: str,
    cpu_buf_pct: int,
    mem_buf_pct: int,
) -> None:
    async for resource, recommendations in bot.gen_recommendation_details_by_resource(
        resource_pattern=resource_pattern, cluster_pattern=cluster_pattern
    ):
        click.echo("\n\n")

        # We currently don't support multi-container recommendations. Skip these.
        # TODO Support multiple containers
        containers = {
            container for rec in recommendations for container in rec.containers.keys()
        }
        if len(containers) > 1:
            click.echo(
                f"Multi-container services are currently unsupported. Skipping {resource}."
            )
            continue
        container = next(iter(containers))

        # Check if the cost savings meets the threshold
        savings = sum((rec.recommendation.monthlySaving for rec in recommendations))
        if savings < minimum_savings:
            click.echo(
                f"Skipping {resource} because estimated savings of {savings} did not meet threshold."
            )
            continue

        # Create a table, displaying information about current resource consumption
        click.echo(f"== Recommendation: Resize {resource} ==")
        print("\n")
        rec_table = get_recommendation_table(
            bot=bot, container=container, recommendations=recommendations
        )
        print(
            rec_table.get_string(
                fields=[
                    "Cluster Type",
                    "Cluster",
                    "Savings",
                    "Memory Limit",
                    "Memory P99 30D",
                    "CPU Limit",
                    "CPU P99 30D",
                ]
            )
        )

        # How do you wish to proceed?
        clusters_to_apply_changes = prompt_cluster_changes()
        if not clusters_to_apply_changes:
            click.echo("No changes to apply. Skipping to the next workload.")
            continue

        # Fetch the proposed change
        proposed_changes: Dict[
            ClusterType, ResourceSpecification
        ] = bot.get_auto_proposed_changes(
            recommendations=recommendations,
            mem_buf_pct=mem_buf_pct,
            cpu_buf_pct=cpu_buf_pct,
        )

        # Apply the changes
        print("\n")
        for cluster_type in clusters_to_apply_changes:

            # Check if a PR exists
            if bot.helm_repository.branch_exists(
                bot.get_branch_name(resource, cluster_type.value)
            ):
                click.echo(f"Skipping {cluster_type} because branch exists.")
                continue

            recommendations_to_apply = [
                rec for rec in recommendations if rec.get_cluster_type() == cluster_type
            ]

            files: Dict[str, HelmResourcesFile] = {}
            default_specification = proposed_changes[cluster_type]
            for rec in recommendations_to_apply:
                specification = proposed_changes[cluster_type]

                # Print the proposed changes
                click.echo(f"\nChanges to {rec.recommendation.clusterName}:")
                proposal_table = PrettyTable()
                proposal_table.align = "l"
                proposal_table.field_names = [
                    "",
                    "Before",
                    "After",
                    "Actual",
                ]
                proposal_table.add_row(
                    [
                        "Requests:",
                        rec.containers[container].current.requests.to_yaml(),
                        specification.requests.to_yaml(),
                        rec.containers[container].p99.requests.to_yaml(),
                    ]
                )
                proposal_table.add_row(
                    [
                        "Limits:",
                        rec.containers[container].current.limits.to_yaml(),
                        specification.limits.to_yaml(),
                        rec.containers[container].p99.requests.to_yaml(),
                    ]
                )
                print(proposal_table)
                print("\n")

                # Prompt to change the specification
                if not click.confirm("Do you want to make changes to this cluster?"):
                    continue
                if not click.confirm("Do you want to make the recommended changes?"):
                    specification = ResourceSpecification(
                        limits=ResourceCount(
                            cpu=click.prompt(
                                "CPU Limit: ",
                                type=str,
                                default=str(default_specification.limits.cpu),
                            ),
                            memory=click.prompt(
                                "Memory Limit: ",
                                type=str,
                                default=str(default_specification.limits.memory),
                            ),
                        ),
                        requests=ResourceCount(
                            cpu=click.prompt(
                                "CPU Request: ",
                                type=str,
                                default=str(default_specification.requests.cpu),
                            ),
                            memory=click.prompt(
                                "Memory Request: ",
                                type=str,
                                default=str(default_specification.requests.memory),
                            ),
                        ),
                    )

                # Fetch the resource file
                cluster_name = HarnessRecommenderBot.normalize_cluster_name(
                    rec.recommendation.clusterName
                )
                resource_name = HarnessRecommenderBot.normalize_resource_name(
                    rec.recommendation.resourceName
                )
                try:
                    resource_file = bot.helm_repository.get_resource_file_for_cluster(
                        cluster=cluster_name
                    )
                    resource_file[resource_name] = specification
                    files[cluster_name] = resource_file
                    default_specification = specification
                except Exception as e:
                    click.echo(
                        f"Error when trying to fetch resource file for {cluster_name}:"
                    )
                    raise

            # Generate a PR
            pr_table = get_recommendation_table(
                bot=bot,
                container=container,
                recommendations=[
                    rec
                    for rec in recommendations_to_apply
                    if (
                        HarnessRecommenderBot.normalize_cluster_name(
                            rec.recommendation.clusterName
                        )
                        in files.keys()
                    )
                ],
            )
            pr_table.junction_char = "|"
            pr_table_str = pr_table.get_string(
                fields=["Cluster", "Savings", "Harness", "Grafana"]
            )
            markdown = [row[1:-1] for row in pr_table_str.split("\n")[1:-1]]

            pr_body = (
                "[Harness](https://docs.harness.io/article/rr85306lq8-continuous-efficiency-overview) detected that certain workloads were over-allocated memory and cpu resources. "
                + "This PR has been automatically generated to reduce resource requests and limits based on historical data. Please review the Harness dashboard for this workload "
                + "and approve/reject/alter this PR accordingly.\n\n"
                + "\n".join(markdown)
            )

            pr_res = bot.helm_repository.create_resource_change_pr(
                files=files,
                commit_message=f"perf: [harness bot] resizing {rec.recommendation.resourceName}",
                commit_branch=bot.get_branch_name(
                    rec.recommendation.resourceName, cluster_type.value
                ),
                pr_title=f"[Harness Bot] Resizing {rec.recommendation.resourceName} in {cluster_type.value.lower()}",
                pr_body=pr_body,
            )

            # Success!
            click.echo(
                f"Successfully created PR for {cluster_type.value}: {pr_res.html_url}"
            )
            click.echo("\n")


if __name__ == "__main__":
    cli()
