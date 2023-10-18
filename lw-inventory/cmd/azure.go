package cmd

import (
	"github.com/lacework-dev/scripts/lw-inventory/cmd/lwazure"
	"github.com/lacework-dev/scripts/lw-inventory/helpers"
	"github.com/spf13/cobra"
)

var azureCmd = &cobra.Command{
	Use:   "azure",
	Short: "Grab Azure Inventory",
	Long:  `Grab Azure Inventory`,
	Run: func(cmd *cobra.Command, args []string) {
		subscriptions := lwazure.ParseIgnoreSubscriptions(cmd)
		includeLocations := lwazure.ParseIncludeLocations(cmd)
		excludeLocations := lwazure.ParseExcludeLocations(cmd)
		debug := helpers.ParseDebug(cmd)
		useQuotas := helpers.ParseUseQuotas(cmd)
		lwazure.Run(subscriptions, debug, useQuotas, includeLocations, excludeLocations)
	},
}

func init() {
	rootCmd.AddCommand(azureCmd)
	azureCmd.Flags().StringP("ignore-subscriptions", "i", "", "Azure subscriptions to ignore")
	azureCmd.Flags().StringP("include-locations", "", "", "Azure locations to include")
	azureCmd.Flags().StringP("exclude-locations", "", "", "Azure locations to exclude")
	azureCmd.Flags().BoolP("debug", "d", false, "Show Debug Logs")
	azureCmd.Flags().BoolP("useQuotas", "q", false, "Use Quotas")
}
