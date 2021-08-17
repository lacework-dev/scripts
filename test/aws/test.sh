#!/bin/bash

#setup RDS example
git clone https://github.com/terraform-aws-modules/terraform-aws-rds.git
cd ./terraform-aws-rds/examples/complete-mysql
terraform init
terraform apply --auto-approve
cd ../../..

# setup EC2 example
git clone https://github.com/terraform-aws-modules/terraform-aws-ec2-instance.git
cd ./terraform-aws-ec2-instance/examples/basic
terraform init
terraform apply --auto-approve
cd ../../..

#setup Redshift example
git clone https://github.com/terraform-aws-modules/terraform-aws-redshift.git
cd ./terraform-aws-redshift/examples/complete
terraform init
terraform apply --auto-approve
cd ../../..

#setup ELB example
git clone https://github.com/terraform-aws-modules/terraform-aws-elb.git
cd ./terraform-aws-elb/examples/complete
terraform init
terraform apply --auto-approve
cd ../../..

#setup NAT Gateway example -- TODO

bash_results=$(sh ../../bash/lw_aws_inventory.sh -j)
echo $bash_results

pwsh_results=$(pwsh -c "../../pwsh/lw_aws_inventory.ps1 -json 1")
echo $pwsh_results

if [[ "$bash_results" == "$pwsh_results" ]]; then
    echo "identical results between bash and pwsh!"
else
    echo "results do not match!"
fi

# cleanup
cd ./terraform-aws-rds/examples/complete-mysql
terraform destroy --auto-approve
cd ../../..
cd ./terraform-aws-ec2-instance/examples/basic
terraform destroy --auto-approve
cd ../../..
cd ./terraform-aws-redshift/examples/complete
terraform destroy --auto-approve
cd ../../..
cd ./terraform-aws-elb/examples/complete
terraform destroy --auto-approve
cd ../../..