#! /bin/bash
# Pre-requisits install the aws cli  - instructions are here https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-install.html
# Set up aws credentials as per https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html
# install and add jq to your path as per https://github.com/stedolan/jq/wiki/Installation
# Please amend the region and profile to suit your environment. If using no profile, please set to "default"
# Region is a required field

profile=default
region=eu-west-1
his=3600
end_time=$(date +%s)
start_time=$(($end_time - $his))
temp_json_file=temp.json
final_json_file=final.json
start_time_hr=$(date -r $start_time)
end_time_hr=$(date -r $end_time)

#
# End of user parameters
#

touch results
touch files.txt

for f in $(aws lambda list-functions --output json --no-paginate | jq -r '.Functions[].FunctionName')
do
  echo $f".json" >> files.txt
done

for f in $(aws lambda list-functions --output json --no-paginate | jq -r '.Functions[].FunctionName')
do
touch $f.json
cat << EOF >> $f.json
"[
   {
      "Id": "m2",
    	"MetricStat": {
    		"Metric": {
    			"Namespace": "AWS/Lambda",
    			"MetricName": "Invocations",
    			"Dimensions": [{
    				"Name": "FunctionName",
    				"Value": "'$f'"
    			}]
    		},
    		"Period": 3600,
    		"Stat": "Sum"
    	},
    	"ReturnData": true
    }
]"
EOF
cat $f.json
done

for l in $(aws lambda list-functions --output json --no-paginate | jq -r '.Functions[].FunctionName')
do
aws cloudwatch get-metric-data --metric-data-queries file://$l.json --start-time $start_time --end-time $end_time --region $region --profile $profile >> results
done

for f in $(cat files.txt)
do
rm -rf $f
done
rm files.txt
mv results results.json

count=$(cat results.json | jq -r '.MetricDataResults[].Values' | awk '{sum+=$0} END{print sum}')
clear
echo ""
echo ""
echo "The script has counted a total of "$count "lambda invocations."
echo "Between $start_time_hr and $end_time_hr."
echo ""
echo "Thanks for using the Lacework AWS serverless call counter!"
echo ""
echo ""
