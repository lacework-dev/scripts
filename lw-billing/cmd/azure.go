package cmd

import (
	"github.com/spf13/cobra"
	"lw-billing/cmd/lwazure"
	"lw-billing/helpers"
)

var azureCmd = &cobra.Command{
	Use:   "azure",
	Short: "Azure Billing",
	Long:  `Azure Billing`,
	Run: func(cmd *cobra.Command, args []string) {
		debug := helpers.ParseDebug(cmd)
		lwazure.Run(debug)
	},
}

func init() {
	rootCmd.AddCommand(azureCmd)
	azureCmd.Flags().BoolP("debug", "d", false, "Show Debug Logs")
}
