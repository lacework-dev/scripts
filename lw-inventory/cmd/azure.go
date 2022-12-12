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
		debug := helpers.ParseDebug(cmd)
		lwazure.Run(subscriptions, debug)
	},
}

func init() {
	rootCmd.AddCommand(azureCmd)
	azureCmd.Flags().StringP("ignore-subscriptions", "i", "", "Azure subscriptions to ignore")
	azureCmd.Flags().BoolP("debug", "d", false, "Show Debug Logs")
}
