package lwaws

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/autoscaling"
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

type AgentVMInfo struct {
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

func Run(profiles []string, regions []string, debug bool) {
	if debug {
		log.SetLevel(log.DebugLevel)
	}

	fmt.Println("Beginning Scan")
	fmt.Printf("Profiles to use: %s\n", profiles)

	totalResources := 0
	var totalStandardOSCount OSCounts
	var totalEnterpriseOSCount OSCounts
	totalAccounts := 0

	//loop over all profiles and get counts
	for _, p := range profiles {
		var agentlessCounts []AgentlessServiceCount
		var ec2VMInfo []AgentVMInfo
		var enterpriseAgentVMInfo []AgentVMInfo
		var agentContainers []AgentContainerCount
		fmt.Println("Using profile", p)

		cfg := getSession(p, "us-east-1")

		if len(regions) == 0 {
			regions = getRegions(*cfg)
		}
		fmt.Printf("Scanning regions: %s\n", regions)

		agentlessCounts = getAgentlessCounts(p, regions)
		ec2VMInfo = getAgentVMCounts(p, regions)
		enterpriseAgentVMInfo = getEnterpriseAgentVMCounts(p, regions)
		agentContainers = getAgentContainerCounts(p, regions)

		//run through each region
		agentlessResourceCount := 0
		agentContainerCount := make(map[string]int)
		standardAgents := []string{}
		enterpriseAgents := []string{}
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
		var amis []string
		for _, vm := range ec2VMInfo {
			amis = append(amis, vm.AMI)
		}

		for _, vm := range enterpriseAgentVMInfo {
			if vm.AgentType == ENTERPRISE_AGENT {
				enterpriseAgents = append(enterpriseAgents, vm.AMI)
			}

			//sometimes instances for EKS/ECS don't show up in EC2 list...might be offline or managed instances in ECS
			if !helpers.Contains(amis, vm.AMI) {
				log.Printf("Instance not in EC2 instance list %s %s", vm.AMI, vm.Region)
			}
		}

		var accountIds []string
		for _, vm := range ec2VMInfo {
			if !helpers.Contains(accountIds, vm.AccountId) {
				accountIds = append(accountIds, vm.AccountId)
			}
		}
		for _, vm := range ec2VMInfo {
			agentlessResourceCount++
			if !helpers.Contains(enterpriseAgents, vm.AMI) {
				standardAgents = append(standardAgents, vm.AMI)
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
		totalStandardOSCount.Linux += standardAgentOSCounts.Linux
		totalStandardOSCount.Windows += standardAgentOSCounts.Windows
		totalEnterpriseOSCount.Linux += enterpriseAgentOSCounts.Linux
		totalEnterpriseOSCount.Windows += enterpriseAgentOSCounts.Windows
		totalAccounts += len(accountIds)

		fmt.Println("----------------------------------------------")
		fmt.Println("Totals for profile", p)
		fmt.Printf("Total Resources  %d\n", agentlessResourceCount)
		fmt.Printf("Standard VM Agents: %d\n", len(standardAgents))
		fmt.Printf("Enterprise VM Agents: %d\n", len(enterpriseAgents))
		for s, c := range agentContainerCount {
			fmt.Printf("%s: %d\n", s, c)
		}

		fmt.Println("\nVM OS Counts")
		fmt.Printf("Standard Linux VMs %d\n", standardAgentOSCounts.Linux)
		fmt.Printf("Standard Windows VMs %d\n", standardAgentOSCounts.Windows)
		fmt.Printf("Enterprise Linux VMs %d\n", enterpriseAgentOSCounts.Linux)
		fmt.Printf("Enterprise Windows VMs %d\n", enterpriseAgentOSCounts.Windows)

		fmt.Println("\nNumber of AWS Accounts inventoried:", len(accountIds))
		fmt.Println("----------------------------------------------")
	}

	fmt.Println("----------------------------------------------")
	fmt.Println("Totals for all profiles")
	fmt.Printf("Total Resources  %d\n", totalResources)
	fmt.Printf("Standard VM Agents: %d\n", totalStandardOSCount.Linux+totalStandardOSCount.Windows)
	fmt.Printf("Enterprise VM Agents: %d\n", totalEnterpriseOSCount.Linux+totalEnterpriseOSCount.Windows)

	fmt.Println("\nVM OS Counts")
	fmt.Printf("Standard Linux VMs %d\n", totalStandardOSCount.Linux)
	fmt.Printf("Standard Windows VMs %d\n", totalStandardOSCount.Windows)
	fmt.Printf("Enterprise Linux VMs %d\n", totalEnterpriseOSCount.Linux)
	fmt.Printf("Enterprise Windows VMs %d\n", totalEnterpriseOSCount.Windows)

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
			channel <- getFargateRunningTasksByRegion(*cfg, r)
		}(r)

		//Running Fargate Containers
		numFuncs += 1
		go func(r string) {
			channel <- getFargateRunningContainersByRegion(*cfg, r)
		}(r)

		//Total Fargate Containers
		numFuncs += 1
		go func(r string) {
			channel <- getFargateTotalContainersByRegion(*cfg, r)
		}(r)

		numFuncs += 1
		go func(r string) {
			channel <- getEKSFargateActiveProfilesByRegion(*cfg, r)
		}(r)

		numFuncs += 1
		go func(r string) {
			channel <- getFargateActiveServicesByRegion(*cfg, r)
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

func getFargateRunningTasksByRegion(cfg aws.Config, region string) AgentContainerCount {
	service := ecs.NewFromConfig(cfg)
	output := ecs.NewListClustersPaginator(service, &ecs.ListClustersInput{})

	taskCount := 0
	for output.HasMorePages() {
		page, err := output.NextPage(context.TODO())
		if err != nil {
			log.Errorln("getFargateRunningTasksByRegion ListClusters ", region, err)
		} else {
			for _, cluster := range page.ClusterArns {
				output := ecs.NewListTasksPaginator(service, &ecs.ListTasksInput{
					Cluster: &cluster,
				})
				for output.HasMorePages() {
					page, err := output.NextPage(context.TODO())
					if err != nil {
						log.Errorln("getFargateRunningTasksByRegion ListTasks ", region, err)
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

func getFargateActiveServicesByRegion(cfg aws.Config, region string) AgentContainerCount {
	service := ecs.NewFromConfig(cfg)
	output := ecs.NewListClustersPaginator(service, &ecs.ListClustersInput{})

	count := 0
	for output.HasMorePages() {
		page, err := output.NextPage(context.TODO())
		if err != nil {
			log.Errorln("getFargateActiveServicesByRegion ListClusters ", region, err)
		} else {
			output, err := service.DescribeClusters(context.TODO(), &ecs.DescribeClustersInput{
				Clusters: page.ClusterArns,
			})

			if err != nil {
				log.Errorln("getFargateActiveServicesByRegion DescribeClusters ", region, err)
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

func getFargateRunningContainersByRegion(cfg aws.Config, region string) AgentContainerCount {
	service := ecs.NewFromConfig(cfg)
	output := ecs.NewListClustersPaginator(service, &ecs.ListClustersInput{})

	taskCount := 0
	for output.HasMorePages() {
		page, err := output.NextPage(context.TODO())
		if err != nil {
			log.Errorln("getFargateRunningContainersByRegion ListClusters ", region, err)
		} else {
			for _, cluster := range page.ClusterArns {
				output := ecs.NewListTasksPaginator(service, &ecs.ListTasksInput{
					Cluster: &cluster,
				})
				for output.HasMorePages() {
					page, err := output.NextPage(context.TODO())
					if err != nil {
						log.Errorln("getFargateRunningContainersByRegion ListTasks ", region, err)
					} else {
						if len(page.TaskArns) > 0 {
							outputDT, err := service.DescribeTasks(context.TODO(), &ecs.DescribeTasksInput{
								Cluster: &cluster,
								Tasks:   page.TaskArns,
							})
							if err != nil {
								log.Errorln("getFargateRunningContainersByRegion DescribeTasks ", region, err)
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

func getFargateTotalContainersByRegion(cfg aws.Config, region string) AgentContainerCount {
	service := ecs.NewFromConfig(cfg)
	output := ecs.NewListClustersPaginator(service, &ecs.ListClustersInput{})

	taskCount := 0
	for output.HasMorePages() {
		page, err := output.NextPage(context.TODO())
		if err != nil {
			log.Errorln("getFargateTotalContainersByRegion ListClusters ", region, err)
		} else {
			for _, cluster := range page.ClusterArns {
				output := ecs.NewListTasksPaginator(service, &ecs.ListTasksInput{
					Cluster: &cluster,
				})
				for output.HasMorePages() {
					page, err := output.NextPage(context.TODO())
					if err != nil {
						log.Errorln("getFargateTotalContainersByRegion ListTasks ", region, err)
					} else {
						if len(page.TaskArns) > 0 {
							outputDT, err := service.DescribeTasks(context.TODO(), &ecs.DescribeTasksInput{
								Cluster: &cluster,
								Tasks:   page.TaskArns,
							})
							if err != nil {
								log.Errorln("getFargateTotalContainersByRegion DescribeTasks ", region, err)
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

func getAgentVMCounts(profile string, regions []string) []AgentVMInfo {
	log.Debugf("start getAgentVMCounts\n")
	start := time.Now()

	numFuncs := 0
	channel := make(chan []AgentVMInfo)
	var serviceCountList []AgentVMInfo
	for _, r := range regions {
		cfg := getSession(profile, r)
		//EC2s
		numFuncs += 1
		go func(r string) {
			channel <- getEC2InstancesByRegion(*cfg, r)
		}(r)
	}

	for i := 0; i < numFuncs; i++ {
		vms := <-channel
		serviceCountList = append(serviceCountList, vms...)
	}

	elapsed := time.Since(start)
	log.Debugf("end getAgentVMCounts - %s\n", elapsed)

	return serviceCountList
}

func getEnterpriseAgentVMCounts(profile string, regions []string) []AgentVMInfo {
	log.Debugf("start getEnterpriseAgentVMCounts\n")
	start := time.Now()

	numFuncs := 0
	channel := make(chan []AgentVMInfo)
	var serviceCountList []AgentVMInfo
	for _, r := range regions {
		cfg := getSession(profile, r)
		//ECS EC2s
		numFuncs += 1
		go func(r string) {
			channel <- getECSVMCountByRegion(*cfg, r)
		}(r)

		//EKS EC2s
		numFuncs += 1
		go func(r string) {
			channel <- getEKSVMCountByRegion(*cfg, r)
		}(r)
	}

	for i := 0; i < numFuncs; i++ {
		vms := <-channel
		serviceCountList = append(serviceCountList, vms...)
	}

	elapsed := time.Since(start)
	log.Debugf("end getEnterpriseAgentVMCounts - %s\n", elapsed)

	return serviceCountList
}

func getEKSVMCountByRegion(cfg aws.Config, region string) []AgentVMInfo {
	service := eks.NewFromConfig(cfg)
	autoscalingService := autoscaling.NewFromConfig(cfg)

	var instances []AgentVMInfo
	output, err := service.ListClusters(context.TODO(), &eks.ListClustersInput{})

	if err != nil {
		log.Errorln("getEKSVMCountByRegion ListClusters ", region, err)
	} else {
		for _, cluster := range output.Clusters {
			output, err := service.ListNodegroups(context.TODO(), &eks.ListNodegroupsInput{
				ClusterName: &cluster,
			})
			if err != nil {
				log.Errorln("getEKSVMCountByRegion ListNodegroups ", region, err)
			} else {
				for _, nodegroup := range output.Nodegroups {
					output, err := service.DescribeNodegroup(context.TODO(), &eks.DescribeNodegroupInput{
						ClusterName:   &cluster,
						NodegroupName: &nodegroup,
					})
					if err != nil {
						log.Errorln("getEKSVMCountByRegion DescribeNodegroup ", region, err)
					} else {
						var asgNames []string
						if output.Nodegroup.Resources != nil {
							for _, autoscalingGroup := range output.Nodegroup.Resources.AutoScalingGroups {
								asgNames = append(asgNames, *autoscalingGroup.Name)
							}

							outputDASG, err := autoscalingService.DescribeAutoScalingGroups(context.TODO(), &autoscaling.DescribeAutoScalingGroupsInput{
								AutoScalingGroupNames: asgNames,
							})

							if err != nil {
								log.Errorln("getEKSVMCountByRegion DescribeAutoScalingGroups ", region, err)
							} else {
								for _, asg := range outputDASG.AutoScalingGroups {
									for _, i := range asg.Instances {
										instances = append(instances, AgentVMInfo{Region: region, AMI: *i.InstanceId, AgentType: ENTERPRISE_AGENT})
									}
								}
							}
						}

					}
				}
			}
		}
	}

	return instances
}

func getECSVMCountByRegion(cfg aws.Config, region string) []AgentVMInfo {
	service := ecs.NewFromConfig(cfg)
	var instances []AgentVMInfo
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
						for _, i := range output.ContainerInstances {
							instances = append(instances, AgentVMInfo{Region: region, AMI: *i.Ec2InstanceId, AgentType: ENTERPRISE_AGENT})
						}
					}
				}
			}
		}
	}

	return instances
}

func getEC2InstanceCountByRegion(cfg aws.Config, region string) AgentlessServiceCount {
	ec2Instances := getEC2InstancesByRegion(cfg, region)

	return AgentlessServiceCount{
		Region:  region,
		Service: EC2,
		Count:   len(ec2Instances),
	}
}

func getEC2InstancesByRegion(cfg aws.Config, region string) []AgentVMInfo {
	service := ec2.NewFromConfig(cfg)
	output := ec2.NewDescribeInstancesPaginator(service, &ec2.DescribeInstancesInput{
		Filters: []ec2Types.Filter{{Name: aws.String("instance-state-name"), Values: []string{"running", "pending", "stopped"}}},
	})

	instances := []AgentVMInfo{}
	for output.HasMorePages() {

		page, err := output.NextPage(context.TODO())
		if err != nil {
			log.Errorln("getEC2InstancesByRegion DescribeInstances ", region, err)
		} else {
			for _, res := range page.Reservations {
				for _, i := range res.Instances {
					//log.Info("platform ", i.Platform)
					//log.Info("platform details ", *i.PlatformDetails)
					instances = append(instances, AgentVMInfo{Region: region, AMI: *i.InstanceId, AgentType: STANDARD_AGENT, OS: *i.PlatformDetails, AccountId: *res.OwnerId})
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
