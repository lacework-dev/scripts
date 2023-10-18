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
	"strconv"
	"strings"
)
gi status
var defaultIncludedLocations = []string{
	"eastus",
	"eastus2",
	"westus",
	"centralus",
	"northcentralus",
	"southcentralus",
	"northeurope",
	"westeurope",
	"eastasia",
	"southeastasia",
	"japaneast",
	"japanwest",
	"australiaeast",
	"australiasoutheast",
	"australiacentral",
	"brazilsouth",
	"southindia",
	"centralindia",
	"westindia",
	"canadacentral",
	"canadaeast",
	"westus2",
	"westcentralus",
	"uksouth",
	"ukwest",
	"koreacentral",
	"koreasouth",
	"francecentral",
	"southafricanorth",
	"uaenorth",
	"switzerlandnorth",
	"germanywestcentral",
	"norwayeast",
	"jioindiawest",
	"westus3",
	"swedencentral",
	"qatarcentral",
	"polandcentral",
	"italynorth",
	"israelcentral",
}

func Run(subscriptionsToIgnore []string, debug bool, useQuotas bool, includeLocations []string, excludeLocations []string) {
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

			valid := setSubscription(subscription)
			if !valid {
				continue
			}

			if useQuotas {
				//locations := getLocations()
				locations := defaultIncludedLocations

				if includeLocations != nil {
					locations = includeLocations
				}

				for _, l := range locations {
					if helpers.Contains(excludeLocations, l) {
						continue
					}

					totalVCPUs += getUsage(l)
				}
			} else {
				standardAgents := getStandardAgents()
				enterpriseAgents := getEntepriseAgents()
				scaleSets := getVMScaleSet()
				rgs := getResourceGroups()
				for _, group := range rgs {
					getContainers(group)
				}

				var locations []string
				for _, vm := range standardAgents {
					if !helpers.Contains(locations, vm.Location) {
						locations = append(locations, vm.Location)
					}
				}

				for _, vm := range scaleSets {
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
				var vmvCPU int32
				for _, vm := range standardAgents {
					for _, size := range vmSizes {
						if vm.Location == size.Location && vm.VMSize == size.Name {
							vm.vCPUs = size.vCPUs
							vmvCPU += vm.vCPUs
							totalVCPUs += size.vCPUs
							standardAgentsWithvCPU = append(standardAgentsWithvCPU, vm)
						}
					}
				}

				var scaleSetsWithvCPU []VMInfo
				var scalesetvCPU int32
				for _, vm := range scaleSets {
					for _, size := range vmSizes {
						if vm.Location == size.Location && vm.VMSize == size.Name {
							vm.vCPUs = size.vCPUs * vm.Quantity
							scalesetvCPU += vm.vCPUs
							totalVCPUs += vm.vCPUs
							scaleSetsWithvCPU = append(scaleSetsWithvCPU, vm)
						}
					}
				}

				var enterpriseAgentsWithvCPU []VMInfo
				var k8svCPU int32
				for _, vm := range enterpriseAgents {
					for _, size := range vmSizes {
						if vm.Location == size.Location && vm.VMSize == size.Name {
							vm.vCPUs = size.vCPUs
							k8svCPU += vm.vCPUs
							totalVCPUs += size.vCPUs
							enterpriseAgentsWithvCPU = append(enterpriseAgentsWithvCPU, vm)
						}
					}
				}

				fmt.Println("VM Counts", len(standardAgentsWithvCPU))
				fmt.Println("VM Scale Set Counts", len(scaleSetsWithvCPU))
				fmt.Println("AKS Counts", len(enterpriseAgentsWithvCPU))

				fmt.Println("\nVM vCPU Counts", vmvCPU)
				fmt.Println("VM Scale Set vCPU Counts", scalesetvCPU)
				fmt.Println("AKS vCPU Counts", k8svCPU)

				for _, vm := range standardAgentsWithvCPU {
					if vm.OS == "Linux" {
						subscriptionVMOSCounts.Linux++
					} else {
						subscriptionVMOSCounts.Windows++
					}
				}

				for _, vm := range scaleSetsWithvCPU {
					if vm.OS == "Linux" {
						subscriptionVMOSCounts.Linux += vm.Quantity
					} else {
						subscriptionVMOSCounts.Windows += vm.Quantity
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
	}

	fmt.Println("----------------------------------------------")
	fmt.Println("Total vCPUs", totalVCPUs)

	if !useQuotas {
		fmt.Println("\nTotal VM OS Counts")
		fmt.Printf("Linux VMs %d\n", vmOSCounts.Linux)
		fmt.Printf("Windows VMs %d\n", vmOSCounts.Windows)
	}

	fmt.Println("\nNumber of Azure subscriptions Inventoried", subscriptionsInventoried)
	fmt.Println("----------------------------------------------")
}

type VMInfo struct {
	OS       string
	ID       string
	Location string
	vCPUs    int32
	VMSize   string
	Quantity int32
}

type OSCounts struct {
	Windows int32
	Linux   int32
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
	fmt.Println("Gathering VM vCPU Count")
	vmCount := getVMs()
	return vmCount
}

func getEntepriseAgents() []VMInfo {
	fmt.Println("Gathering AKS vCPU Count")
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

func ParseIncludeLocations(cmd *cobra.Command) []string {
	includeFlag := helpers.GetFlagEnvironmentString(cmd, "include-locations", "include-locations", "", false)
	var locations []string
	if includeFlag != "" {
		locTemp := strings.Split(includeFlag, ",")
		for _, p := range locTemp {
			trimmed := strings.TrimSpace(p)
			locations = append(locations, trimmed)
		}
	}
	return locations
}

func ParseExcludeLocations(cmd *cobra.Command) []string {
	excludeFlag := helpers.GetFlagEnvironmentString(cmd, "exclude-locations", "exclude-locations", "", false)
	var locations []string
	if excludeFlag != "" {
		locTemp := strings.Split(excludeFlag, ",")
		for _, p := range locTemp {
			trimmed := strings.TrimSpace(p)
			locations = append(locations, trimmed)
		}
	}
	return locations
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
		log.Errorln("error running az set subscription", err)
		return false
	}

	return true
}

type getResourceGroupList struct {
	Name string `json:"name"`
}

func getResourceGroups() []string {
	buf := bytes.NewBuffer([]byte{})

	cmd := exec.Command("az", "group", "list")
	cmd.Stdout = buf
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		helpers.Bail("error running az group list", err)
	}

	response := []getResourceGroupList{}
	if err := json.NewDecoder(buf).Decode(&response); err != nil {
		helpers.Bail("Error decoding groups json", err)
	}

	var groups []string
	for _, group := range response {
		groups = append(groups, group.Name)
	}

	return groups
}

type getContainerListResponse struct {
	Containers []struct {
		Resources struct {
			Requests struct {
				CPU float32 `json:"cpu"`
			} `json:"requests"`
		} `json:"resources"`
	} `json:"containers"`
	Location string `json:"location"`
	OSType   string `json:"osType"`
}

func getContainers(resourceGroup string) []VMInfo {
	buf := bytes.NewBuffer([]byte{})

	cmd := exec.Command("az", "container", "list", "-g", resourceGroup)
	cmd.Stdout = buf
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		helpers.Bail("error running az container list", err)
	}

	response := []getContainerListResponse{}
	if err := json.NewDecoder(buf).Decode(&response); err != nil {
		helpers.Bail("Error decoding container json", err)
	}

	var vms = []VMInfo{}
	for _, containers := range response {
		for _, container := range containers.Containers {
			vms = append(vms, VMInfo{Location: containers.Location, OS: containers.OSType, vCPUs: int32(container.Resources.Requests.CPU)})
		}
	}
	return vms
}

type getVMScaleSetResponse struct {
	SKU struct {
		Capacity int32  `json:"capacity"`
		Name     string `json:"name"`
	} `json:"sku"`
	VirtualMachineProfile struct {
		StorageProfile struct {
			OSDisk struct {
				OSType string `json:"osType"`
			} `json:"osDisk"`
		}
	} `json:"virtualMachineProfile"`
	Location string `json:"location"`
}

func getVMScaleSet() []VMInfo {
	buf := bytes.NewBuffer([]byte{})

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

	var vms = []VMInfo{}
	for _, ss := range response {
		vms = append(vms, VMInfo{OS: ss.VirtualMachineProfile.StorageProfile.OSDisk.OSType, ID: "", Location: ss.Location, VMSize: ss.SKU.Name, Quantity: ss.SKU.Capacity})
	}
	return vms
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

type getListLocationsResponse struct {
	DisplayName string `json:"displayName"`
	Name        string `json:"name"`
}

func getLocations() []string {
	buf := bytes.NewBuffer([]byte{})

	cmd := exec.Command("az", "account", "list-locations")
	cmd.Stdout = buf
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		helpers.Bail("error running az account list-locations", err)
	}

	response := []getListLocationsResponse{}
	if err := json.NewDecoder(buf).Decode(&response); err != nil {
		helpers.Bail("Error decoding list locations json", err)
	}

	var locations []string
	for _, location := range response {
		locations = append(locations, location.Name)
	}

	return locations
}

type getListUsageResponse struct {
	Value string `json:"currentValue"`
	Name  string `json:"localName"`
}

func getUsage(location string) int32 {
	buf := bytes.NewBuffer([]byte{})

	cmd := exec.Command("az", "vm", "list-usage", "--location", location)
	cmd.Stdout = buf
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		fmt.Errorf("error running az vm list-usage", err)
		return 0
	}

	response := []getListUsageResponse{}
	if err := json.NewDecoder(buf).Decode(&response); err != nil {
		helpers.Bail("Error decoding list usage json", err)
	}

	var vcpus int32
	for _, q := range response {
		if q.Name == "Total Regional vCPUs" {
			vcpu, err := strconv.ParseInt(q.Value, 10, 32)
			if err != nil {
				println(err)
			}
			vcpus = int32(vcpu)
		}
	}
	fmt.Printf("%s: %d vCPUS\n", location, vcpus)
	return vcpus
}
