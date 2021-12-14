# Use-case: scanning a Docker v2 registry that cannot do auto-polling https://docs.lacework.com/integrate-a-docker-v2-registry#container-registry-support
# First, integrate a Container Registry of Docker v2 kind, no need for registry notifications, maybe enable Non-OS Package support
# Then go to Lacework > Resources >  Containers >  Container Image Information and download as CSV
# The first two columns of the CSV are "Repository"	"Image Tag". The 11th column is "Eval Guid"
# We'll call the Lacework API to perform a on-demand scan of all containers from a known Docker v2 repository previously found in the system but where Auto-Polling wasn't available (Nexus, Jfrog, etc).
# For future containers, ideally the inline scanner will be used to scan before they are pushed to the repository

# PRE-REQUISITES: Install and configure the Lacework CLI https://docs.lacework.com/cli/

from typing import List
from dataclasses import dataclass
from sys import argv
import subprocess
import csv


@dataclass
class DockerImage:
    registry: str
    repository: str
    tag: str


def _get_docker_images(customer_registry_name, reader) -> List[DockerImage]:
    supported_entries = []

    for entry in reader:
        entry_details = entry[0].split('/', 1)
        registry_name = entry_details[0]

        if registry_name != customer_registry_name:
            continue

        repository_name = entry_details[1]
        tag = entry[1]

        docker_image = DockerImage(registry_name, repository_name, tag)
        supported_entries.append(docker_image)

    return supported_entries


def _get_supported_images(filename, customer_registry_name) -> List[DockerImage]:
    with open(filename, 'r') as file:
        reader = csv.reader(file)
        next(reader)

        supported_images = _get_docker_images(customer_registry_name, reader)

    return supported_images


def run_scan(profile_name, supported_images) -> None:
    for image in supported_images:
        registry = image.registry
        repository = image.repository
        tag = image.tag

        command = f'lacework vulnerability -p {profile_name} container scan {registry} {repository} {tag}'
        print(f'Running: {command}')
        split_command = command.split()
        output = subprocess.run(split_command, check=True, capture_output=True, text=True).stdout
        print(output)


def main() -> None:
    profile_name = argv[1]
    filename = argv[2]
    customer_registry_name = argv[3]

    supported_images = _get_supported_images(filename, customer_registry_name)
    run_scan(profile_name, supported_images)


if __name__ == '__main__':
    main()
