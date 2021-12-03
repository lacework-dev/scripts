### AWS System Manager Document for Lacework Agent Installation ###

This is the AWS Systems Manager document created by the [Lacework Terraform module to install agents on EC2 instances](https://docs.lacework.com/install-agent-on-aws-ec2-instances-using-terraform-and-aws-systems-manager).  Useful for 
shops that don't/can't/won't use Terraform.

To use the SSM doc:
 - Replace `default: <YOUR TOKEN>` with your [AWS Agent Access Token](https://docs.lacework.com/create-agent-access-tokens-and-download-agent-installers)
 - Create an [AWS SSM Document](https://docs.aws.amazon.com/systems-manager/latest/userguide/create-ssm-doc.html).
 - If desired, restrict the installation scope using tags, etc.  
 - Publish the AWS SSM document
 - ???
 - Profit!
