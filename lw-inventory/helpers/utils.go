package helpers

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

func GetFlagEnvironmentString(cmd *cobra.Command, flag string, env string, message string, required bool) string {
	value := cmd.Flag(flag).Value.String()
	if value == "" {
		value = viper.GetString(env)

		if required {
			if value == "" {
				Bail(message, nil)
			}
		}
		return value
	}
	return value
}

func ParseDebug(cmd *cobra.Command) bool {
	return GetFlagEnvironmentBool(cmd, "debug", "debug", false)
}

func ParseUseQuotas(cmd *cobra.Command) bool {
	return GetFlagEnvironmentBool(cmd, "useQuotas", "useQuotas", false)
}

func GetFlagEnvironmentBool(cmd *cobra.Command, flag string, env string, required bool) bool {
	value, _ := cmd.Flags().GetBool(flag)
	return value
}

func Bail(message string, err error) {
	if err == nil {
		fmt.Println(message)
	} else {
		fmt.Println(message, err)
	}
	os.Exit(1)
}

func Contains(s []string, e string) bool {
	for _, a := range s {
		if a == e {
			return true
		}
	}
	return false
}
