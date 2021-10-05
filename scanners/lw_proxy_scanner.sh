#!/bin/bash
# namespaces=$(kubectl get ns --output name)
# for ns in $namespaces: do
EXCLUDE_FILTERS="azurecr.io"
REPOSITORY="default-docker-virtual"
REGISTRY_DOMAIN="yourdomain.jfrog.io"
SCANNER="proxy"
LWPROXY="localhost"
publicimages=$(kubectl get pods --all-namespaces -o jsonpath="{.items[*].spec.containers[*].image}" | tr -s '[[:space:]]' '\n' | uniq)

export LW_SCANNER_SCAN_LIBRARY_PACKAGES=true
export LW_SCANNER_SAVE_RESULTS=true

while getopts r:l:d:s: flag
do
    case "${flag}" in
        r) REPOSITORY=${OPTARG};;
        l) LWPROXY=${OPTARG};;
        d) REGISTRY_DOMAIN=${OPTARG};;
        s) SCANNER=${OPTARG};;
    esac
done

for image in $publicimages:
do
    #parse out the image name and the version from the image data retrieved via kubectl
    #Example: lw_proxy_scanner.sh -s proxy -l laceworkProxyScannerHost -r myRepoInJFrog -d mydomain.jfrog.io
    IN=$image
    arrIN=(${IN//:/ })
    name=${arrIN[0]}
    tag=${arrIN[1]}    

    if [[ $tag == "" ]]; then
        tag="latest"
    fi

    echo +++++Scanning image $name with label $tag
    commandstr="curl --location --request POST '$LWPROXY:8080/v1/scan' --header 'Content-Type: application/json' --data-raw '{\"registry\": \"$REGISTRY_DOMAIN\",\"image_name\": \"$REPOSITORY/$name\",\"tag\": \"$tag\"}'"

    if [[ $SCANNER == "inline" ]]; then
        commandstr="lw-scanner evaluate ${name} ${tag}"
    fi
    
    echo +++++executing: $commandstr
    eval $commandstr
done
