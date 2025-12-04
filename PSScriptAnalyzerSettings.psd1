@{
    Rules = @{
        # Suppress noisy or context-irrelevant warnings
        AvoidUsingEmptyCatchBlock = @{
            Enabled = $false
        }
        AvoidUsingWriteHost       = @{
            Enabled = $false
        }

        # Add others here if needed later:
        # PSAvoidUsingCmdletAliases = @{ Enabled = $false }
        # PSUseSingularNouns       = @{ Enabled = $false }
    }
}
