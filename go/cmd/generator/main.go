package main

import (
	"fmt"
	"os"
	"path/filepath"
	"text/template"

	"github.com/spf13/cobra"
)

func generateFile(path, tpl string, config Config) error {
	t, err := template.New(filepath.Base(path)).Parse(tpl)
	if err != nil {
		return err
	}

	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()

	return t.Execute(f, config)
}

func main() {
	rootCmd := &cobra.Command{
		Use:   "generator",
		Short: "Generate remote debugging configuration files",
		Long: `A generator for creating Docker-based remote debugging configuration files.
This tool will generate necessary files including Dockerfile, docker-compose.yaml,
and .env for remote debugging Go applications.`,
	}

	rootCmd.AddCommand(generateCmd)

	generateCmd.Flags().StringVar(&config.GoVersion, "go-version", "1.22.2", "Go version to use")
	generateCmd.Flags().StringVar(&config.ProjectName, "project", "", "Project name")
	generateCmd.Flags().StringVar(&config.SrcDir, "src", "", "Source directory to mount")
	generateCmd.Flags().StringVar(&config.MainFile, "main", "", "Path to main file relative to src directory")
	generateCmd.Flags().IntVar(&config.DelvePort, "port", 40000, "Port for Delve debugger")

	generateCmd.MarkFlagRequired("project")
	generateCmd.MarkFlagRequired("src")
	generateCmd.MarkFlagRequired("main")

	if err := rootCmd.Execute(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}
