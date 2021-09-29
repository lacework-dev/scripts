#!/bin/bash
# namespaces=$(kubectl get ns --output name)
# for ns in $namespaces: do
EXCLUDE_FILTERS="azurecr.io"
JFROG_REGISTRY="default-docker-virtual"
LWPROXY="localhost"
publicimages=$(kubectl describe deployments -A | grep Image: | sed "s/Image:[ \t]*//g" | grep -v $EXCLUDE_FILTERS)
export LW_SCANNER_SCAN_LIBRARY_PACKAGES=true
export LW_SCANNER_SAVE_RESULTS=true

while getopts r:lwp: flag
do
    case "${flag}" in
        r) JFROG_REGISTRY=${OPTARG};;
        lwp) LWPROXY=${OPTARG};;
    esac
done

for image in $publicimages:
do
#  ~ lw-scanner evaluate bitnami/mariadb 10.5.10-debian-10-r18
    name=$(echo $image | cut -d ':' -f 1)
    tag=$(echo $image | cut -d ':' -f 2)
    echo +++++Commencing Proxy scan of images in : $JFROG_REGISTRY
    #docker pull $name:$tag
    echo +++++
    echo +++++Scanning image $name with label $tag
    echo +++++ LWPROXY: $LWPROXY and JFROG_REGISTRY: $JFROG_REGISTRY
    commandstr="curl --location --request POST '${LWPROXY}:9080/v1/scan' --header 'Content-Type: application/json' --data-raw '{\"registry\": \"${JFROG_REGISTRY}\",\"$image\": \"${JFROG_REGISTRY}/$image\",\"tag\": \"$tag\"}'"
    echo +++++executing: $commandstr
    eval $commandstr
done
