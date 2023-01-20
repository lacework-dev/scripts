package lwaws

import (
	"context"
	"fmt"
	"github.com/aws/aws-sdk-go-v2/service/ecs"
	"math"
	"strconv"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	ec2Types "github.com/aws/aws-sdk-go-v2/service/ec2/types"
	ecsTypes "github.com/aws/aws-sdk-go-v2/service/ecs/types"
	"github.com/lacework-dev/scripts/lw-inventory/helpers"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
)

type InstanceType struct {
	Name   string
	vCPU   int32
	Region string
}

type EC2VMInfo struct {
	Region       string
	AMI          string
	AccountId    string
	AgentType    string
	OS           string
	vCPU         int32
	InstanceType string
}

type OSCounts struct {
	Windows int
	Linux   int
}

type ContainerClusterInfo struct {
	Region        string
	ContainerType string
	vCPU          float64
	ClusterName   string
	AccountId     string
}

const (
	FARGATE_RUNNING_CONTAINERS = "Fargate Running Containers"
)

func Run(profiles []string, regions []string, debug bool) {
	if debug {
		log.SetLevel(log.DebugLevel)
	}

	fmt.Println("Beginning Scan")
	fmt.Printf("Profiles to use: %s\n", profiles)

	var totalvCPU int32
	accountVMVCPUS := make(map[string]int32)
	accountContainerVCPUS := make(map[string]int32)
	var totalVMOSCounts OSCounts

	for _, p := range profiles {
		fmt.Println("Using profile", p)

		cfg := getSession(p, "us-east-1")

		if len(regions) == 0 {
			regions = getRegions(*cfg)
		}
		fmt.Printf("Scanning regions: %s\n", regions)

		instanceTypes := getInstanceTypes(p, regions)
		ec2InstanceInfo := getEC2Instances(p, regions)
		containerInfo := getContainerInfo(p, regions)

		//allVMs = append(allVMs, ec2InstanceInfo...)

		var vmOSCounts OSCounts
		var accountIds []string
		var vmAccountData = make(map[string][]EC2VMInfo)
		var containervCPUData = make(map[string]float64)
		for _, vm := range ec2InstanceInfo {
			for _, it := range instanceTypes {
				if it.Region == vm.Region && it.Name == vm.InstanceType {
					vm.vCPU = it.vCPU
					vmAccountData[vm.AccountId] = append(vmAccountData[vm.AccountId], vm)

				}
			}
			if vm.OS == "Linux/UNIX" {
				vmOSCounts.Linux++
			} else {
				vmOSCounts.Windows++
			}

			if !helpers.Contains(accountIds, vm.AccountId) {
				accountIds = append(accountIds, vm.AccountId)
			}
		}

		for _, container := range containerInfo {
			containervCPUData[container.AccountId] = containervCPUData[container.AccountId] + container.vCPU
		}

		totalVMOSCounts.Linux += vmOSCounts.Linux
		totalVMOSCounts.Windows += vmOSCounts.Windows

		for account, vms := range vmAccountData {
			for _, vm := range vms {
				accountVMVCPUS[account] += vm.vCPU
				totalvCPU += vm.vCPU
			}
		}

		for account, vcpu := range containervCPUData {
			vcpus := int32(math.Round(vcpu))
			accountContainerVCPUS[account] += vcpus
			totalvCPU += vcpus
		}

		fmt.Println("----------------------------------------------")
		fmt.Printf("AWS vCPUs %d for profile %s\n", totalvCPU, p)

		fmt.Println("\nAccount Breakdown")
		for account, vcpus := range accountVMVCPUS {
			fmt.Printf("Account VM vCPUs: %s - %d\n", account, vcpus)
		}

		for account, vcpus := range accountContainerVCPUS {
			fmt.Printf("Account Container vCPUs: %s - %d\n", account, vcpus)
		}

		fmt.Println("\nVM OS Counts")
		fmt.Printf("Linux VMs %d\n", vmOSCounts.Linux)
		fmt.Printf("Windows VMs %d\n", vmOSCounts.Windows)

		fmt.Println("\nNumber of AWS Accounts Inventoried:", len(accountIds))
		fmt.Println("----------------------------------------------")
	}

	//var totalvCPU int32
	//accountVMVCPUS := make(map[string]int32)
	//for account, vms := range accountData {
	//	for _, vm := range vms {
	//		accountVMVCPUS[account] += vm.vCPU
	//		totalvCPU += vm.vCPU
	//	}
	//}

	fmt.Println("----------------------------------------------")
	fmt.Printf("Total AWS vCPUs %d\n", totalvCPU)

	fmt.Println("\nAccount Breakdown")
	for account, vcpus := range accountVMVCPUS {
		fmt.Printf("Account: %s - %d\n", account, vcpus)
	}

	fmt.Println("\nVM OS Counts")
	fmt.Printf("Linux VMs %d\n", totalVMOSCounts.Linux)
	fmt.Printf("Windows VMs %d\n", totalVMOSCounts.Windows)

	fmt.Println("\nNumber of AWS Accounts inventoried:", len(accountVMVCPUS))
	fmt.Println("----------------------------------------------")
}

func getSession(profile string, region string) *aws.Config {
	cfg, err := config.LoadDefaultConfig(context.TODO(),
		config.WithRegion(region),
		config.WithSharedConfigProfile(profile),
		config.WithDefaultsMode(aws.DefaultsModeInRegion),
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

func getInstanceTypesByRegion(cfg aws.Config, region string) []InstanceType {
	var instanceTypes []InstanceType
	//log.Println("aws cfg", cfg)

	service := ec2.NewFromConfig(cfg)
	output := ec2.NewDescribeInstanceTypesPaginator(service, &ec2.DescribeInstanceTypesInput{})

	for output.HasMorePages() {
		page, err := output.NextPage(context.TODO())
		if err != nil {
			log.Errorln("getInstanceTypes NewDescribeInstanceTypesPaginator ", region, err)
		} else {
			for _, it := range page.InstanceTypes {
				//fmt.Println(it.InstanceType, it.VCpuInfo.DefaultVCpus, region)
				instanceTypes = append(instanceTypes, InstanceType{
					Name:   fmt.Sprintf("%s", it.InstanceType),
					vCPU:   *it.VCpuInfo.DefaultVCpus,
					Region: region,
				})
			}
		}
	}

	return instanceTypes
}

func getInstanceTypes(profile string, regions []string) []InstanceType {
	log.Debugf("start getInstanceTypes\n")
	start := time.Now()

	numFuncs := 0
	channel := make(chan []InstanceType)
	var instanceTypes []InstanceType
	for _, r := range regions {
		cfg := getSession(profile, r)
		//Instance Types
		numFuncs += 1
		go func(r string) {
			channel <- getInstanceTypesByRegion(*cfg, r)
		}(r)
	}

	for i := 0; i < numFuncs; i++ {
		instanceTypesPerRegion := <-channel
		instanceTypes = append(instanceTypes, instanceTypesPerRegion...)
	}

	elapsed := time.Since(start)
	log.Debugf("end getInstanceTypes - %s\n", elapsed)

	return instanceTypes
}

func getEC2Instances(profile string, regions []string) []EC2VMInfo {
	log.Debugf("start getEC2Instances\n")
	start := time.Now()

	numFuncs := 0
	channel := make(chan []EC2VMInfo)
	var serviceCountList []EC2VMInfo
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
	log.Debugf("end getEC2Instances - %s\n", elapsed)

	return serviceCountList
}

func getContainerInfo(profile string, regions []string) []ContainerClusterInfo {
	log.Debugf("start getContainer\n")
	start := time.Now()

	numFuncs := 0
	channel := make(chan []ContainerClusterInfo)
	var containerList []ContainerClusterInfo

	for _, r := range regions {
		cfg := getSession(profile, r)
		//ECS Tasks
		//numFuncs += 1
		//go func(r string) {
		//	channel <- getECSTaskDefinitionsByRegion(*cfg, r)
		//}(r)
		//
		////Running Fargate Tasks
		//numFuncs += 1
		//go func(r string) {
		//	channel <- getECSFargateRunningTasksByRegion(*cfg, r)
		//}(r)

		//Running Fargate Containers
		numFuncs += 1
		go func(r string) {
			channel <- getECSFargateRunningContainersByRegion(*cfg, r)
		}(r)

		////Total Fargate Containers
		//numFuncs += 1
		//go func(r string) {
		//	channel <- getECSFargateTotalContainersByRegion(*cfg, r)
		//}(r)
		//
		//numFuncs += 1
		//go func(r string) {
		//	channel <- getEKSFargateActiveProfilesByRegion(*cfg, r)
		//}(r)
		//
		//numFuncs += 1
		//go func(r string) {
		//	channel <- getECSFargateActiveServicesByRegion(*cfg, r)
		//}(r)
	}

	for i := 0; i < numFuncs; i++ {
		containers := <-channel
		containerList = append(containerList, containers...)
	}

	elapsed := time.Since(start)
	log.Debugf("end getContainer - %s\n", elapsed)

	return containerList
}

func getECSFargateRunningContainersByRegion(cfg aws.Config, region string) []ContainerClusterInfo {
	service := ecs.NewFromConfig(cfg)
	output := ecs.NewListClustersPaginator(service, &ecs.ListClustersInput{})

	var allClusterInfo []ContainerClusterInfo
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
					//var clusterInfo ContainerClusterInfo
					//clusterInfo.ClusterName = page.
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
												vcpu, _ := strconv.ParseFloat(*t.Cpu, 32)
												clusterPieces := strings.Split(cluster, ":")
												//println(clusterPieces)
												clusterInfo := ContainerClusterInfo{
													Region:        region,
													ContainerType: FARGATE_RUNNING_CONTAINERS,
													vCPU:          vcpu / 1024,
													ClusterName:   cluster,
													AccountId:     clusterPieces[4],
												}
												allClusterInfo = append(allClusterInfo, clusterInfo)
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

	return allClusterInfo
}

//func getContainerEC2Instances(profile string, regions []string) []EC2VMInfo {
//	log.Debugf("start getContainerEC2Instances\n")
//	start := time.Now()
//
//	numFuncs := 0
//	channel := make(chan []EC2VMInfo)
//	var serviceCountList []EC2VMInfo
//	for _, r := range regions {
//		cfg := getSession(profile, r)
//		//ECS EC2s
//		numFuncs += 1
//		go func(r string) {
//			channel <- getECSVMCountByRegion(cfg, r)
//		}(r)
//
//		//EKS EC2s
//		numFuncs += 1
//		go func(r string) {
//			channel <- getEKSVMCountByRegion(cfg, r)
//		}(r)
//	}
//
//	for i := 0; i < numFuncs; i++ {
//		vms := <-channel
//		serviceCountList = append(serviceCountList, vms...)
//	}
//
//	elapsed := time.Since(start)
//	log.Debugf("end getContainerEC2Instances - %s\n", elapsed)
//
//	return serviceCountList
//}

//func getEKSVMCountByRegion(cfg aws.Config, region string) []EC2VMInfo {
//	service := eks.NewFromConfig(cfg)
//	autoscalingService := autoscaling.NewFromConfig(cfg)
//
//	var instances []EC2VMInfo
//	output, err := service.ListClusters(context.TODO(), &eks.ListClustersInput{})
//
//	if err != nil {
//		log.Errorln("getEKSVMCountByRegion ListClusters ", region, err)
//	} else {
//		for _, cluster := range output.Clusters {
//			output, err := service.ListNodegroups(context.TODO(), &eks.ListNodegroupsInput{
//				ClusterName: &cluster,
//			})
//			if err != nil {
//				log.Errorln("getEKSVMCountByRegion ListNodegroups ", region, err)
//			} else {
//				for _, nodegroup := range output.Nodegroups {
//					output, err := service.DescribeNodegroup(context.TODO(), &eks.DescribeNodegroupInput{
//						ClusterName:   &cluster,
//						NodegroupName: &nodegroup,
//					})
//					if err != nil {
//						log.Errorln("getEKSVMCountByRegion DescribeNodegroup ", region, err)
//					} else {
//						var asgNames []string
//						for _, autoscalingGroup := range output.Nodegroup.Resources.AutoScalingGroups {
//							asgNames = append(asgNames, *autoscalingGroup.Name)
//						}
//
//						outputDASG, err := autoscalingService.DescribeAutoScalingGroups(context.TODO(), &autoscaling.DescribeAutoScalingGroupsInput{
//							AutoScalingGroupNames: asgNames,
//						})
//
//						if err != nil {
//							log.Errorln("getEKSVMCountByRegion DescribeAutoScalingGroups ", region, err)
//						} else {
//							for _, asg := range outputDASG.AutoScalingGroups {
//								for _, i := range asg.Instances {
//									role := fmt.Sprintf("%s", *output.Nodegroup.NodeRole)
//									instances = append(instances, EC2VMInfo{Region: region, AMI: *i.InstanceId, InstanceType: *i.InstanceType, AccountId: role[13:25]})
//								}
//							}
//						}
//					}
//				}
//			}
//		}
//	}
//
//	return instances
//}

//func getECSVMCountByRegion(cfg aws.Config, region string) []EC2VMInfo {
//	service := ecs.NewFromConfig(cfg)
//	var instances []EC2VMInfo
//	output, err := service.ListClusters(context.TODO(), &ecs.ListClustersInput{})
//
//	if err != nil {
//		log.Errorln("getECSVMCountByRegion ListClusters ", region, err)
//	} else {
//		for _, cluster := range output.ClusterArns {
//			output, err := service.ListContainerInstances(context.TODO(), &ecs.ListContainerInstancesInput{
//				Cluster: &cluster,
//			})
//
//			if err != nil {
//				log.Errorln("getECSVMCountByRegion ListContainerInstances ", region, err)
//			} else {
//				for _, cia := range output.ContainerInstanceArns {
//					output, err := service.DescribeContainerInstances(context.TODO(), &ecs.DescribeContainerInstancesInput{
//						Cluster:            &cluster,
//						ContainerInstances: []string{cia},
//					})
//
//					if err != nil {
//						log.Errorln("getECSVMCountByRegion DescribeContainerInstances ", region, err)
//					} else {
//						for _, i := range output.ContainerInstances {
//							parts := strings.Split(*i.ContainerInstanceArn, ":")
//							accountId := parts[4]
//							instances = append(instances, EC2VMInfo{Region: region, AMI: *i.Ec2InstanceId, AccountId: accountId})
//						}
//					}
//				}
//			}
//		}
//	}
//
//	return instances
//}

func getEC2InstancesByRegion(cfg aws.Config, region string) []EC2VMInfo {
	service := ec2.NewFromConfig(cfg)
	output := ec2.NewDescribeInstancesPaginator(service, &ec2.DescribeInstancesInput{
		Filters: []ec2Types.Filter{{Name: aws.String("instance-state-name"), Values: []string{"running", "pending", "stopped"}}},
	})

	var instances []EC2VMInfo
	for output.HasMorePages() {

		page, err := output.NextPage(context.TODO())
		if err != nil {
			log.Errorln("getEC2InstancesByRegion DescribeInstances ", region, err)
		} else {
			for _, res := range page.Reservations {
				for _, i := range res.Instances {
					if *res.OwnerId != "" {
						instances = append(instances, EC2VMInfo{Region: region, AMI: *i.InstanceId, OS: *i.PlatformDetails, AccountId: *res.OwnerId, InstanceType: fmt.Sprintf("%s", i.InstanceType)})
					}
				}
			}
		}
	}

	return instances
}

func ParseProfiles(cmd *cobra.Command) []string {
	profilesFlag := helpers.GetFlagEnvironmentString(cmd, "profile", "profile", "Missing Profile(s) to use", false)
	var profiles []string
	if profilesFlag != "" {
		profilesTemp := strings.Split(profilesFlag, ",")
		for _, p := range profilesTemp {
			trimmed := strings.TrimSpace(p)
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
