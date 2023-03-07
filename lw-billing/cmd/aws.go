package cmd

import (
	"github.com/spf13/cobra"
	"lw-billing/cmd/lwaws"
	"lw-billing/helpers"
)

var awsCmd = &cobra.Command{
	Use:   "aws",
	Short: "AWS Billing",
	Long:  `AWS Billing`,
	Run: func(cmd *cobra.Command, args []string) {
		billingCSV := lwaws.ParseBilling(cmd)
		debug := helpers.ParseDebug(cmd)
		lwaws.Run(billingCSV, debug)
	},
}

func init() {
	rootCmd.AddCommand(awsCmd)
	awsCmd.Flags().StringP("billing", "b", "", "AWS billing csv")
	awsCmd.Flags().BoolP("debug", "d", false, "Show Debug Logs")
}
