#!/bin/bash

# Set the initial counts to zero.
EC2_INSTANCES=1
RDS_INSTANCES=2
REDSHIFT_CLUSTERS=3
ELB_V1=4
ELB_V2=5
NAT_GATEWAYS=6


TOTAL=$(($EC2_INSTANCES + $RDS_INSTANCES + $REDSHIFT_CLUSTERS + $ELB_V1 + $ELB_V2 + $NAT_GATEWAYS))


function jsonoutput {
  echo "{"
  echo "  \"EC2 Instances\": \"$EC2_INSTANCES\","
  echo "  \"RDS Instances\": \"$RDS_INSTANCES\","
  echo "  \"Redshift Clusters\": \"$REDSHIFT_CLUSTERS\","
  echo "  \"v1 Load Balancers\": \"$ELB_V1\","
  echo "  \"v2 Load Balancers\": \"$ELB_V2\","
  echo "  \"NAT Gateways\": \"$NAT_GATEWAYS\","
  echo "  \"Total\": \"$TOTAL\""
  echo "}"
}

jsonoutput