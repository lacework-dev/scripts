package lwazure

import (
	"bytes"
	"encoding/json"
	"fmt"
	"github.com/lacework-dev/scripts/lw-inventory/helpers"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
	"os"
	"os/exec"
	"strings"
)

func Run(subscriptionsToIgnore []string, debug bool) {
	if debug {
		log.SetLevel(log.DebugLevel)
	}

	subscriptions := getSubscriptions()

	totalAgentlessCount := 0
	totalStandardAgents := 0
	totalEnterpriseAgents := 0
	totalStandardAgentLinuxCount := 0
	totalStandardAgentWindowsCount := 0
	totalEnterpriseAgentLinuxCount := 0
	totalEnterpriseAgentWindowsCount := 0

	subscriptionsInventoried := 0
	for _, subscription := range subscriptions {
		if !helpers.Contains(subscriptionsToIgnore, subscription) {
			subscriptionsInventoried++
			fmt.Println("Scanning Subscription", subscription)
			setSubscription(subscription)
			rgs := getResourceGroups()
			agentlessCount := getAgentlessCount(rgs)
			standardAgents := getStandardAgents(rgs)
			enterpriseAgents := getEntepriseAgents()

			fmt.Println("\nResources", agentlessCount)
			fmt.Println("Standard Agents", len(standardAgents))
			fmt.Println("Enterprise Agents", len(enterpriseAgents))

			standardAgentWindowsCount := 0
			standardAgentLinuxCount := 0
			for _, vm := range standardAgents {
				if vm.OS == "Linux" {
					standardAgentLinuxCount++
				} else {
					standardAgentWindowsCount++
				}
			}

			enterpriseAgentLinuxCount := 0
			enterpriseAgentWindowsCount := 0
			for _, vm := range enterpriseAgents {
				if vm.OS == "Linux" {
					enterpriseAgentLinuxCount++
				} else {
					enterpriseAgentWindowsCount++
				}
			}

			fmt.Println("\nVM OS Counts")
			fmt.Printf("Standard Linux VMs %d\n", standardAgentLinuxCount)
			fmt.Printf("Standard Windows VMs %d\n", standardAgentWindowsCount)
			fmt.Printf("Enterprise Linux VMs %d\n", enterpriseAgentLinuxCount)
			fmt.Printf("Enterprise Windows VMs %d\n\n", enterpriseAgentWindowsCount)

			totalAgentlessCount += agentlessCount
			totalStandardAgents += len(standardAgents)
			totalEnterpriseAgents += len(enterpriseAgents)

			totalStandardAgentLinuxCount += standardAgentLinuxCount
			totalStandardAgentWindowsCount += standardAgentWindowsCount
			totalEnterpriseAgentLinuxCount += enterpriseAgentLinuxCount
			totalEnterpriseAgentWindowsCount += enterpriseAgentWindowsCount
		}
	}

	fmt.Println("----------------------------------------------")
	fmt.Println("Total Resources", totalAgentlessCount)
	fmt.Println("Standard Agents", totalStandardAgents)
	fmt.Println("Enterprise Agents", totalEnterpriseAgents)

	fmt.Println("\nTotal VM OS Counts")
	fmt.Printf("Standard Linux VMs %d\n", totalStandardAgentLinuxCount)
	fmt.Printf("Standard Windows VMs %d\n", totalStandardAgentWindowsCount)
	fmt.Printf("Enterprise Linux VMs %d\n", totalEnterpriseAgentLinuxCount)
	fmt.Printf("Enterprise Windows VMs %d\n", totalEnterpriseAgentWindowsCount)

	fmt.Println("\nNumber of Azure subscriptions inventoried", subscriptionsInventoried)
	fmt.Println("----------------------------------------------")
}

type VMInfo struct {
	OS string
	ID string
}

func getStandardAgents(resourceGroups []string) []VMInfo {
	fmt.Println("Gathering Standard Agent Count")
	vmCount := getVMs()
	return vmCount
}

func getEntepriseAgents() []VMInfo {
	fmt.Println("Gathering Enterprise Agent Count")
	nodes := getAKSNodes()
	return nodes
}

func getAgentlessCount(resourceGroups []string) int {
	fmt.Println("Gathering resource count")
	resourceCount := 0
	numFuncs := 0
	channel := make(chan int)

	numFuncs += 1
	go func() {
		channel <- len(getVMs())
	}()

	numFuncs += 1
	go func() {
		channel <- getVMScaleSet()
	}()

	numFuncs += 1
	go func() {
		channel <- getSQLServers()
	}()

	numFuncs += 1
	go func() {
		channel <- getLoadBalancers()
	}()

	numFuncs += 1
	go func(rgs []string) {
		channel <- getGatewayCount(rgs)
	}(resourceGroups)

	for i := 0; i < numFuncs; i++ {
		counts := <-channel
		resourceCount += counts
	}

	return resourceCount
}

func getGatewayCount(resourceGroups []string) int {
	gatewayCount := 0
	for _, rg := range resourceGroups {
		gatewayCount += getGateways(rg)
	}
	return gatewayCount
}

func ParseIgnoreSubscriptions(cmd *cobra.Command) []string {
	subscriptionsFlag := helpers.GetFlagEnvironmentString(cmd, "ignore-subscriptions", "ignore-subscriptions", "", false)
	var subscriptions []string
	if subscriptionsFlag != "" {
		subsTemp := strings.Split(subscriptionsFlag, ",")
		for _, p := range subsTemp {
			trimmed := strings.TrimSpace(p)
			subscriptions = append(subscriptions, trimmed)
		}
	}
	return subscriptions
}

type getGatewayListResponse struct {
	Name string `json:"name"`
}

func getGateways(resourceGroup string) int {
	buf := bytes.NewBuffer([]byte{})

	cmd := exec.Command("az", "network", "vnet-gateway", "list", "-g", resourceGroup)
	cmd.Stdout = buf
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		helpers.Bail("error running az network vnet-gateway list", err)
	}

	response := []getGatewayListResponse{}
	if err := json.NewDecoder(buf).Decode(&response); err != nil {
		helpers.Bail("Error decoding vnet gateways json", err)
	}

	gateways := len(response)

	log.Debugln("gateways returned", resourceGroup, gateways)
	return gateways
}

type getVMScaleSetResponse struct {
	SKU struct {
		Capacity int `json:"capacity"`
	} `json:"sku"`
}

func getVMScaleSet() int {
	buf := bytes.NewBuffer([]byte{})

	//az group list | jq -r '.[] | .name'
	cmd := exec.Command("az", "vmss", "list")
	cmd.Stdout = buf
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		helpers.Bail("error running az vmss list", err)
	}

	response := []getVMScaleSetResponse{}
	if err := json.NewDecoder(buf).Decode(&response); err != nil {
		helpers.Bail("Error decoding scalesets json", err)
	}

	var scalesets int
	for _, ss := range response {
		scalesets += ss.SKU.Capacity
	}

	log.Debugln("scalesets returned", scalesets)
	return scalesets
}

type getAKSNodesResponse struct {
	AgentPoolProfiles []struct {
		PowerState struct {
			Code string `json:"code"`
		} `json:"powerState"`
		Count  int    `json:"count"`
		Min    int    `json:"minCount"`
		Max    int    `json:"maxCount"`
		Mode   string `json:"mode"`
		OSType string `json:"osType"`
	} `json:"agentPoolProfiles"`
}

func getAKSNodes() []VMInfo {
	buf := bytes.NewBuffer([]byte{})

	cmd := exec.Command("az", "aks", "list")
	cmd.Stdout = buf
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		helpers.Bail("error running az aks list", err)
	}

	response := []getAKSNodesResponse{}
	if err := json.NewDecoder(buf).Decode(&response); err != nil {
		helpers.Bail("Error decoding aks nodes json", err)
	}

	var nodes []VMInfo
	for _, cluster := range response {
		for _, pool := range cluster.AgentPoolProfiles {
			//both user and system pools, daemonset is installed on all nodes
			if pool.PowerState.Code == "Running" {
				nodes = append(nodes, VMInfo{OS: pool.OSType})
				//nodes += pool.Count
			}
		}
	}

	log.Debugln("aks nodes returned", nodes)
	return nodes
}

type getSQLServerListResponse struct {
	Name string `json:"name"`
}

func getSQLServers() int {
	buf := bytes.NewBuffer([]byte{})

	cmd := exec.Command("az", "sql", "server", "list")
	cmd.Stdout = buf
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		helpers.Bail("error running az sql server list", err)
	}

	response := []getSQLServerListResponse{}
	if err := json.NewDecoder(buf).Decode(&response); err != nil {
		helpers.Bail("Error decoding sqlservers json", err)
	}

	sqlservers := len(response)

	log.Debugln("sqlservers returned", sqlservers)
	return sqlservers
}

type getLoadBalancerListResponse struct {
	Name string `json:"name"`
}

func getLoadBalancers() int {
	buf := bytes.NewBuffer([]byte{})

	cmd := exec.Command("az", "network", "lb", "list")
	cmd.Stdout = buf
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		helpers.Bail("error running az network lb list", err)
	}

	response := []getLoadBalancerListResponse{}
	if err := json.NewDecoder(buf).Decode(&response); err != nil {
		helpers.Bail("Error decoding loadbalancers json", err)
	}

	loadbalancers := len(response)

	log.Debugln("loadbalancers returned", loadbalancers)
	return loadbalancers
}

type getGroupListResponse struct {
	Name string `json:"name"`
}

func getResourceGroups() []string {
	buf := bytes.NewBuffer([]byte{})

	//az group list | jq -r '.[] | .name'
	cmd := exec.Command("az", "group", "list")
	cmd.Stdout = buf
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		helpers.Bail("error running az group list", err)
	}

	response := []getGroupListResponse{}
	if err := json.NewDecoder(buf).Decode(&response); err != nil {
		helpers.Bail("Error decoding groups json", err)
	}

	var groups []string
	for _, group := range response {
		log.Debugln("Resource group name", group.Name)
		groups = append(groups, group.Name)
	}

	log.Debugln("resource groups returned", groups)
	return groups
}

func setSubscription(subscription string) bool {
	buf := bytes.NewBuffer([]byte{})

	cmd := exec.Command("az", "account", "set", "--subscription", subscription)
	cmd.Stdout = buf
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		helpers.Bail("error running az set subscription", err)
	}

	return true
}

type getVMsListResponse struct {
	StorageProfile struct {
		ImageReference struct {
			Publisher    string `json:"publisher"`
			SKU          string `json:"sku"`
			ExactVersion string `json:"exactVersion"`
		} `json:"imageReference"`
		OSDisk struct {
			OSType string `json:"osType"`
		} `json:"osDisk"`
	} `json:"storageProfile"`
	ID string `json:"vmId"`
}

func getVMs() []VMInfo {
	buf := bytes.NewBuffer([]byte{})

	cmd := exec.Command("az", "vm", "list", "-d", "--query", "[?powerState=='VM running']")
	cmd.Stdout = buf
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		helpers.Bail("error running az vm list", err)
	}

	response := []getVMsListResponse{}
	if err := json.NewDecoder(buf).Decode(&response); err != nil {
		helpers.Bail("Error decoding vms json", err)
	}

	var vms = []VMInfo{}
	for _, vm := range response {
		vms = append(vms, VMInfo{OS: vm.StorageProfile.OSDisk.OSType, ID: vm.ID})
	}

	log.Debugln("vms returned", vms)
	return vms
}

type getAccountListResponse struct {
	ID string `json:"id"`
}

func getSubscriptions() []string {
	buf := bytes.NewBuffer([]byte{})

	cmd := exec.Command("az", "account", "list")
	cmd.Stdout = buf
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		helpers.Bail("error running az account list", err)
	}

	response := []getAccountListResponse{}
	if err := json.NewDecoder(buf).Decode(&response); err != nil {
		helpers.Bail("Error decoding subscription json", err)
	}

	var subscriptions []string
	for _, account := range response {
		subscriptions = append(subscriptions, account.ID)
	}

	return subscriptions
}
