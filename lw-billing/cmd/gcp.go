package cmd

import (
	"github.com/spf13/cobra"
	"lw-billing/cmd/lwgcp"
	"lw-billing/helpers"
	// compute "google.golang.org/api/compute/v1"
)

var gcpCmd = &cobra.Command{
	Use:   "gcp",
	Short: "GCP Billing",
	Long:  `GCP Billing`,
	Run: func(cmd *cobra.Command, args []string) {
		debug := helpers.ParseDebug(cmd)
		lwgcp.Run(debug)
	},
}

func init() {
	rootCmd.AddCommand(gcpCmd)
	gcpCmd.Flags().BoolP("debug", "d", false, "Show Debug Logs")
}
