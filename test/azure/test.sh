terraform init
terraform apply --auto-approve

bash_results=$(sh ../../bash/lw_azure_inventory.sh) #bash doesn't have json support..yet
pwsh_results=$(pwsh -c "../../pwsh/lw_azure_inventory.ps1")

if [[ "$bash_results" == "$pwsh_results" ]]; then
    echo "identical results between bash and pwsh!"
    exit 0
else
    echo "results do not match!"
    exit 1
fi

#terraform destroy --auto-approve