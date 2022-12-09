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

	var vmOSCounts OSCounts
	var totalVCPUs int32
	subscriptionsInventoried := 0
	for _, subscription := range subscriptions {
		if !helpers.Contains(subscriptionsToIgnore, subscription) {
			var subscriptionVMOSCounts OSCounts
			subscriptionsInventoried++
			fmt.Println("Scanning Subscription", subscription)
			setSubscription(subscription)
			standardAgents := getStandardAgents()
			enterpriseAgents := getEntepriseAgents()

			var locations []string
			for _, vm := range standardAgents {
				if !helpers.Contains(locations, vm.Location) {
					locations = append(locations, vm.Location)
				}
			}

			for _, vm := range enterpriseAgents {
				if !helpers.Contains(locations, vm.Location) {
					locations = append(locations, vm.Location)
				}
			}

			var vmSizes []MachineType
			for _, location := range locations {
				vmSizes = getVMSizesByLocation(location)
			}

			var standardAgentsWithvCPU []VMInfo
			for _, vm := range standardAgents {
				for _, size := range vmSizes {
					if vm.Location == size.Location && vm.VMSize == size.Name {
						vm.vCPUs = size.vCPUs
						totalVCPUs += size.vCPUs
						standardAgentsWithvCPU = append(standardAgentsWithvCPU, vm)
					}
				}
			}

			var enterpriseAgentsWithvCPU []VMInfo
			for _, vm := range enterpriseAgents {
				for _, size := range vmSizes {
					if vm.Location == size.Location && vm.VMSize == size.Name {
						vm.vCPUs = size.vCPUs
						totalVCPUs += size.vCPUs
						enterpriseAgentsWithvCPU = append(enterpriseAgentsWithvCPU, vm)
					}
				}
			}

			fmt.Println("Standard Agents", len(standardAgentsWithvCPU))
			fmt.Println("Enterprise Agents", len(enterpriseAgentsWithvCPU))

			for _, vm := range standardAgentsWithvCPU {
				if vm.OS == "Linux" {
					subscriptionVMOSCounts.Linux++
				} else {
					subscriptionVMOSCounts.Windows++
				}
			}

			for _, vm := range enterpriseAgentsWithvCPU {
				if vm.OS == "Linux" {
					subscriptionVMOSCounts.Linux++
				} else {
					subscriptionVMOSCounts.Windows++
				}
			}

			fmt.Println("\nVM OS Counts")
			fmt.Printf("Linux VMs %d\n", vmOSCounts.Linux)
			fmt.Printf("Windows VMs %d\n", vmOSCounts.Windows)

			vmOSCounts.Linux += subscriptionVMOSCounts.Linux
			vmOSCounts.Windows += subscriptionVMOSCounts.Windows

		}
	}

	fmt.Println("----------------------------------------------")
	fmt.Println("Total vCPUs", totalVCPUs)
	fmt.Println("\nTotal VM OS Counts")
	fmt.Printf("Linux VMs %d\n", vmOSCounts.Linux)
	fmt.Printf("Windows VMs %d\n", vmOSCounts.Windows)

	fmt.Println("\nNumber of Azure subscriptions inventoried", subscriptionsInventoried)
	fmt.Println("----------------------------------------------")
}

type VMInfo struct {
	OS       string
	ID       string
	Location string
	vCPUs    int32
	VMSize   string
}

type OSCounts struct {
	Windows int
	Linux   int
}

type MachineType struct {
	vCPUs    int32
	Name     string
	Location string
}

type getVMSizesResponse struct {
	Name  string `json:"name"`
	Cores int32  `json:"numberOfCores"`
}

func getVMSizesByLocation(location string) []MachineType {
	buf := bytes.NewBuffer([]byte{})

	cmd := exec.Command("az", "vm", "list-sizes", "-l", location)
	cmd.Stdout = buf
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		helpers.Bail("error running az vm list-sizes", err)
	}

	response := []getVMSizesResponse{}
	if err := json.NewDecoder(buf).Decode(&response); err != nil {
		helpers.Bail("Error decoding vm size json", err)
	}

	var machineTypes []MachineType
	for _, size := range response {
		machineTypes = append(machineTypes, MachineType{
			vCPUs:    size.Cores,
			Name:     size.Name,
			Location: location,
		})
	}

	return machineTypes
}

func getStandardAgents() []VMInfo {
	fmt.Println("Gathering Standard Agent Count")
	vmCount := getVMs()
	return vmCount
}

func getEntepriseAgents() []VMInfo {
	fmt.Println("Gathering Enterprise Agent Count")
	nodes := getAKSNodes()
	return nodes
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
		VMSize string `json:"vmSize"`
	} `json:"agentPoolProfiles"`
	Location string `json:"location"`
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
				nodes = append(nodes, VMInfo{OS: pool.OSType, Location: cluster.Location, VMSize: pool.VMSize})
			}
		}
	}

	log.Debugln("aks nodes returned", nodes)
	return nodes
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
	HardwareProfile struct {
		VMSize string `json:"vmSize"`
	} `json:"hardwareProfile"`
	ID       string `json:"vmId"`
	Location string `json:"location"`
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
		vms = append(vms, VMInfo{OS: vm.StorageProfile.OSDisk.OSType, ID: vm.ID, Location: vm.Location, VMSize: vm.HardwareProfile.VMSize})
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
