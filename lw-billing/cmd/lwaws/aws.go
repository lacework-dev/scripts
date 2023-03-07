package lwaws

import (
	"encoding/csv"
	"fmt"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
	"io"
	"lw-billing/helpers"
	"os"
	"strconv"
	"strings"
)

func Run(billingCSV string, debug bool) {
	if debug {
		log.SetLevel(log.DebugLevel)
	}

	instanceTypes := loadAWSInstanceTypes()
	instances := getVMVCPU(billingCSV, instanceTypes)
	lambdas := getLambdaVCPU(billingCSV)
	getFargateVCPU(billingCSV)

	vmvcpus := countUpVMs(instances)
	println("VM vCPUS:", vmvcpus)

	lambdavcpus := countUpLambdas(lambdas)
	println("Lambda vCPUS:", lambdavcpus)

	println("Total AWS vCPUS:", vmvcpus+lambdavcpus)
}

const (
	hoursPerMonth   = 720
	recordID        = 4
	linkedAccountID = 2
	usageType       = 15
	usageQty        = 21
	productCode     = 12
	payerAccountID  = 1
)

type InstanceType struct {
	Name string
	VCPU int
}

type BillingInstance struct {
	Name      string
	Hours     float64
	AccountID string
	VCPU      int
}

func check(e error) {
	if e != nil {
		panic(e)
	}
}

func countUpVMs(instances map[string][]BillingInstance) int {
	var totalVCPUs float64

	for account, instance := range instances {
		var accountvCPUs float64
		for _, it := range instance {
			numInstances := it.Hours / hoursPerMonth
			vcpus := numInstances * float64(it.VCPU)
			accountvCPUs += vcpus
			totalVCPUs += vcpus
		}
		fmt.Printf("Account %s - VM vCPUs: %.2f\n", account, accountvCPUs)
	}

	return int(totalVCPUs)
}

func countUpLambdas(instances map[string]float64) int {
	var totalVCPUs float64

	for account, vcpus := range instances {
		var accountvCPUs float64
		accountvCPUs += vcpus
		totalVCPUs += vcpus
		fmt.Printf("Account %s - Lambda vCPUs: %.2f\n", account, accountvCPUs)
	}
	return int(totalVCPUs)
}

func getVMVCPU(filename string, instanceTypes []InstanceType) map[string][]BillingInstance {
	readFile, err := os.Open(filename)
	check(err)
	defer readFile.Close()

	r := csv.NewReader(readFile)

	instances := make(map[string][]BillingInstance)
	for {
		row, err := r.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			log.Fatal(err)
		}

		for _, instanceType := range instanceTypes {
			if !strings.Contains(row[recordID], "AccountTotal") && row[linkedAccountID] != "" && strings.Contains(row[usageType], instanceType.Name) {
				hours, _ := strconv.ParseFloat(row[usageQty], 64)
				accountID := row[linkedAccountID]
				if accountID == "" {
					accountID = row[payerAccountID]
				}
				instances[accountID] = append(instances[accountID], BillingInstance{
					Name:      instanceType.Name,
					AccountID: accountID,
					Hours:     hours,
					VCPU:      instanceType.VCPU,
				})
			}
		}
	}

	return instances
}

func getLambdaVCPU(filename string) map[string]float64 {
	readFile, err := os.Open(filename)
	check(err)
	defer readFile.Close()

	r := csv.NewReader(readFile)

	lambdas := make(map[string]float64)
	for {
		row, err := r.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			log.Fatal(err)
		}

		if !strings.Contains(row[recordID], "AccountTotal") && row[linkedAccountID] != "" && row[productCode] == "AWSLambda" && strings.Contains(row[usageType], "Lambda-GB-Second") {
			accountID := row[linkedAccountID]
			if accountID == "" {
				accountID = row[payerAccountID]
			}
			seconds, _ := strconv.ParseFloat(row[usageQty], 64)

			lambdas[accountID] += seconds / 3600 / 1024 / hoursPerMonth
		}
	}

	return lambdas
}

func getFargateVCPU(filename string) map[string]float64 {
	readFile, err := os.Open(filename)
	check(err)
	defer readFile.Close()

	r := csv.NewReader(readFile)

	lambdas := make(map[string]float64)
	for {
		row, err := r.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			log.Fatal(err)
		}

		if !strings.Contains(row[recordID], "AccountTotal") && row[linkedAccountID] != "" && row[productCode] == "AmazonECS" && strings.Contains(row[usageType], "Fargate-vCPU-Hours:perCPU") {
			accountID := row[linkedAccountID]
			if accountID == "" {
				accountID = row[payerAccountID]
			}
			hours, _ := strconv.ParseFloat(row[usageQty], 64)
			fmt.Printf("Fargate %s, %.2f\n", accountID, hours)
		}
	}

	return lambdas
}

func loadAWSInstanceTypes() []InstanceType {
	var instanceTypes []InstanceType
	for instance, vcpu := range helpers.Aws_instances {
		instanceTypes = append(instanceTypes, InstanceType{
			Name: instance,
			VCPU: vcpu,
		})
	}

	return instanceTypes
}

func ParseBilling(cmd *cobra.Command) string {
	billingCSV := helpers.GetFlagEnvironmentString(cmd, "billing", "billing", "Missing Billing CSV", true)
	return billingCSV
}
