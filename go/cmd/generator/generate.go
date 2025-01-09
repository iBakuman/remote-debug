package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/spf13/cobra"
)

type Config struct {
	GoVersion   string
	ProjectName string
	SrcDir      string
	MainFile    string
	DelvePort   int
}

var config Config

var generateCmd = &cobra.Command{
	Use:   "generate",
	Short: "Generate remote debugging configuration files",
	Long: `Generate all necessary files for remote debugging a Go application.
This includes:
- Dockerfile for the debug container
- docker-compose.yaml for orchestration
- .env file for configuration
- dlv.sh script for running delve debugger`,
	RunE: func(cmd *cobra.Command, args []string) error {
		if config.ProjectName == "" || config.SrcDir == "" || config.MainFile == "" {
			return fmt.Errorf("project name, source directory, and main file are required")
		}

		// Create debug directory
		debugDir := filepath.Join("examples", "debug")
		if err := os.MkdirAll(debugDir, 0755); err != nil {
			return fmt.Errorf("error creating debug directory: %v", err)
		}

		// Generate files
		files := map[string]string{
			"Dockerfile":          dockerfileTpl,
			"docker-compose.yaml": dockerComposeTpl,
			".env":                envTpl,
			"dlv.sh":              dlvScriptTpl,
		}

		for filename, tpl := range files {
			if err := generateFile(filepath.Join(debugDir, filename), tpl, config); err != nil {
				return fmt.Errorf("error generating %s: %v", filename, err)
			}
			if filename == "dlv.sh" {
				if err := os.Chmod(filepath.Join(debugDir, filename), 0755); err != nil {
					return fmt.Errorf("error making dlv.sh executable: %v", err)
				}
			}
		}

		fmt.Println("Debug files generated successfully!")
		fmt.Println("To start debugging:")
		fmt.Printf("1. cd %s\n", debugDir)
		fmt.Println("2. docker-compose up")
		return nil
	},
}
