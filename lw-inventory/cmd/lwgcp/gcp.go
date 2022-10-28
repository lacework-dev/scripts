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
	"google.golang.org/api/sqladmin/v1"
	computepb "google.golang.org/genproto/googleapis/cloud/compute/v1"
	"strings"
)

const (
	GCE_VM = "GCE VM"
	GKE_VM = "GKE VM"
)

type ProjectInfo struct {
	ID     string
	Name   string
	Number int64
}

type AgentlessServiceCount struct {
	Region  string
	Service string
	Count   int
}

type VMInstanceInfo struct {
	Zone   string
	Image  string
	VMType string
	OS     string
}

type OSCounts struct {
	Windows int
	Linux   int
}

func Run(projectsToIgnore []string, credentials string, debug bool) {
	if debug {
		log.SetLevel(log.DebugLevel)
	}

	projects := getProjects(credentials, projectsToIgnore)
	agentlessCount := getAgentlessCount(credentials, projects)

	vms := getVMInstances(credentials, projects)
	enterpriseVMs := getEntepriseAgents(vms)
	standardVMs := getStandardAgents(vms)

	fmt.Println("----------------------------------------------")
	fmt.Printf("Total Resources %d\n", agentlessCount+len(vms))
	fmt.Printf("Standard VM Agents: %d\n", len(standardVMs))
	fmt.Printf("Enterprise VM Agents: %d\n", len(enterpriseVMs))
	fmt.Println("Number of GCP projects inventoried", len(projects))
	fmt.Println("----------------------------------------------")
}

func getAgentlessCount(credentials string, projects []ProjectInfo) int {
	fmt.Println("Gathering resource count")
	resourceCount := 0
	numFuncs := 0
	channel := make(chan int)

	numFuncs += 1
	go func(credentials string, projects []ProjectInfo) {
		channel <- getLoadBalancers(credentials, projects)
	}(credentials, projects)

	numFuncs += 1
	go func(credentials string, projects []ProjectInfo) {
		channel <- getGateways(credentials, projects)
	}(credentials, projects)

	numFuncs += 1
	go func(credentials string, projects []ProjectInfo) {
		channel <- getSQLServerInstances(credentials, projects)
	}(credentials, projects)

	for i := 0; i < numFuncs; i++ {
		counts := <-channel
		resourceCount += counts
	}

	return resourceCount
}

func getStandardAgents(vms []VMInstanceInfo) []VMInstanceInfo {
	var standardVMs []VMInstanceInfo

	for _, vm := range vms {
		if vm.VMType == GCE_VM {
			standardVMs = append(standardVMs, vm)
		}
	}
	return standardVMs
}

func getEntepriseAgents(vms []VMInstanceInfo) []VMInstanceInfo {
	var enterpriseVMs []VMInstanceInfo

	for _, vm := range vms {
		if vm.VMType == GKE_VM {
			enterpriseVMs = append(enterpriseVMs, vm)
		}
	}
	return enterpriseVMs
}

func getLoadBalancers(credentials string, projects []ProjectInfo) int {
	fmt.Println("Inventorying LoadBalancers")
	ctx := context.Background()

	loadbalancerCount := 0

	for _, project := range projects {
		if isServiceEnabled(project.Number, "compute.googleapis.com", credentials) {
			instancesClient, err := compute.NewForwardingRulesRESTClient(ctx)

			if err != nil {
				fmt.Errorf("NewInstancesRESTClient: %v", err)
				return 0
			}
			defer instancesClient.Close()

			req := &computepb.AggregatedListForwardingRulesRequest{
				Project: project.ID,
			}

			it := instancesClient.AggregatedList(ctx, req)
			// Despite using the `MaxResults` parameter, you don't need to handle the pagination
			// yourself. The returned iterator object handles pagination
			// automatically, returning separated pages as you iterate over the results.
			for {
				pair, err := it.Next()
				if err == iterator.Done {
					break
				}
				if err != nil {
					fmt.Errorf("getLoadBalancers pair iterator: %v", err)
					return 0
				}
				//fmt.Println(pair)
				if pair.Value.ForwardingRules != nil {
					//fmt.Println(pair)
					loadbalancerCount += len(pair.Value.ForwardingRules)
				}
			}
		} else {
			fmt.Println("Compute not enabled for ", project.Name)
		}
	}

	log.Debugln("LoadBalancers found", loadbalancerCount)
	return loadbalancerCount
}

func getGateways(credentials string, projects []ProjectInfo) int {
	fmt.Println("Inventorying Gateways")
	ctx := context.Background()

	routerCount := 0

	for _, project := range projects {
		if isServiceEnabled(project.Number, "compute.googleapis.com", credentials) {
			instancesClient, err := compute.NewRoutersRESTClient(ctx)

			if err != nil {
				fmt.Errorf("NewInstancesRESTClient: %v", err)
				return 0
			}
			defer instancesClient.Close()

			req := &computepb.AggregatedListRoutersRequest{
				Project: project.ID,
			}

			it := instancesClient.AggregatedList(ctx, req)
			// Despite using the `MaxResults` parameter, you don't need to handle the pagination
			// yourself. The returned iterator object handles pagination
			// automatically, returning separated pages as you iterate over the results.
			for {
				pair, err := it.Next()
				if err == iterator.Done {
					break
				}
				if err != nil {
					fmt.Errorf("getGateways pair iterator: %v", err)
					return 0
				}
				//fmt.Println(pair)
				if pair.Value.Routers != nil {
					//fmt.Println(pair)
					routerCount += len(pair.Value.Routers)
				}
			}
		} else {
			fmt.Println("Compute not enabled for ", project.Name)
		}
	}

	log.Debugln("Gateways found", routerCount)
	return routerCount
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

func getSQLServerInstances(credentials string, projects []ProjectInfo) int {
	fmt.Println("Inventorying SQL")
	ctx := context.Background()
	sqlService, err := sqladmin.NewService(ctx, option.WithCredentialsFile(credentials))
	if err != nil {
		log.Fatalln("error in getSQLServerInstances", err)
	}

	sqlCount := 0

	for _, project := range projects {
		if isServiceEnabled(project.Number, "sqladmin.googleapis.com", credentials) {
			//fmt.Println("got in enabled")
			req := sqlService.Instances.List(project.ID)
			if err := req.Pages(ctx, func(page *sqladmin.InstancesListResponse) error {
				//for _, db := range page.Items {
				//	fmt.Println(db.Name)
				//}
				sqlCount += len(page.Items)
				return nil
			}); err != nil {
				log.Fatal("err in getSQLServerInstances", err)
			}
		} else {
			fmt.Println("SQL not enabled for", project.Name, "("+project.ID+")")
		}
	}

	log.Debugln("SQL Servers found", sqlCount)
	return sqlCount
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
			// Despite using the `MaxResults` parameter, you don't need to handle the pagination
			// yourself. The returned iterator object handles pagination
			// automatically, returning separated pages as you iterate over the results.
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
						//fmt.Println(instance)
						if instance.GetStatus() == "RUNNING" {
							if _, ok := instance.GetLabels()["goog-gke-node"]; ok {
								vms = append(vms, VMInstanceInfo{Zone: pair.Key, VMType: GKE_VM})
							} else {
								vms = append(vms, VMInstanceInfo{Zone: pair.Key, VMType: GCE_VM})
							}
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
