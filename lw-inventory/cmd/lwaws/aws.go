package lwaws

import (
	"context"
	"fmt"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/aws/retry"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	ec2Types "github.com/aws/aws-sdk-go-v2/service/ec2/types"
	"github.com/aws/aws-sdk-go-v2/service/ecs"
	ecsTypes "github.com/aws/aws-sdk-go-v2/service/ecs/types"
	"github.com/aws/aws-sdk-go-v2/service/lambda"
	"github.com/lacework-dev/scripts/lw-inventory/helpers"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
	"math"
	"strconv"
	"strings"
	"time"
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

type LambdaInfo struct {
	Region    string
	Name      string
	Memory    int32
	vCPU      float64
	AccountId string
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
	totalAccountvCPUS := make(map[string]int32)
	accountContainerVCPUS := make(map[string]int32)
	accountLambdaVCPUS := make(map[string]int32)
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
		lambdaInfo := getLambdaInfo(p, regions)

		var vmOSCounts OSCounts
		var accountIds []string
		var vmAccountData = make(map[string][]EC2VMInfo)
		var containervCPUData = make(map[string]float64)
		var lambdavCPUData = make(map[string]float64)
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

		for _, lambda := range lambdaInfo {
			lambdavCPUData[lambda.AccountId] = lambdavCPUData[lambda.AccountId] + lambda.vCPU
		}

		totalVMOSCounts.Linux += vmOSCounts.Linux
		totalVMOSCounts.Windows += vmOSCounts.Windows

		for account, vms := range vmAccountData {
			for _, vm := range vms {
				accountVMVCPUS[account] += vm.vCPU
				totalAccountvCPUS[account] += vm.vCPU
				totalvCPU += vm.vCPU
			}
		}

		for account, vcpu := range containervCPUData {
			vcpus := int32(math.Round(vcpu))
			accountContainerVCPUS[account] += vcpus
			totalAccountvCPUS[account] += vcpus
			totalvCPU += vcpus
		}

		for account, vcpu := range containervCPUData {
			vcpus := int32(math.Round(vcpu))
			accountLambdaVCPUS[account] += vcpus
			totalAccountvCPUS[account] += vcpus
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

		for account, vcpus := range accountLambdaVCPUS {
			fmt.Printf("Account Lambda vCPUs: %s - %d\n", account, vcpus)
		}

		fmt.Println("\nVM OS Counts")
		fmt.Printf("Linux VMs %d\n", vmOSCounts.Linux)
		fmt.Printf("Windows VMs %d\n", vmOSCounts.Windows)

		fmt.Println("\nNumber of AWS Accounts Inventoried:", len(accountIds))
		fmt.Println("----------------------------------------------")
	}

	fmt.Println("----------------------------------------------")
	fmt.Printf("Total AWS vCPUs %d\n", totalvCPU)

	fmt.Println("\nAccount Breakdown")
	for account, vcpus := range totalAccountvCPUS {
		fmt.Printf("Account: %s - %d\n", account, vcpus)
	}

	//for account, vcpus := range totalAccountvCPUS {
	//	fmt.Printf("Account Lambda vCPUs: %s - %d\n", account, vcpus)
	//}
	//fmt.Println("Lambda counts not available at this time")

	fmt.Println("\nVM OS Counts")
	fmt.Printf("Linux VMs %d\n", totalVMOSCounts.Linux)
	fmt.Printf("Windows VMs %d\n", totalVMOSCounts.Windows)

	fmt.Println("\nNumber of AWS Accounts Inventoried:", len(accountVMVCPUS))
	fmt.Println("----------------------------------------------")
}

func getSession(profile string, region string) *aws.Config {
	cfg, err := config.LoadDefaultConfig(context.Background(),
		config.WithRegion(region),
		config.WithSharedConfigProfile(profile),
		//config.WithDefaultsMode(aws.DefaultsModeInRegion),
		config.WithRetryer(func() aws.Retryer {
			return retry.AddWithMaxAttempts(retry.NewStandard(), 1)
		}),
	)
	if err != nil {
		log.Errorln("Error connecting to AWS", err)
	}

	return &cfg
}

func getRegions(cfg aws.Config) []string {
	service := ec2.NewFromConfig(cfg)
	var regions []string
	regionsResponse, err := service.DescribeRegions(context.Background(), &ec2.DescribeRegionsInput{
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

func getLambdas(cfg aws.Config, region string) []LambdaInfo {
	service := lambda.NewFromConfig(cfg)
	output := lambda.NewListFunctionsPaginator(service, &lambda.ListFunctionsInput{})

	var lambdas []LambdaInfo
	for output.HasMorePages() {
		page, err := output.NextPage(context.Background())
		if err != nil {
			log.Errorln("getLambdas NewListFunctionsPaginator ", err)
		} else {
			for _, it := range page.Functions {
				clusterPieces := strings.Split(*it.FunctionArn, ":")
				lambdas = append(lambdas, LambdaInfo{
					Region:    region,
					Name:      *it.FunctionName,
					Memory:    *it.MemorySize,
					AccountId: clusterPieces[4],
					vCPU:      float64(*it.MemorySize) / 1024,
				})
			}
		}
	}
	return lambdas
}

func getInstanceTypesByRegion(cfg aws.Config, region string) []InstanceType {
	var instanceTypes []InstanceType

	service := ec2.NewFromConfig(cfg)
	output := ec2.NewDescribeInstanceTypesPaginator(service, &ec2.DescribeInstanceTypesInput{})

	for output.HasMorePages() {
		page, err := output.NextPage(context.Background())
		if err != nil {
			log.Errorln("getInstanceTypes NewDescribeInstanceTypesPaginator ", region, err)
			if strings.Contains(err.Error(), "credentials") {
				println("auth issue")
			}
		} else {
			for _, it := range page.InstanceTypes {
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
		//Running Fargate Containers
		numFuncs += 1
		go func(r string) {
			channel <- getECSFargateRunningContainersByRegion(*cfg, r)
		}(r)
	}

	for i := 0; i < numFuncs; i++ {
		containers := <-channel
		containerList = append(containerList, containers...)
	}

	elapsed := time.Since(start)
	log.Debugf("end getContainer - %s\n", elapsed)

	return containerList
}

func getLambdaInfo(profile string, regions []string) []LambdaInfo {
	log.Debugf("start getContainer\n")
	start := time.Now()

	numFuncs := 0
	channel := make(chan []LambdaInfo)
	var lambdasList []LambdaInfo

	for _, r := range regions {
		cfg := getSession(profile, r)

		numFuncs += 1
		go func(r string) {
			channel <- getLambdas(*cfg, r)
		}(r)
	}

	for i := 0; i < numFuncs; i++ {
		containers := <-channel
		lambdasList = append(lambdasList, containers...)
	}

	elapsed := time.Since(start)
	log.Debugf("end getContainer - %s\n", elapsed)

	return lambdasList
}

func getECSFargateRunningContainersByRegion(cfg aws.Config, region string) []ContainerClusterInfo {
	service := ecs.NewFromConfig(cfg)
	output := ecs.NewListClustersPaginator(service, &ecs.ListClustersInput{})

	var allClusterInfo []ContainerClusterInfo
	for output.HasMorePages() {
		page, err := output.NextPage(context.Background())
		if err != nil {
			log.Errorln("getECSFargateRunningContainersByRegion ListClusters ", region, err)
		} else {
			for _, cluster := range page.ClusterArns {
				output := ecs.NewListTasksPaginator(service, &ecs.ListTasksInput{
					Cluster: &cluster,
				})
				for output.HasMorePages() {
					page, err := output.NextPage(context.Background())
					if err != nil {
						log.Errorln("getECSFargateRunningContainersByRegion ListTasks ", region, err)
					} else {
						if len(page.TaskArns) > 0 {
							outputDT, err := service.DescribeTasks(context.Background(), &ecs.DescribeTasksInput{
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

func getEC2InstancesByRegion(cfg aws.Config, region string) []EC2VMInfo {
	service := ec2.NewFromConfig(cfg)
	output := ec2.NewDescribeInstancesPaginator(service, &ec2.DescribeInstancesInput{
		Filters: []ec2Types.Filter{{Name: aws.String("instance-state-name"), Values: []string{"running", "pending"}}},
	})

	var instances []EC2VMInfo
	for output.HasMorePages() {

		page, err := output.NextPage(context.Background())
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
