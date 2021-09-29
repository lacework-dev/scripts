#!/bin/bash
# namespaces=$(kubectl get ns --output name)
# for ns in $namespaces: do
EXCLUDE_FILTERS="azurecr.io"
REPOSITORY="default-docker-virtual"
REGISTRY_DOMAIN="yourjfrogtenant.jfrog.io"
LWPROXY="localhost"
publicimages=$(kubectl describe deployments -A | grep Image: | sed "s/Image:[ \t]*//g" | grep -v $EXCLUDE_FILTERS)
export LW_SCANNER_SCAN_LIBRARY_PACKAGES=true
export LW_SCANNER_SAVE_RESULTS=true

while getopts r:lwp: flag
do
    case "${flag}" in
        r) REPOSITORY=${OPTARG};;
        lwp) LWPROXY=${OPTARG};;
        d) REGISTRY_DOMAIN=${OPTARG};;
    esac
done

echo +++++Commencing Proxy scan of images in : $REPOSITORY

for image in $publicimages:
do
#  ~ lw-scanner evaluate bitnami/mariadb 10.5.10-debian-10-r18
    
    #parse out the image name and the version from the image data retrieved via kubectl
    IN=$image
    arrIN=(${IN//:/ })
    name=${arrIN[0]}
    tag=${arrIN[1]}    

    echo +++++Scanning image $name with label $tag
    echo +++++ LWPROXY: $LWPROXY and REPOSITORY: $REPOSITORY
    
    commandstr="curl --location --request POST '${LWPROXY}:8080/v1/scan' --header 'Content-Type: application/json' --data-raw '{\"registry\": \"${REGISTRY_DOMAIN}\",\"image_name\": \"$REPOSITORY/$name\",\"tag\": \"$tag\"}'"
    echo +++++executing: $commandstr
    
    eval $commandstr
done

