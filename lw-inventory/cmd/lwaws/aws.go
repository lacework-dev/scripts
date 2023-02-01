package lwaws

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	"github.com/aws/aws-sdk-go-v2/service/ecs"
	"github.com/aws/aws-sdk-go-v2/service/elasticloadbalancing"
	"github.com/aws/aws-sdk-go-v2/service/elasticloadbalancingv2"

	ec2Types "github.com/aws/aws-sdk-go-v2/service/ec2/types"
	ecsTypes "github.com/aws/aws-sdk-go-v2/service/ecs/types"
	"github.com/aws/aws-sdk-go-v2/service/eks"
	"github.com/aws/aws-sdk-go-v2/service/rds"
	"github.com/aws/aws-sdk-go-v2/service/redshift"
	"github.com/lacework-dev/scripts/lw-inventory/helpers"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
)

const (
	EC2                         = "EC2 VM"
	RDS                         = "RDS Instance"
	REDSHIFT                    = "Redshift"
	NATGATEWAY                  = "NAT Gateway"
	ELBv1                       = "ELBv1"
	ELBv2                       = "ELBv2"
	ECS                         = "ECS EC2 VM"
	ECS_TASKS                   = "ECS Task"
	FARGATE_RUNNING_TASKS       = "Fargate Running Task"
	FARGATE_RUNNING_CONTAINERS  = "Fargate Running Containers"
	FARGATE_TOTAL_CONTAINERS    = "Fargate Total Containers"
	FARGATE_ACTIVE_SERVICES     = "Fargate Active Services"
	EKS_FARGATE_ACTIVE_PROFILES = "EKS Fargate Active Profiles"
	ENTERPRISE_AGENT            = "Enterprise Agent"
	STANDARD_AGENT              = "Standard Agent"
)

type AgentlessServiceCount struct {
	Region  string
	Service string
	Count   int
}

type AgentContainerCount struct {
	Region        string
	ContainerType string
	Count         int
}

type VMInfo struct {
	Region    string
	AMI       string
	AccountId string
	AgentType string
	OS        string
}

type OSCounts struct {
	Windows int
	Linux   int
}

func Run(profiles []string, regions []string, debug bool, k8sTags []string) {
	if debug {
		log.SetLevel(log.DebugLevel)
	}

	fmt.Println("Beginning Scan")
	fmt.Printf("Profiles to use: %s\n", profiles)

	totalResources := 0
	var totalStandardAgentOSCount OSCounts
	var totalEnterpriseAgentOSCount OSCounts
	totalAccounts := 0

	//loop over all profiles and get counts
	for _, p := range profiles {
		var agentlessCounts []AgentlessServiceCount
		var ec2VMInfo []VMInfo
		var ECSVMInfo []VMInfo
		var agentContainers []AgentContainerCount
		fmt.Println("Using profile", p)

		cfg := getSession(p, "us-east-1")

		if len(regions) == 0 {
			regions = getRegions(*cfg)
		}
		fmt.Printf("Scanning regions: %s\n", regions)

		agentlessCounts = getAgentlessCounts(p, regions)
		ec2VMInfo = getAgentVMCounts(p, regions, k8sTags)
		ECSVMInfo = getECSVMCounts(p, regions)
		agentContainers = getAgentContainerCounts(p, regions)

		//run through each region
		agentlessResourceCount := 0
		agentContainerCount := make(map[string]int)
		var standardAgents []string
		var enterpriseAgents []string
		agentlessServices := []string{RDS, REDSHIFT, ELBv1, ELBv2, NATGATEWAY, ECS}
		agentServices := []string{ECS_TASKS, FARGATE_RUNNING_TASKS, FARGATE_RUNNING_CONTAINERS, FARGATE_TOTAL_CONTAINERS, FARGATE_ACTIVE_SERVICES, EKS_FARGATE_ACTIVE_PROFILES}
		var enterpriseAgentOSCounts OSCounts
		var standardAgentOSCounts OSCounts

		for _, r := range regions {
			agentlessCountByRegion := 0

			log.Debugln("Region ", r)
			for _, s := range agentlessServices {
				agentlessCountByRegion += getAgentlessCountByService(agentlessCounts, r, s)
			}

			agentlessResourceCount += agentlessCountByRegion

			for _, s := range agentServices {
				agentContainerCount[s] += getAgentCountByService(agentContainers, r, s)
			}
		}

		//get a list of AMIs to compare against
		var ECSAMIS []string
		for _, vm := range ECSVMInfo {
			ECSAMIS = append(ECSAMIS, vm.AMI)
		}

		var cleanVMs []VMInfo

		for _, vm := range ec2VMInfo {
			if vm.AgentType == ENTERPRISE_AGENT {
				cleanVMs = append(cleanVMs, vm)
			} else {
				if helpers.Contains(ECSAMIS, vm.AMI) {
					vm.AgentType = ENTERPRISE_AGENT
					cleanVMs = append(cleanVMs, vm)
				} else {
					vm.AgentType = STANDARD_AGENT
					cleanVMs = append(cleanVMs, vm)
				}
			}
		}

		var accountIds []string
		for _, vm := range cleanVMs {
			if !helpers.Contains(accountIds, vm.AccountId) {
				accountIds = append(accountIds, vm.AccountId)
			}
		}

		for _, vm := range cleanVMs {
			agentlessResourceCount++
			if vm.AgentType == STANDARD_AGENT {
				if vm.OS == "Linux/UNIX" {
					standardAgentOSCounts.Linux++
				} else {
					standardAgentOSCounts.Windows++
				}
			} else {
				if vm.OS == "Linux/UNIX" {
					enterpriseAgentOSCounts.Linux++
				} else {
					enterpriseAgentOSCounts.Windows++
				}
			}
		}

		totalResources += agentlessResourceCount
		totalStandardAgentOSCount.Linux += standardAgentOSCounts.Linux
		totalStandardAgentOSCount.Windows += standardAgentOSCounts.Windows
		totalEnterpriseAgentOSCount.Linux += enterpriseAgentOSCounts.Linux
		totalEnterpriseAgentOSCount.Windows += enterpriseAgentOSCounts.Windows
		totalAccounts += len(accountIds)

		fmt.Println("----------------------------------------------")
		fmt.Println("Totals for profile", p)
		fmt.Printf("Total Resources  %d\n", agentlessResourceCount)
		fmt.Printf("Standard Agent VMs: %d\n", len(standardAgents))
		fmt.Printf("Enterprise Agent VMs: %d\n", len(enterpriseAgents))
		for s, c := range agentContainerCount {
			fmt.Printf("%s: %d\n", s, c)
		}

		fmt.Println("\nVM OS Counts")
		fmt.Printf("Standard Agent Linux VMs %d\n", standardAgentOSCounts.Linux)
		fmt.Printf("Standard Agent Windows VMs %d\n", standardAgentOSCounts.Windows)
		fmt.Printf("Enterprise Agent Linux VMs %d\n", enterpriseAgentOSCounts.Linux)
		fmt.Printf("Enterprise Agent Windows VMs %d\n", enterpriseAgentOSCounts.Windows)

		fmt.Println("\nNumber of AWS Accounts inventoried:", len(accountIds))
		fmt.Println("----------------------------------------------")
	}

	fmt.Println("----------------------------------------------")
	fmt.Println("Totals for all profiles")
	fmt.Printf("Total Resources  %d\n", totalResources)
	fmt.Printf("Standard Agent VMs: %d\n", totalStandardAgentOSCount.Linux+totalStandardAgentOSCount.Windows)
	fmt.Printf("Enterprise Agent VMs: %d\n", totalEnterpriseAgentOSCount.Linux+totalEnterpriseAgentOSCount.Windows)

	fmt.Println("\nVM OS Counts")
	fmt.Printf("Standard Agent Linux VMs %d\n", totalStandardAgentOSCount.Linux)
	fmt.Printf("Standard Agent Windows VMs %d\n", totalStandardAgentOSCount.Windows)
	fmt.Printf("Enterprise Agent Linux VMs %d\n", totalEnterpriseAgentOSCount.Linux)
	fmt.Printf("Enterprise Agent Windows VMs %d\n", totalEnterpriseAgentOSCount.Windows)

	fmt.Println("\nNumber of AWS Accounts inventoried:", totalAccounts)
	fmt.Println("----------------------------------------------")

}

func getSession(profile string, region string) *aws.Config {
	cfg, err := config.LoadDefaultConfig(context.TODO(),
		config.WithRegion(region),
		config.WithSharedConfigProfile(profile),
		//config.WithDefaultsMode(aws.DefaultsModeAuto),
	)
	if err != nil {
		log.Errorln("Error connecting to AWS", err)
	}

	return &cfg
}

func getRegions(cfg aws.Config) []string {
	service := ec2.NewFromConfig(cfg)
	var regions []string
	regionsResponse, err := service.DescribeRegions(context.TODO(), &ec2.DescribeRegionsInput{
		AllRegions: aws.Bool(true),
	})

	if err != nil {
		fmt.Println(err)
	} else {
		awsRegions := regionsResponse.Regions
		for _, r := range awsRegions {
			//make sure not to add regions that are disabled
			if *r.OptInStatus != "not-opted-in" {
				n := *r.RegionName
				regions = append(regions, n)
			} else {
				log.Debugln("Region skipped", *r.RegionName)
			}
		}
	}

	return regions
}

func getAgentlessCountByService(counts []AgentlessServiceCount, region string, service string) int {
	for _, i := range counts {
		if i.Service == service && i.Region == region {
			log.Debugf("%s: %d\n", service, i.Count)
			return i.Count
		}
	}
	return 0
}

func getAgentCountByService(counts []AgentContainerCount, region string, containerType string) int {
	for _, i := range counts {
		if i.ContainerType == containerType && i.Region == region {
			// log.Debugf("%s: %d\n", containerType, i.Count)
			return i.Count
		}
	}
	return 0
}

func getAgentlessCounts(profile string, regions []string) []AgentlessServiceCount {
	log.Debugf("start getAgentlessCounts\n")
	start := time.Now()

	numFuncs := 0
	channel := make(chan AgentlessServiceCount)
	var serviceCountList []AgentlessServiceCount
	for _, r := range regions {
		cfg := getSession(profile, r)
		//rds instances
		numFuncs += 1
		go func(r string) {
			channel <- getRDSInstanceCountByRegion(*cfg, r)
		}(r)

		//redshift instances
		numFuncs += 1
		go func(r string) {
			channel <- getRedshiftInstanceCountByRegion(*cfg, r)
		}(r)

		//elbv1 instances
		numFuncs += 1
		go func(r string) {
			channel <- getELBv1InstanceCountByRegion(*cfg, r)
		}(r)

		// //elbv2 instances
		numFuncs += 1
		go func(r string) {
			channel <- getELBv2InstanceCountByRegion(*cfg, r)
		}(r)

		//NAT gateways
		numFuncs += 1
		go func(r string) {
			channel <- getNatGatewayInstanceCountByRegion(*cfg, r)
		}(r)
	}

	for i := 0; i < numFuncs; i++ {
		count := <-channel
		serviceCountList = append(serviceCountList, count)
	}

	elapsed := time.Since(start)
	log.Debugf("end getAgentlessCounts - %s\n", elapsed)
	return serviceCountList
}

func getAgentContainerCounts(profile string, regions []string) []AgentContainerCount {
	log.Debugf("start getAgentContainerCounts\n")
	start := time.Now()

	numFuncs := 0
	channel := make(chan AgentContainerCount)
	var agentContainerList []AgentContainerCount

	for _, r := range regions {
		cfg := getSession(profile, r)
		//ECS Tasks
		numFuncs += 1
		go func(r string) {
			channel <- getECSTaskDefinitionsByRegion(*cfg, r)
		}(r)

		//Running Fargate Tasks
		numFuncs += 1
		go func(r string) {
			channel <- getECSFargateRunningTasksByRegion(*cfg, r)
		}(r)

		//Running Fargate Containers
		numFuncs += 1
		go func(r string) {
			channel <- getECSFargateRunningContainersByRegion(*cfg, r)
		}(r)

		//Total Fargate Containers
		numFuncs += 1
		go func(r string) {
			channel <- getECSFargateTotalContainersByRegion(*cfg, r)
		}(r)

		numFuncs += 1
		go func(r string) {
			channel <- getEKSFargateActiveProfilesByRegion(*cfg, r)
		}(r)

		numFuncs += 1
		go func(r string) {
			channel <- getECSFargateActiveServicesByRegion(*cfg, r)
		}(r)
	}

	for i := 0; i < numFuncs; i++ {
		containers := <-channel
		agentContainerList = append(agentContainerList, containers)
	}

	elapsed := time.Since(start)
	log.Debugf("end getAgentContainerCounts - %s\n", elapsed)

	return agentContainerList
}

func getEKSFargateActiveProfilesByRegion(cfg aws.Config, region string) AgentContainerCount {
	service := eks.NewFromConfig(cfg)
	output := eks.NewListClustersPaginator(service, &eks.ListClustersInput{})

	count := 0
	for output.HasMorePages() {
		page, err := output.NextPage(context.TODO())
		if err != nil {
			log.Errorln("getEKSFargateActiveProfilesByRegion ListFargateProfiles ", region, output, err)
		} else {
			for _, c := range page.Clusters {
				output := eks.NewListFargateProfilesPaginator(service, &eks.ListFargateProfilesInput{ClusterName: &c})
				for output.HasMorePages() {
					page, err := output.NextPage(context.TODO())
					if err != nil {
						log.Errorln("getEKSFargateActiveProfilesByRegion ListFargateProfiles ", region, c, err)
					} else {
						count += len(page.FargateProfileNames)
					}
				}
			}
		}
	}

	return AgentContainerCount{
		Region:        region,
		ContainerType: EKS_FARGATE_ACTIVE_PROFILES,
		Count:         count,
	}
}

func getECSTaskDefinitionsByRegion(cfg aws.Config, region string) AgentContainerCount {
	service := ecs.NewFromConfig(cfg)
	output := ecs.NewListTaskDefinitionsPaginator(service, &ecs.ListTaskDefinitionsInput{})

	count := 0
	for output.HasMorePages() {
		page, err := output.NextPage(context.TODO())
		if err != nil {
			log.Errorln("getECSTaskDefinitionsByRegion ListTaskDefinitions ", region, err)
		} else {
			count += len(page.TaskDefinitionArns)
		}
	}

	return AgentContainerCount{
		Region:        region,
		ContainerType: ECS_TASKS,
		Count:         count,
	}
}

func getECSFargateRunningTasksByRegion(cfg aws.Config, region string) AgentContainerCount {
	service := ecs.NewFromConfig(cfg)
	output := ecs.NewListClustersPaginator(service, &ecs.ListClustersInput{})

	taskCount := 0
	for output.HasMorePages() {
		page, err := output.NextPage(context.TODO())
		if err != nil {
			log.Errorln("getECSFargateRunningTasksByRegion ListClusters ", region, err)
		} else {
			for _, cluster := range page.ClusterArns {
				output := ecs.NewListTasksPaginator(service, &ecs.ListTasksInput{
					Cluster: &cluster,
				})
				for output.HasMorePages() {
					page, err := output.NextPage(context.TODO())
					if err != nil {
						log.Errorln("getECSFargateRunningTasksByRegion ListTasks ", region, err)
					} else {
						taskCount += len(page.TaskArns)
					}
				}
			}
		}
	}

	return AgentContainerCount{
		Region:        region,
		ContainerType: FARGATE_RUNNING_TASKS,
		Count:         taskCount,
	}
}

func getECSFargateActiveServicesByRegion(cfg aws.Config, region string) AgentContainerCount {
	service := ecs.NewFromConfig(cfg)
	output := ecs.NewListClustersPaginator(service, &ecs.ListClustersInput{})

	count := 0
	for output.HasMorePages() {
		page, err := output.NextPage(context.TODO())
		if err != nil {
			log.Errorln("getECSFargateActiveServicesByRegion ListClusters ", region, err)
		} else {
			output, err := service.DescribeClusters(context.TODO(), &ecs.DescribeClustersInput{
				Clusters: page.ClusterArns,
			})

			if err != nil {
				log.Errorln("getECSFargateActiveServicesByRegion DescribeClusters ", region, err)
			} else {
				for _, c := range output.Clusters {
					count += int(c.ActiveServicesCount)
				}
			}
		}
	}

	return AgentContainerCount{
		Region:        region,
		ContainerType: FARGATE_ACTIVE_SERVICES,
		Count:         count,
	}
}

func getECSFargateRunningContainersByRegion(cfg aws.Config, region string) AgentContainerCount {
	service := ecs.NewFromConfig(cfg)
	output := ecs.NewListClustersPaginator(service, &ecs.ListClustersInput{})

	taskCount := 0
	for output.HasMorePages() {
		page, err := output.NextPage(context.TODO())
		if err != nil {
			log.Errorln("getECSFargateRunningContainersByRegion ListClusters ", region, err)
		} else {
			for _, cluster := range page.ClusterArns {
				output := ecs.NewListTasksPaginator(service, &ecs.ListTasksInput{
					Cluster: &cluster,
				})
				for output.HasMorePages() {
					page, err := output.NextPage(context.TODO())
					if err != nil {
						log.Errorln("getECSFargateRunningContainersByRegion ListTasks ", region, err)
					} else {
						if len(page.TaskArns) > 0 {
							outputDT, err := service.DescribeTasks(context.TODO(), &ecs.DescribeTasksInput{
								Cluster: &cluster,
								Tasks:   page.TaskArns,
							})
							if err != nil {
								log.Errorln("getECSFargateRunningContainersByRegion DescribeTasks ", region, err)
							} else {
								for _, t := range outputDT.Tasks {
									if t.LaunchType == ecsTypes.LaunchTypeFargate && ecsTypes.DesiredStatus(*t.LastStatus) == ecsTypes.DesiredStatusRunning {
										for _, c := range t.Containers {
											if ecsTypes.DesiredStatus(*c.LastStatus) == ecsTypes.DesiredStatusRunning {
												taskCount += 1
											}
										}
									}
								}
							}
						}
					}
				}
			}
		}
	}

	return AgentContainerCount{
		Region:        region,
		ContainerType: FARGATE_RUNNING_CONTAINERS,
		Count:         taskCount,
	}
}

func getECSFargateTotalContainersByRegion(cfg aws.Config, region string) AgentContainerCount {
	service := ecs.NewFromConfig(cfg)
	output := ecs.NewListClustersPaginator(service, &ecs.ListClustersInput{})

	taskCount := 0
	for output.HasMorePages() {
		page, err := output.NextPage(context.TODO())
		if err != nil {
			log.Errorln("getECSFargateTotalContainersByRegion ListClusters ", region, err)
		} else {
			for _, cluster := range page.ClusterArns {
				output := ecs.NewListTasksPaginator(service, &ecs.ListTasksInput{
					Cluster: &cluster,
				})
				for output.HasMorePages() {
					page, err := output.NextPage(context.TODO())
					if err != nil {
						log.Errorln("getECSFargateTotalContainersByRegion ListTasks ", region, err)
					} else {
						if len(page.TaskArns) > 0 {
							outputDT, err := service.DescribeTasks(context.TODO(), &ecs.DescribeTasksInput{
								Cluster: &cluster,
								Tasks:   page.TaskArns,
							})
							if err != nil {
								log.Errorln("getECSFargateTotalContainersByRegion DescribeTasks ", region, err)
							} else {
								for _, t := range outputDT.Tasks {
									if t.LaunchType == ecsTypes.LaunchTypeFargate && ecsTypes.DesiredStatus(*t.LastStatus) == ecsTypes.DesiredStatusRunning {
										taskCount += len(t.Containers)
									}
								}
							}
						}
					}
				}
			}
		}
	}

	return AgentContainerCount{
		Region:        region,
		ContainerType: FARGATE_TOTAL_CONTAINERS,
		Count:         taskCount,
	}
}

func getAgentVMCounts(profile string, regions []string, k8sTags []string) []VMInfo {
	log.Debugf("start getAgentVMCounts\n")
	start := time.Now()

	numFuncs := 0
	channel := make(chan []VMInfo)
	var serviceCountList []VMInfo
	for _, r := range regions {
		cfg := getSession(profile, r)
		//EC2s
		numFuncs += 1
		go func(r string, tags []string) {
			channel <- getEC2InstancesByRegion(*cfg, r, tags)
		}(r, k8sTags)
	}

	for i := 0; i < numFuncs; i++ {
		vms := <-channel
		serviceCountList = append(serviceCountList, vms...)
	}

	elapsed := time.Since(start)
	log.Debugf("end getAgentVMCounts - %s\n", elapsed)

	return serviceCountList
}

func getECSVMCounts(profile string, regions []string) []VMInfo {
	log.Debugf("start getECSVMCounts\n")
	start := time.Now()

	numFuncs := 0
	channel := make(chan []VMInfo)
	var serviceCountList []VMInfo
	for _, r := range regions {
		cfg := getSession(profile, r)
		//ECS EC2s
		numFuncs += 1
		go func(r string) {
			channel <- getECSVMCountByRegion(*cfg, r)
		}(r)
	}

	for i := 0; i < numFuncs; i++ {
		vms := <-channel
		serviceCountList = append(serviceCountList, vms...)
	}

	elapsed := time.Since(start)
	log.Debugf("end getECSVMCounts - %s\n", elapsed)

	return serviceCountList
}

func getECSVMCountByRegion(cfg aws.Config, region string) []VMInfo {
	service := ecs.NewFromConfig(cfg)
	var instances []VMInfo
	output, err := service.ListClusters(context.TODO(), &ecs.ListClustersInput{})

	if err != nil {
		log.Errorln("getECSVMCountByRegion ListClusters ", region, err)
	} else {
		for _, cluster := range output.ClusterArns {
			output, err := service.ListContainerInstances(context.TODO(), &ecs.ListContainerInstancesInput{
				Cluster: &cluster,
			})

			if err != nil {
				log.Errorln("getECSVMCountByRegion ListContainerInstances ", region, err)
			} else {
				for _, cia := range output.ContainerInstanceArns {
					output, err := service.DescribeContainerInstances(context.TODO(), &ecs.DescribeContainerInstancesInput{
						Cluster:            &cluster,
						ContainerInstances: []string{cia},
					})

					if err != nil {
						log.Errorln("getECSVMCountByRegion DescribeContainerInstances ", region, err)
					} else {
						//log.Debugln("ECS EC2 Instances", output.ContainerInstances)
						for _, i := range output.ContainerInstances {
							log.Debugln("ECS VM ID", region, *i.Ec2InstanceId)
							instances = append(instances, VMInfo{Region: region, AMI: *i.Ec2InstanceId, AgentType: ENTERPRISE_AGENT})
						}
					}
				}
			}
		}
	}

	return instances
}

func getEC2InstancesByRegion(cfg aws.Config, region string, k8sTags []string) []VMInfo {
	service := ec2.NewFromConfig(cfg)
	output := ec2.NewDescribeInstancesPaginator(service, &ec2.DescribeInstancesInput{
		Filters: []ec2Types.Filter{{Name: aws.String("instance-state-name"), Values: []string{"running", "pending", "stopped"}}},
	})

	instances := []VMInfo{}
	for output.HasMorePages() {

		page, err := output.NextPage(context.TODO())
		if err != nil {
			log.Errorln("getEC2InstancesByRegion DescribeInstances ", region, err)
		} else {
			for _, res := range page.Reservations {
				for _, i := range res.Instances {
					agentType := STANDARD_AGENT
					log.Debugln("Looking for user provided k8s tags", k8sTags)
					for _, t := range i.Tags {
						log.Debugf("Instance: %s, tag: %s", *i.InstanceId, *t.Key)
						if helpers.Contains(k8sTags, *t.Key) {
							log.Debugln("found EKS node")
							agentType = ENTERPRISE_AGENT
						}
						//if *t.Key == "eks:cluster-name" || *t.Key == "aws:eks:cluster-name" {
						//
						//}
					}
					instances = append(instances, VMInfo{Region: region, AMI: *i.InstanceId, AgentType: agentType, OS: *i.PlatformDetails, AccountId: *res.OwnerId})
				}
			}
		}
	}

	return instances
}

func getRDSInstanceCountByRegion(cfg aws.Config, region string) AgentlessServiceCount {
	service := rds.NewFromConfig(cfg)
	output := rds.NewDescribeDBInstancesPaginator(service, &rds.DescribeDBInstancesInput{})

	instanceCount := 0
	for output.HasMorePages() {
		page, err := output.NextPage(context.TODO())
		if err != nil {
			log.Errorln("getRDSInstanceCountByRegion DescribeDBInstances ", region, err)
		} else {
			instanceCount += len(page.DBInstances)
		}
	}

	return AgentlessServiceCount{
		Region:  region,
		Service: RDS,
		Count:   instanceCount,
	}
}

func getRedshiftInstanceCountByRegion(cfg aws.Config, region string) AgentlessServiceCount {
	service := redshift.NewFromConfig(cfg)
	output := redshift.NewDescribeClustersPaginator(service, &redshift.DescribeClustersInput{})

	instanceCount := 0
	for output.HasMorePages() {
		page, err := output.NextPage(context.TODO())
		if err != nil {
			log.Errorln("getRedshiftInstanceCountByRegion DescribeClusters ", region, err)
		} else {
			instanceCount += len(page.Clusters)
		}
	}

	return AgentlessServiceCount{
		Region:  region,
		Service: REDSHIFT,
		Count:   instanceCount,
	}
}

func getELBv1InstanceCountByRegion(cfg aws.Config, region string) AgentlessServiceCount {
	service := elasticloadbalancing.NewFromConfig(cfg)
	output := elasticloadbalancing.NewDescribeLoadBalancersPaginator(service, &elasticloadbalancing.DescribeLoadBalancersInput{})

	instanceCount := 0
	for output.HasMorePages() {
		page, err := output.NextPage(context.TODO())
		if err != nil {
			log.Errorln("getELBv1InstanceCountByRegion DescribeLoadBalancers ", region, err)
		} else {
			instanceCount += len(page.LoadBalancerDescriptions)
		}
	}

	return AgentlessServiceCount{
		Region:  region,
		Service: ELBv1,
		Count:   instanceCount,
	}
}

func getELBv2InstanceCountByRegion(cfg aws.Config, region string) AgentlessServiceCount {
	service := elasticloadbalancingv2.NewFromConfig(cfg)
	output := elasticloadbalancingv2.NewDescribeLoadBalancersPaginator(service, &elasticloadbalancingv2.DescribeLoadBalancersInput{})

	instanceCount := 0
	for output.HasMorePages() {
		page, err := output.NextPage(context.TODO())
		if err != nil {
			log.Errorln("getELBv2InstanceCountByRegion DescribeLoadBalancers ", region, err)
		} else {
			instanceCount += len(page.LoadBalancers)
		}
	}

	return AgentlessServiceCount{
		Region:  region,
		Service: ELBv2,
		Count:   instanceCount,
	}
}

func getNatGatewayInstanceCountByRegion(cfg aws.Config, region string) AgentlessServiceCount {
	service := ec2.NewFromConfig(cfg)
	output := ec2.NewDescribeNatGatewaysPaginator(service, &ec2.DescribeNatGatewaysInput{})

	instanceCount := 0
	for output.HasMorePages() {
		page, err := output.NextPage(context.TODO())
		if err != nil {
			log.Errorln("getNatGatewayInstanceCountByRegion DescribeNatGateways ", region, err)
		} else {
			instanceCount += len(page.NatGateways)
		}
	}

	return AgentlessServiceCount{
		Region:  region,
		Service: NATGATEWAY,
		Count:   instanceCount,
	}
}

func ParseProfiles(cmd *cobra.Command) []string {
	profilesFlag := helpers.GetFlagEnvironmentString(cmd, "profile", "profile", "Missing Profile(s) to use", false)
	var profiles []string
	if profilesFlag != "" {
		profilesTemp := strings.Split(profilesFlag, ",")
		for _, p := range profilesTemp {
			trimmed := strings.TrimSpace((p))
			profiles = append(profiles, trimmed)
		}
	} else {
		profiles = append(profiles, "default")
	}
	return profiles
}

func ParseTags(cmd *cobra.Command) []string {
	tagsFlag := helpers.GetFlagEnvironmentString(cmd, "tags", "tags", "Missing tags to use", false)
	tags := []string{"eks:cluster-name", "aws:eks:cluster-name"}
	if tagsFlag != "" {
		tagsTemp := strings.Split(tagsFlag, ",")
		for _, tag := range tagsTemp {
			trimmed := strings.TrimSpace(tag)
			tags = append(tags, trimmed)
		}
	}
	return tags
}

func ParseRegions(cmd *cobra.Command) []string {
	regionsFlag := helpers.GetFlagEnvironmentString(cmd, "region", "region", "Missing Region(s) to use", false)
	var regions []string
	if regionsFlag != "" {
		profilesTemp := strings.Split(regionsFlag, ",")
		for _, p := range profilesTemp {
			trimmed := strings.TrimSpace(p)
			regions = append(regions, trimmed)
		}
	}
	return regions
}
