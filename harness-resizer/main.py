#!/usr/bin/env python3

import asyncio
import re
from typing import List, Optional

import click
from prettytable import PrettyTable
from lib.structs import ResourceCount, ResourceSpecification

from lib.utils import coro, generate_chunk
from lib.harness import HarnessClient, HarnessRecommendationDetail
from lib.helm_repo import HelmRepository


class HarnessRecommenderBot:
    harness_client: HarnessClient
    helm_repository: HelmRepository

    def __init__(
        self, harness_client: HarnessClient, helm_repository: HelmRepository
    ) -> None:
        self.harness_client = harness_client
        self.helm_repository = helm_repository

    async def get_recommendations(
        self, limit: int, offset: int, minimum_savings: int
    ) -> List[HarnessRecommendationDetail]:
        # Get list of recommendations matching criteria
        recommendations = await self.harness_client.list_recommendations(
            limit=limit, minimum_savings=minimum_savings, offset=offset
        )

        # Fetch the details of these recommendations (in chunks)
        recommendation_details = []
        chunks = generate_chunk(recommendations, 10)
        for chunk in chunks:
            recommendation_details += await asyncio.gather(
                *[self.harness_client.get_recommendation_detail(rec) for rec in chunk]
            )

        return recommendation_details

    async def gen_recommendations(
        self,
        minimum_savings: int,
        batch_size: int = 10,
        cluster_pattern: Optional[str] = None,
        resource_pattern: Optional[str] = None,
    ):
        offset = 0
        while True:
            recs = await self.get_recommendations(
                limit=batch_size, offset=offset, minimum_savings=minimum_savings
            )
            offset += batch_size
            if len(recs) == 0:
                raise StopAsyncIteration()
            for rec in recs:
                if (cluster_pattern is not None) and (
                    not re.match(cluster_pattern, rec.recommendation.clusterName)
                ):
                    click.echo(
                        f"Per cluster pattern, skipping {rec.recommendation.resourceName} in {rec.recommendation.clusterName}"
                    )
                    continue
                if (resource_pattern is not None) and (
                    not re.match(resource_pattern, rec.recommendation.resourceName)
                ):
                    click.echo(
                        f"Per resource pattern, skipping {rec.recommendation.resourceName} in {rec.recommendation.clusterName}"
                    )
                    continue
                yield rec

    def get_grafana_link(self, cluster: str, workload: str) -> str:
        return f"https://grafana.lacework.teleport.sh/d/maWI3lA7z/resource-utilization?orgId=1&refresh=1m&var-datasource={cluster}&var-namespace=default&var-workload={workload}&from=1653367120733&to=1653410320733"

    def get_pr_body(
        self, rec: HarnessRecommendationDetail, normalized_cluster: str, workload: str
    ) -> str:
        return (
            "[Harness](https://docs.harness.io/article/rr85306lq8-continuous-efficiency-overview) detected that certain workloads were over-allocated memory and cpu resources. "
            + "This PR has been automatically generated to reduce resource requests and limits based on historical data. Please review the Harness dashboard for this workload "
            + "and approve/reject/alter this PR accordingly.\n\n"
            + f"* [Harness Dashboard]({rec.get_url(self.harness_client.account_identifier)})\n"
            + f"* [Grafana Dashboard]({self.get_grafana_link(normalized_cluster, workload)})\n"
            + "* Ask questions in #harness-resizer on Slack\n"
        )


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


@cli.command()
@click.option("--limit", default=10)
@click.option("--offset", default=0)
@click.option("--minimum_savings", default=0)
@click.pass_obj
@coro
async def list_improvements(
    bot: HarnessRecommenderBot, limit: int, offset: int, minimum_savings: int
):
    recommendation_details = await bot.get_recommendations(
        limit=limit, offset=offset, minimum_savings=minimum_savings
    )

    # Print the results in a pretty table
    table = PrettyTable()
    table.align = "l"
    table.field_names = [
        "Cluster",
        "Service",
        "Monthly Cost Savings",
        "Current Memory Buffer %",
        "Current CPU Buffer %",
    ]
    table.add_rows(
        [
            [
                rec.recommendation.clusterName,
                rec.recommendation.resourceName,
                f"${rec.recommendation.monthlySaving:,.2f}",
                f"{rec.get_worst_case_buffer_pct().memory_pct:,.1f} %",
                f"{rec.get_worst_case_buffer_pct().cpu_pct:,.1f} %",
            ]
            for rec in recommendation_details
        ]
    )
    print(table)


def normalize_cluster_name(name: str) -> str:
    if match := re.search("lacework-prod-(.*)", name, re.IGNORECASE):
        return match.group(1)
    return name


def normalize_resource_name(name: str) -> str:
    return name.replace("-", "_")


@cli.command()
@click.option("--minimum_savings", default=100)
@click.option("--resource_pattern", type=str, default=None)
@click.option("--cluster_pattern", type=str, default=None)
@click.pass_obj
@coro
async def generate_prs_interactive(
    bot: HarnessRecommenderBot,
    minimum_savings: int,
    cluster_pattern: str,
    resource_pattern: str,
):
    async for rec in bot.gen_recommendations(
        minimum_savings=minimum_savings,
        cluster_pattern=cluster_pattern,
        resource_pattern=resource_pattern,
    ):
        # TODO Handle multiple containers
        if len(rec.containers) > 1:
            continue
        container = next(iter(rec.containers.values()))

        # Check if a PR exists
        if bot.helm_repository.branch_exists(rec.get_head_branch()):
            continue

        # Create a table, displaying information about the proposed change
        table = PrettyTable()
        table.align = "l"
        table.header = False
        table.add_row(["Cluster: ", rec.recommendation.clusterName])
        table.add_row(["Monthly Cost Savings: ", rec.recommendation.resourceName])
        table.add_row(
            [
                "Current Memory Buffer %: ",
                f"{rec.get_worst_case_buffer_pct().memory_pct:,.1f} %",
            ]
        )
        table.add_row(
            [
                "Current CPU Buffer %: ",
                f"{rec.get_worst_case_buffer_pct().cpu_pct:,.1f} %",
            ]
        )
        table.add_row(
            ["Harness Dashboard: ", rec.get_url(bot.harness_client.account_identifier)]
        )
        print(table)

        # Prompt user if they want to create a PR
        if not click.confirm("\nDo you want to create a PR?", default=False):
            continue

        # Create a table, displaying information about recommended change
        table = PrettyTable()
        table.align = "l"
        table.field_names = ["", "Before", "After"]
        table.add_row(
            [
                "Limits: ",
                container.current.limits.to_yaml(),
                container.p99.limits.to_yaml(),
            ]
        )
        table.add_row(
            [
                "Requests: ",
                container.current.requests.to_yaml(),
                container.p99.requests.to_yaml(),
            ]
        )
        click.echo("== Recommended Changes ==")
        print(table)

        cluster_name = normalize_cluster_name(rec.recommendation.clusterName)
        resource_name = normalize_resource_name(rec.recommendation.resourceName)

        # Set the values
        resource_file = bot.helm_repository.get_resource_file_for_cluster(
            cluster=cluster_name
        )
        container_resources = resource_file[resource_name]
        if click.confirm(
            "\nDo you want to propose the recommended changes?", default=True
        ):
            container_resources[container] = container.p99
        elif click.confirm("\nDo you want to propose custom changes?", default=True):
            resource_file[resource_name] = ResourceSpecification(
                limits=ResourceCount(
                    cpu=click.prompt(
                        "CPU Limit: ", default=container.current.limits.cpu
                    ),
                    memory=click.prompt(
                        "Memory Limit: ", default=container.current.limits.memory
                    ),
                ),
                requests=ResourceCount(
                    cpu=click.prompt(
                        "CPU Request: ", default=container.current.requests.cpu
                    ),
                    memory=click.prompt(
                        "Memory Request: ", default=container.current.requests.memory
                    ),
                ),
            )
        else:
            continue

        # Generate a PR
        pr_res = bot.helm_repository.create_resource_change_pr(
            cluster=cluster_name,
            file=resource_file,
            commit_message=f"perf: [harness bot] resizing {rec.recommendation.resourceName} in {cluster_name}",
            commit_branch=rec.get_head_branch(),
            pr_title=f"[Harness Bot] Resizing {rec.recommendation.resourceName} in {cluster_name}",
            pr_body=bot.get_pr_body(rec, cluster_name, rec.recommendation.resourceName),
        )

        # Success!
        click.echo(f"\nSuccessfully created PR!")
        click.echo(pr_res.html_url)
        click.echo("\n\n")


if __name__ == "__main__":
    cli()
