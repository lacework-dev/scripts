terraform init
terraform apply --auto-approve

bash_results=$(sh ../../bash/lw_gcp_inventory.sh -j)
pwsh_results=$(pwsh -c "../../pwsh/lw_gcp_inventory.ps1 -json 1")

if  [ $bash_results == $pwsh_results ]; then
    echo "identical results!"
    exit 0
else
    echo "results do not match"
    exit 1
fi

#terraform destroy --auto-approve