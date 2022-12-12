package cmd

import (
	"github.com/lacework-dev/scripts/lw-inventory/helpers"
	"github.com/spf13/cobra"
)

var cfgFile string

var rootCmd = &cobra.Command{
	Use:   "lw-inventory",
	Short: "",
	Long:  "",
}

func Execute() {
	if err := rootCmd.Execute(); err != nil {
		helpers.Bail("error starting app", err)
	}
}
