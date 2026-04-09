import Darwin

if let exitCode = AutomationCLI.runIfNeeded() {
    Darwin.exit(exitCode)
}

CodeIslandApp.main()
