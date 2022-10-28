package cmd

import (
	"github.com/lacework-dev/scripts/lw-inventory/cmd/lwgcp"
	"github.com/lacework-dev/scripts/lw-inventory/helpers"
	"github.com/spf13/cobra"
	// compute "google.golang.org/api/compute/v1"
)

var gcpCmd = &cobra.Command{
	Use:   "gcp",
	Short: "Grab GCP Inventory",
	Long:  `Grab GCP Inventory`,
	Run: func(cmd *cobra.Command, args []string) {
		//zones := lwgcp.ParseZones(cmd)
		projectsToIgnore := lwgcp.ParseProjectsToIgnore(cmd)
		credentials := lwgcp.ParseCredentials(cmd)
		debug := helpers.ParseDebug(cmd)
		lwgcp.Run(projectsToIgnore, credentials, debug)
	},
}

func init() {
	rootCmd.AddCommand(gcpCmd)
	//gcpCmd.Flags().StringP("zone", "", "", "GCP Zone(s) to inventory")
	gcpCmd.Flags().StringP("projects-to-ignore", "i", "", "GCP projects to ignore")
	gcpCmd.Flags().StringP("credentials", "c", "", "Path to GCP credentials file") //may add back in if need to support custom location
	gcpCmd.Flags().BoolP("debug", "d", false, "Show Debug Logs")
}
