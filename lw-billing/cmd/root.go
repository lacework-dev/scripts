package cmd

import (
	"github.com/spf13/cobra"
	"lw-billing/helpers"
)

var cfgFile string

var rootCmd = &cobra.Command{
	Use:   "lw-billing",
	Short: "",
	Long:  "",
}

func Execute() {
	if err := rootCmd.Execute(); err != nil {
		helpers.Bail("error starting app", err)
	}
}
