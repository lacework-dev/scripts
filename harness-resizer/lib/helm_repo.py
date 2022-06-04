#!/usr/bin/env python3

from typing import Any, List
from functools import cache

import oyaml as yaml
from github import Github
from github.Repository import Repository
from github.ContentFile import ContentFile
from github.GithubException import GithubException

from .structs import ResourceCount, ResourceSpecification


class ResourceFileException(Exception):
    def __init__(self, message: str) -> None:
        super().__init__(message)


class HelmResourcesFile:
    _original_file: ContentFile
    _dict: Any

    def __init__(self, file: ContentFile) -> None:
        self._original_file = file
        self._dict = yaml.safe_load(file.decoded_content)
        if "resources" not in self._dict:
            raise ResourceFileException("Missing key 'resources'")

    def __getitem__(self, service: str) -> ResourceSpecification:
        if service not in self._dict["resources"]:
            raise ResourceFileException(f"Missing key 'resources.{service}'")
        resource_dict = self._dict["resources"][service]
        return ResourceSpecification(
            requests=ResourceCount(
                cpu=resource_dict["resourcesRequests"].get("cpu", None),
                memory=resource_dict["resourcesRequests"].get("memory", None),
            ),
            limits=ResourceCount(
                cpu=resource_dict["resourcesLimits"].get("cpu", None),
                memory=resource_dict["resourcesLimits"].get("memory", None),
            ),
        )

    def __setitem__(self, service: str, resources: ResourceSpecification) -> None:
        if service not in self._dict["resources"]:
            raise ResourceFileException(f"Missing key 'resources.{service}'")
        if resources.requests.cpu:
            self._dict["resources"][service]["resourcesRequests"][
                "cpu"
            ] = resources.requests.cpu_val
        if resources.requests.memory:
            self._dict["resources"][service]["resourcesRequests"][
                "memory"
            ] = resources.requests.memory_val
        if resources.limits.cpu:
            self._dict["resources"][service]["resourcesLimits"][
                "cpu"
            ] = resources.limits.cpu_val
        if resources.limits.memory:
            self._dict["resources"][service]["resourcesLimits"][
                "memory"
            ] = resources.limits.memory_val

    @property
    def original_sha(self) -> str:
        return self._original_file.sha

    def to_yaml(self) -> str:
        return yaml.dump(self._dict, default_flow_style=False)


class HelmRepository:
    github: Github
    repo: Repository

    def __init__(self, personal_token: str, repo: str) -> None:
        self.github = Github(personal_token)
        self.repo = self.github.get_repo(repo)

    @cache
    def get_cluster_resources_path(self, cluster: str) -> str:
        return f"config/{cluster}/resources.yaml"

    @cache
    def get_resource_file_for_cluster(self, cluster: str) -> HelmResourcesFile:
        file = self.repo.get_contents(self.get_cluster_resources_path(cluster))
        return HelmResourcesFile(file)

    def create_resource_change_pr(
        self,
        cluster: str,
        file: HelmResourcesFile,
        commit_message: str,
        commit_branch: str,
        pr_title: str,
        pr_body: str,
        source_branch: str = "main",
    ) -> None:
        assert "harness_" in commit_branch, "always commit to a safe branch"

        # Create a new branch
        source_branch = self.repo.get_branch("main")
        self.repo.create_git_ref(
            ref=f"refs/heads/{commit_branch}", sha=source_branch.commit.sha
        )

        # Modify a file in that branch
        update_file_res = self.repo.update_file(
            path=self.get_cluster_resources_path(cluster),
            message=commit_message,
            content=file.to_yaml(),
            sha=file.original_sha,
            branch=commit_branch,
        )

        # Create a Pull Request
        create_pr_res = self.repo.create_pull(
            title=pr_title,
            body=pr_body,
            base="main",
            head=commit_branch,
            draft=False,
            maintainer_can_modify=True,
        )

        return create_pr_res

    def branch_exists(self, commit_branch: str) -> bool:
        assert "harness_" in commit_branch, "always commit to a safe branch"
        try:
            self.repo.get_branch(branch=commit_branch)
            return True
        except GithubException as ex:
            if ex.status == 404:
                return False
            raise
