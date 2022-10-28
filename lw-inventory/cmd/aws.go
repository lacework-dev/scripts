package cmd

import (
	"github.com/lacework-dev/scripts/lw-inventory/cmd/lwaws"
	"github.com/lacework-dev/scripts/lw-inventory/helpers"
	"github.com/spf13/cobra"
)

var awsCmd = &cobra.Command{
	Use:   "aws",
	Short: "Grab AWS Inventory",
	Long:  `Grab AWS Inventory`,
	Run: func(cmd *cobra.Command, args []string) {
		regions := lwaws.ParseRegions(cmd)
		profiles := lwaws.ParseProfiles(cmd)
		debug := helpers.ParseDebug(cmd)
		lwaws.Run(profiles, regions, debug)
	},
}

func init() {
	rootCmd.AddCommand(awsCmd)
	awsCmd.Flags().StringP("profile", "p", "", "AWS Profile(s) to inventory")
	awsCmd.Flags().StringP("region", "r", "", "AWS Region(s) to inventory")
	awsCmd.Flags().BoolP("debug", "d", false, "Show Debug Logs")
}
