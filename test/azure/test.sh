terraform init
terraform apply --auto-approve

bash_results=$(sh ../../bash/lw_azure_inventory.sh) #bash doesn't have json support..yet
pwsh_results=$(pwsh -c "../../pwsh/lw_azure_inventory.ps1")

if [[ "$bash_results" == "$pwsh_results" ]]; then
    echo "identical results between bash and pwsh!"
else
    echo "results do not match!"
fi

terraform destroy --auto-approve