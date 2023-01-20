package lwgcp

import (
	compute "cloud.google.com/go/compute/apiv1"
	"context"
	"fmt"
	"github.com/lacework-dev/scripts/lw-inventory/helpers"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
	"google.golang.org/api/cloudresourcemanager/v1"
	"google.golang.org/api/iterator"
	"google.golang.org/api/option"
	"google.golang.org/api/serviceusage/v1"
	computepb "google.golang.org/genproto/googleapis/cloud/compute/v1"
	"strconv"
	"strings"
)

type ProjectInfo struct {
	ID     string
	Name   string
	Number int64
}

type VMInstanceInfo struct {
	Zone         string
	Image        string
	OS           string
	InstanceType string
	Project      string
	vCPU         int32
	Name         string
}

type InstanceType struct {
	Zone string
	Name string
}

type MachineType struct {
	vCPUs int32
	Name  string
	Zone  string
}

type OSCounts struct {
	Windows int
	Linux   int
}

type ContainerClusterInfo struct {
	Zone          string
	ContainerType string
	vCPU          float64
	ClusterName   string
	Project       string
}

func Run(projectsToIgnore []string, credentials string, debug bool) {
	if debug {
		log.SetLevel(log.DebugLevel)
	}

	projects := getProjects(credentials, projectsToIgnore)
	vms := getVMInstances(credentials, projects)
	machineTypes := getMachinesTypes(credentials, projects, vms)
	//getCloudRunCounts

	var vmsWithvCPU []VMInstanceInfo
	for _, vm := range vms {
		for _, mt := range machineTypes {
			if vm.Zone == mt.Zone && vm.InstanceType == mt.Name {
				vm.vCPU = mt.vCPUs
			}
		}
		if vm.vCPU == 0 {
			vm.vCPU = parseCustomInstanceType(vm.InstanceType)
		}
		vmsWithvCPU = append(vmsWithvCPU, vm)
	}

	for _, project := range projects {
		fmt.Println("Project:", project.Name)
		var vcpus int32
		for _, vm := range vmsWithvCPU {
			if vm.Project == project.Name {
				log.Debugln(vm.Name, vm.InstanceType, vm.vCPU)
				vcpus += vm.vCPU
			}
		}
		fmt.Printf("vCPUs: %d\n\n", vcpus)
	}
	fmt.Println("----------------------------------------------")
	fmt.Println("Number of GCP projects inventoried:", len(projects))
	fmt.Println("----------------------------------------------")
}

func parseCustomInstanceType(instanceType string) int32 {
	parts := strings.Split(instanceType, "-")
	i, err := strconv.ParseInt(parts[2], 10, 32)
	if err != nil {
		panic(err)
	}
	vcpus := int32(i)
	return vcpus
}

func ParseCredentials(cmd *cobra.Command) string {
	return helpers.GetFlagEnvironmentString(cmd, "credentials", "credentials", "", false)
}

func ParseProjectsToIgnore(cmd *cobra.Command) []string {
	projectsToIgnoreFlag := helpers.GetFlagEnvironmentString(cmd, "projects-to-ignore", "projects-to-ignore", "", false)
	var projectsToIgnore []string
	if projectsToIgnoreFlag != "" {
		projectsToIgnoreTemp := strings.Split(projectsToIgnoreFlag, ",")
		for _, z := range projectsToIgnoreTemp {
			trimmed := strings.TrimSpace(z)
			projectsToIgnore = append(projectsToIgnore, trimmed)
		}
	}
	return projectsToIgnore
}

func isProjectValid(project *cloudresourcemanager.Project, projectsToIgnore []string) bool {
	yesno := project.LifecycleState == "ACTIVE" && !helpers.Contains(projectsToIgnore, project.ProjectId)
	return yesno
}

func isServiceEnabled(projectNumber int64, service string, credentials string) bool {
	ctx := context.Background()
	c, err := serviceusage.NewService(ctx, option.WithCredentialsFile(credentials))
	if err != nil {
		fmt.Println("service usage new service error", err)
		return false
	}

	resp, err := c.Services.Get(fmt.Sprintf("projects/%d/services/%s", projectNumber, service)).Do()
	if err != nil {
		log.Fatalln("services get error", err)
		return false
	}
	return resp.State == "ENABLED"
}

func getVMInstances(credentials string, projects []ProjectInfo) []VMInstanceInfo {
	fmt.Println("Inventorying Compute")
	ctx := context.Background()

	var vms []VMInstanceInfo

	for _, project := range projects {
		if isServiceEnabled(project.Number, "compute.googleapis.com", credentials) {
			instancesClient, err := compute.NewInstancesRESTClient(ctx)

			if err != nil {
				fmt.Errorf("NewInstancesRESTClient: %v", err)
				return nil
			}
			defer instancesClient.Close()

			req := &computepb.AggregatedListInstancesRequest{
				Project: project.ID,
			}

			it := instancesClient.AggregatedList(ctx, req)
			for {
				pair, err := it.Next()
				if err == iterator.Done {
					break
				}
				if err != nil {
					fmt.Errorf("NewInstancesRESTClient pair iterator: %v", err)
					return nil
				}
				instances := pair.Value.Instances
				if len(instances) > 0 {
					for _, instance := range instances {
						if instance.GetStatus() == "RUNNING" {
							parts := strings.Split(*instance.MachineType, "/")
							instanceType := parts[10]
							zone := parts[8]
							vms = append(vms, VMInstanceInfo{Project: project.Name, Zone: zone, InstanceType: instanceType, Name: *instance.Name})
						}
					}
				}
			}
		} else {
			fmt.Println("Compute not enabled for ", project.Name)
		}
	}

	log.Debugln("VMs found", len(vms))
	return vms
}

func getMachinesTypes(credentials string, projects []ProjectInfo, vms []VMInstanceInfo) []MachineType {
	fmt.Println("Getting Machine Types")
	var project ProjectInfo
	for _, p := range projects {
		if isServiceEnabled(p.Number, "compute.googleapis.com", credentials) {
			if project.ID == "" {
				project = p
			}
		}
	}

	var machineTypes []MachineType
	if len(vms) == 0 {
		return machineTypes
	}

	var instanceTypes []string
	var zones []string
	for _, vm := range vms {
		if !helpers.Contains(instanceTypes, vm.InstanceType) {
			instanceTypes = append(instanceTypes, vm.InstanceType)
		}
		if !helpers.Contains(zones, vm.Zone) {
			zones = append(zones, vm.Zone)
		}
	}

	for _, instanceType := range instanceTypes {
		mt := getMachineTypeByName(credentials, project, instanceType, zones)
		if len(mt) > 0 {
			machineTypes = append(machineTypes, mt...)
		}
	}

	return machineTypes
}

func getMachineTypeByName(credentials string, project ProjectInfo, instanceType string, zones []string) []MachineType {

	ctx := context.Background()

	var machineTypes []MachineType

	instancesClient, err := compute.NewMachineTypesRESTClient(ctx)

	if err != nil {
		fmt.Errorf("NewMachineTypesRESTClient: %v", err)
		return nil
	}
	defer instancesClient.Close()

	//format the query string
	x := fmt.Sprintf(`(name = "%s") AND ((zone = "%s")`, instanceType, zones[0])
	for _, z := range zones[1:] {
		x += fmt.Sprintf(` OR (zone = "%s")`, z)
	}
	x += ")" //need the trailing ")"

	var machineTypeQuery *string
	machineTypeQuery = &x

	req := &computepb.AggregatedListMachineTypesRequest{
		Project: project.ID,
		Filter:  machineTypeQuery,
	}

	it := instancesClient.AggregatedList(ctx, req)
	for {
		pair, err := it.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			fmt.Errorf("NewInstancesRESTClient pair iterator: %v", err)
			return nil
		}

		types := pair.Value.MachineTypes

		for _, mt := range types {
			machineTypes = append(machineTypes, MachineType{
				vCPUs: *mt.GuestCpus,
				Name:  *mt.Name,
				Zone:  *mt.Zone,
			})
		}

	}

	log.Debugln("Machine Type found", len(machineTypes))
	return machineTypes
}

func getProjects(credentials string, projectsToIgnore []string) []ProjectInfo {
	fmt.Println("Inventorying Compute")
	ctx := context.Background()
	service, err := cloudresourcemanager.NewService(ctx, option.WithCredentialsFile(credentials))
	if err != nil {
		log.Fatalln(err)
	}

	var projects []ProjectInfo
	req := service.Projects.List()
	if err := req.Pages(ctx, func(page *cloudresourcemanager.ListProjectsResponse) error {
		for _, project := range page.Projects {
			if isProjectValid(project, projectsToIgnore) {
				fmt.Println("Scanning project", project.ProjectId)

				projects = append(projects, ProjectInfo{
					ID:     project.ProjectId,
					Name:   project.Name,
					Number: project.ProjectNumber,
				})
			}
		}
		return nil
	}); err != nil {
		log.Fatal(err)
	}

	log.Debugln("Projects found", projects)
	return projects
}
