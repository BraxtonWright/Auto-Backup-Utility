# This will prevent the script from running unless the user is running the script in at least powershell version 7.4 because of the use of "-CaseInsensitive" flag inside the Helper-Functions.psm1 file https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_requires?view=powershell-7.3#-version-nn
#Requires -Version 7.4

# To enter debugging mode, uncomment the following line (will not be applied to the Helper-Functions.psm1 and UI-FUnctions.psm1 files, you have to go each of the files and uncomment the same line of code near the top)
# $VerbosePreference = "Continue"

#region Library Importing
Import-Module -DisableNameChecking $PSScriptRoot'\util\Helper-Functions.psm1'
Import-Module -DisableNameChecking $PSScriptRoot'\util\UI-Functions.psm1'
#endregion

#region Variables and Pre-configuring
# the @() defines an array
$noAnswer = @('N', 'n')
$yesAnswer = @('Y', 'y')
$yesNoAnswer = $yesAnswer + $noAnswer
$quitAnswer = @('Q', 'q')
$backAnswer = @('B', 'b')
$clearContinueAnswer = @('C', 'c')
# The below variable is also used inside the file "Helper-Functions.psm1" file.  However, for some reason that file pulls this variable into itself so you can use it there as well?
$jobOperations = @{
    Backup  = "backup"
    Restore = "restore"
}
# The reason for having $Global in front of some variables are not in others is because those that have this identifier can be modified inside function calls.  Explanation for this found here https://stackoverflow.com/questions/30590972/global-variable-changed-in-function-not-effective and here https://techgenix.com/powershell-global-variable
$robocopyMaxThreads = 128
$maxSystemThreads = Get-SystemThreadCount
$Global:userDefinedThreads = $null
$availableJobs = Get-JobsFromJobFolder
$Global:selectedJobsCount = 0

<#
 This is added because after PowerShell 7.2, it introduced this new variable and it is set to 'Minimal' by default.
 However, it causes my Write-Progress to not work as it should.
 So I have to manually set it to 'Classic' to get the old view back and have it work as it should.
#>
$PSStyle.Progress.View = "Classic"

$Host.PrivateData.ProgressBackgroundColor = 'Cyan' 
$Host.PrivateData.ProgressForegroundColor = 'Black'
#endregion

#region Notes
# Powershell doesn't have a normal scopes as do most programming languages.  It has three levels, Global, Script, and Local and when you run functions defined in this file, it is in the "Script" level.  That means that you can reference any varaible defined in a function, regardless on if it was created inside a subscope such as an if statment or not https://www.varonis.com/blog/powershell-variable-scope
# To add the help section as shown below for the functions, you simply need to type out "help-function" (doesn't auto grab function arguments) or "##" (auto grabs function arguments) and it will create a template that you can fill out with your required information. https://stackoverflow.com/questions/72643685/autodocstring-for-powershell-functions
#endregion

<#
.SYNOPSIS
    Displays the main menu for this script.
.DESCRIPTION
    This will display a menu where the user can chose one of three options to navigate to.  Select jobs, define thread count to be used, or get the job summary/start the backup/restore process.
.EXAMPLE
    Get-MainScreen
.NOTES
    N.A.
#>
function Get-MainScreen {
    do {
        Get-MainScreenUI -numberOfJobsSelected $Global:selectedJobsCount

        $userInput = Read-Host "`nSelection or 'Q'uit"

        # The below condition inside the switch statment will convert the user input to an it if it can be converted otherwise, it will be null https://stackoverflow.com/questions/69500314/checking-if-a-string-can-cannot-be-converted-to-int-float
        switch ($userInput -as [int]) {
            1 { Select-JobProcess }
            2 { Get-UserDefinedThreads }
            3 { if ($Global:selectedJobsCount -ne 0) { Get-BackupRestoreSummaryScreen } }
        }
    } while ($userInput -notin $quitAnswer)

    Clear-Host

    # We don't have to call the below function in production but I am keeping it here because when you leave this function, it will automaticly terminate the script.
    Exit-ScriptDeployment
}

<#
.SYNOPSIS
    Displays the screen the user uses to either backup or restore jobs.
.DESCRIPTION
    This will display a menu where the user can select one of two options.  Select jobs to be backed up or select jobs to be restored.
.EXAMPLE
    Select-JobProcess
.NOTES
    N.A.
#>
function Select-JobProcess {
    do {
        Get-JobProcessUI
        
        $userInput = Read-Host "`nSelection or 'B'ack"

        # The below condition inside the switch statment will convert the user input to an it if it can be converted otherwise, it will be null https://stackoverflow.com/questions/69500314/checking-if-a-string-can-cannot-be-converted-to-int-float
        switch ($userInput -as [int]) {
            1 { Select-Jobs $jobOperations.Backup }
            2 { Select-Jobs $jobOperations.Restore }
        }
    } While ($userInput -notin $backAnswer)
}

<#
.SYNOPSIS
    Displays a screen that the user uses to select jobs.
.DESCRIPTION
    This will display all available jobs "CSV files" defined inside the "Jobs" folder so the user can select them.
.PARAMETER operation
    The operation you wish to perform when selecting the jobs, such as "backup" or "restore".
.EXAMPLE
    Select-Jobs "backup"
.Example
    $jobOperations = @{
        Backup  = "backup"
        Restore = "restore"
    }
    Select-Jobs $jobOperations.Backup
.NOTES
    Designed to accept only two types of operations, either backup or restore
#>
function Select-Jobs {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, Position = 0)] [string] $operation
    )
    Write-Verbose "Argument supplied for `"Select-Jobs`": $operation"

    do {
        Get-SelectJobsUI $operation ($availableJobs | Select-Object JobName, JobOperation)

        $userInput = Read-Host "`nIndex or go 'B'ack"
        $intUserInput = $userInput -as [int] # Convert the user input to an it if it can be converted otherwise, it will be null https://stackoverflow.com/questions/69500314/checking-if-a-string-can-cannot-be-converted-to-int-float
        
        Write-Verbose "The user input is between 1 and $($availableJobs.Count): $($intUserInput -in 1..$availableJobs.Count)"
        # The user input is the valid range for the selection
        if ($intUserInput -in 1..$availableJobs.Count) {
            Write-Verbose "Before change:  $($availableJobs[$intUserInput - 1].JobOperation)"
            if ([String]::IsNullOrEmpty($availableJobs[$intUserInput - 1].JobOperation)) {
                $availableJobs[$intUserInput - 1].JobOperation = $operation
                $Global:selectedJobsCount++
            }
            elseif ($availableJobs[$intUserInput - 1].JobOperation -eq $operation) {
                $availableJobs[$intUserInput - 1].JobOperation = $Null
                $Global:selectedJobsCount--
            }
            Write-Verbose "After change:  $($availableJobs[$intUserInput - 1].JobOperation)"
        }
    } while ($userInput -notin $backAnswer)
}

<#
.SYNOPSIS
    Displays a screen that the user uses define/undefine the number of threads to use for the selected jobs.
.DESCRIPTION
    This will display an optional screen where the user can chose how many threads they want the script to use when either backing up or restoring files defined inside the jobs.
.EXAMPLE
    Get-UserDefinedThreads
.NOTES
    This is an optional screen.  If the user doesn't define the number of threads, it will use the default for robocopy "8"
#>
function Get-UserDefinedThreads {
    $firstStartUp = $true
    $maxAllowedThreads = $maxSystemThreads -le $robocopyMaxThreads ? $maxSystemThreads : $robocopyMaxThreads
    $threadsConfigured = -not [string]::IsNullOrEmpty($Global:userDefinedThreads)
    $validUserInput = [string]::IsNullOrEmpty($Global:userDefinedThreads) ? $backAnswer : $backAnswer + $clearContinueAnswer

    do {
        Get-UserDefinedThreadsUI $maxSystemThreads $Global:userDefinedThreads $robocopyMaxThreads

        # If it is not the first time here, validate the user's input
        if (-not $firstStartUp) {
            # Checks to see if the user input is a integer or a valid input
            if ($intUserInput -isnot [int] -and $userInput -notin $validUserInput) {
                Write-Verbose "Failing Condition:
                `r`tInput not an integer: $($intUserInput -isnot [int])
                `r`tInput is not 'C'lear or 'B'ack: $($userInput -notin $validUserInput)"

                Write-Host "ERROR:  Your input `"$userInput`" is not an integer."
            }
            # Checks to see if input (which is an integer) is between 1 and the maximum number of threads for the system or 128 (the max thread count that RoboCopy can handle)
            elseif ($intUserInput -notin 1..$maxAllowedThreads) {
                if ($intUserInput -gt $robocopyMaxThreads) { Write-Host "ERROR:  The max thread count that robocopy can handle is $robocopyMaxThreads threads." }
                else { Write-Host "ERROR:  Your input `"$intUserInput`" is outside the capabilities of your system." }
            }
        }

        $firstStartUp = $false

        $inputPrompt = "Number of threads<1> or go 'B'ack"
        $inputPrompt = $threadsConfigured ? $inputPrompt.Replace("<1>", ", 'C'lear,") : $inputPrompt.Replace("<1>", '')

        $userInput = Read-Host -Prompt $inputPrompt
        $intUserInput = $userInput -as [int]
        # Do while ((user's input is not an integer) OR (the integer user input is not in the valid range)) AND (the user's input is not 'C'lear or go 'B'ack)
    } while (($intUserInput -isnot [int] -or $intUserInput -notin 1..$maxAllowedThreads) -and $userInput -notin $validUserInput)

    if ($intUserInput -is [int]) {
        $Global:userDefinedThreads = $intUserInput
    }
    elseif ($userInput -in $clearContinueAnswer) {
        $Global:userDefinedThreads = $Null
    }
}

<#
.SYNOPSIS
    Displays a summary screen for the jobs selected.
.DESCRIPTION
    This will display the summary screen for the jobs selected and will tell the users what drives are required for the selected jobs and a brief table telling where the jobs will be copying to/from.
    Then if the user chooses to continue, it will check to make sure that all the required drives are connected and source paths exist before continuing.

    If it is unable to detect a required drive, then it will show the drive(s) that it was unable to detect and ask the user to connect the drive and have the script check again.
    If however, it is unable to detect a source path, it will then show the source paths it was unable to detect and then will ask the user if they want to continue with the process by excluding source paths it couldn't find.  This is because in some instances, this is an expected result because the either the OS might have not created the source directory when performing a backup operation or it hasn't been backed up yet when performing a restore operation.
.EXAMPLE
    Get-BackupRestoreSummaryScreen
.NOTES
    If a job is being restored, this function will automaticaly swap all the "Source" and "Destination" properties of the selected job inside the property stored inside of "$availableJobs.JobContent"
#>
function Get-BackupRestoreSummaryScreen {
    Clear-Host # We add this here because we call the UI function after we process all the data

    # Make a deep copy of the jobs that have been queued and sorts them by JobOperation first then by JobName property
    $jobsToProcess = $availableJobs | Where-Object JobOperation -ne $Null | ForEach-Object {
        [PSCustomObject]@{
            JobName      = $_.JobName
            JobOperation = $_.JobOperation
            JobContent   = $_.JobContent | ForEach-Object {
                [PSCustomObject]@{
                    Source       = $_.Source
                    Destination  = $_.Destination
                    Description  = $_.Description
                    FileMatching = $_.FileMatching
                }
            }
        }
    } | Sort-Object JobOperation, JobName
    Write-Verbose "Jobs selected to be processed (for debugging):
    $($jobsToProcess | Format-Table | Out-String)"
    # $jobsToProcess | Out-File -Width 1000 ./test.txt # for debugging only to see the formatted contents

    # Go through each entry and if we are restoring in the job, then swap the source and destination paths.
    # The -Parallel flag used below will have this action run in Parallel. To reference the current object, use $PSItem and to bring in outside variables, use $USING:varname
    $jobsToProcess | Foreach-Object -Parallel {
        if ($PSItem.JobOperation -eq $USING:jobOperations.Restore) {
            $PSItem.JobContent | ForEach-Object -Parallel {
                Write-Verbose "Swapping the source and destinations paths for the entry: $PSItem"
                $PSItem.Source, $PSItem.Destination = $PSItem.Destination, $PSItem.Source # This uses multiple assignments to swap the contents of the two variables https://powershellmagazine.com/2013/08/07/pstip-swapping-the-value-of-two-variables/
            }
        }
    }

    Write-Verbose "Jobs after being processed (for debugging):
    `r`t $($jobsToProcess | Format-Table | Out-String)"

    # This function call is formatted this way so that it will supply a single array of PSCustomObjects with the properties "Source" and "Destination"
    $requiredDrives = Get-RequiredDrives ($jobsToProcess | ForEach-Object { $_.JobContent | Select-Object Source, Destination })
    $compressedToFrom = Compress-RootDriveToFrom $jobsToProcess

    do {
        Get-BackupRestoreSummaryScreenUI $requiredDrives $compressedToFrom
    
        $userInput = Read-Host -Prompt "Do you want to continue with the process 'Y'es or 'N'o"
        if ($userInput -in $yesAnswer) {
            $UserInput = Read-Host -Prompt "This is a final confirmation, do you want to continue 'Y'es or 'N'o"
        }
    } while ( $userinput -notin $yesNoAnswer)

    # Start backup process if the paths are valid
    if ($userInput -in $yesAnswer) {
        do {
            $returned = Assert-PathsValid $jobsToProcess
            if (-not $returned.AllValid) {
                Get-BackupRestoreErrorScreenUI ($returned | Select-Object CanContinue, DriveErrors, PathErrors)

                if ($returned.CanContinue) {
                    $UserInput = Read-Host "'C'ontinue or go 'B'ack to the main menu"
                }
                else {
                    $UserInput = Read-Host "Press ENTER to re-evaulate the data or go 'B'ack to the main menu"
                }
            }
            $validUserInput = $returned.CanContinue ? $clearContinueAnswer + $backAnswer : $backAnswer
        } while (-not $returned.AllValid -and $userInput -notin $validUserInput)

        if ($returned.AllValid -or $userInput -in $clearContinueAnswer) {
            # NEED TO SEE IF THERE IS A PERFORMANCE HIT USING THE ROBOCOPYPIPE FUNCTION
            # use the Measure-Command cmdlet to achieve this
            Start-Backup $jobsToProcess
            Exit-ScriptDeployment
        }
    }
}

<#
.SYNOPSIS
    Start the process of backing up and/or restoring files inside the selected jobs.
.DESCRIPTION
    This will start the process of backing up and/or restoring the files defined inside the jobs the user has selected from the "Source" property to the "Destination" property.
.PARAMETER jobsToProcess
    An array of PSCustomObjects that follow the below format that this function will read from to perform the backup or restore
    @{
        JobName = "Name of the job"
        JobOperation = "either 'backup' or 'restore'"
        JobContent = [System.Collections.Generic.List[PSCustomObject]]@() # this contains an list of PSCustomObjects with the following properties "Source", "Destination", "Description", and "FileMatching"
    }
.EXAMPLE
    $jobsToProcess = @(
        [PSCustomObject]@{
            JobName = "Job1"
            JobOperation = "backup"
            JobContent = @(
                [PSCustomObject]@{
                    Source       = "C:/Folder 1"
                    Destination  = "C:/Folder 2"
                    Description  = "Mirroring Folder 1 to Folder 2"
                    FileMatching = ''
                }
            )
        },
        [PSCustomObject]@{
            JobName = "Job2"
            JobOperation = "restore"
            JobContent = @(
                [PSCustomObject]@{
                    Source       = "C:/Folder 3"
                    Destination  = "C:/Folder 4"
                    Description  = "Copying all .exe and .png files from Folder 3 to Folder 4"
                    FileMatching = '*.exe/*.png'
                },
                [PSCustomObject]@{
                    Source       = "C:/Folder 5"
                    Destination  = "C:/Folder 6"
                    Description  = "Mirroring Folder 5 to Folder 6"
                    FileMatching = ''
                }
            )
        }
    )

    Start-Backup $jobsToProcess
.NOTES
    This function doesn't swap the "Source" and "Destination" properties stored inside of "JobContent" if you are restoring.  This is done inside the function "Get-BackupRestoreSummaryScreen" when the summary is being displayed.
    This function will count the number of UNIQUE files in the source and destination paths before it starts the backup.  It stores the nubmer of UNIQUE files inside a new property "EntryFileCount" for each PSCustomObject inside of "JobContent" for each entry inside the job.
#>
function Start-Backup {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)] [PSCustomObject] $jobsToProcess
    )

    Clear-Host
    Write-Verbose "Argument supplied for `"Start-Backup`": $($jobsToProcess | Format-Table | Out-String)"

    # The number of files for the jobs is stored inside a new property called "EntryFileCount" inside of $jobsToProcess.JobContent.  This property is added during the function "Get-TotalFileCount" for the jobs and we have to pass the entire object stored inside of "JobContent" to the function to have it be added to the reference of "JobContent" instead of a copy of "JobContent"
    $combinedJobsFileCount = Get-TotalFileCount ($jobsToProcess | ForEach-Object { $_.JobContent })
    
    Clear-Host
    Write-Verbose "File Count returned: $($combinedJobsFileCount)"
    Write-Verbose "Checking to see if the property `"JobContent`" has the new property named `"EntryFileCount`" inside them: $($jobsToProcess | ForEach-Object { $_.JobContent} | Format-Table | Out-String)"

    #region Robocopy parameters and what they do
    # W = Wait time between fails
    # R = Retry times
    # NDL = Don't log directory names
    # NC  = Don't log file classes (existing, new file, etc.)
    # BYTES = Show file sizes in bytes
    # NJH = Do not display robocopy job header (JH)
    # NJS = Do not display robocopy job summary (JS)

    # can or can not be used depending on what the user choses while defining the job files and using this script
    # MIR = Mirror mode
    # MT:<n> = Creates multi-threaded copies with n threads
    # There are more parameters documented here, however they are not needed for this script https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/robocopy
    #endregion

    # The below three varaibles will use what is called splatting to replace the contents of the array/hashtable into a cmdlet https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_splatting?view=powershell-5.1
    $commonRobocopyParams = "/W:0", "/R:1", "/NDL", "/NC", "/BYTES", "/NJH", "/NJS"
    $overallProgressParameters = @{
        ID               = 0
        Activity         = "TBD"
        Status           = "Percent completed: 0%     Estimated time remaining: TDB"
        PercentComplete  = 0
        CurrentOperation = "Files copied: 0 / TBD     Files left: TBD"
    }
    $jobProgressParameters = @{
        ParentID         = 0
        ID               = 1
        Activity         = "TBD"
        Status           = "Percent completed: 0%      File size: TBD     Processing file: TBD"
        PercentComplete  = 0
        CurrentOperation = "Copied: 0 / TBD     Files Left: TBD"
    }
    # This object is used for passing additional variables that are required for the function "Get-RobocopyProgress" to work correctly
    $helperVariables = @{
        TotalFileCount = $combinedJobsFileCount
        EntryFileCount = $null # To be the contents stored inside of $jobsToProcess.JobContent.EntryFileCount
        FilesProcessed = -1 # We set it to -1 because inside the function "Get-RobocopyProgress", it will auto increment it by one when it gets to the first file.  If it was 0, when it would start processing the first file, it would result in it saying that the file has been processed when it has not yet been processed.
        StartTime      = Get-Date
    }

    $jobsToProcess | ForEach-Object {
        Write-Verbose "Job being processed: `"$($_ | Select-Object JobName, JobOperation)`""

        $currentJobOperation = $_.JobOperation
        $overallProgressParameters.Activity = $currentJobOperation -eq $jobOperations.Backup ? "Generating backup for the job `"$($_.JobName)`"" : "Restoring files for the job `"$($_.JobName)`""

        $_.JobContent | ForEach-Object {
            Write-Verbose "`tCurrent entry being processed $($_)"

            # If the source directory exists, then process it.
            if (Test-Path $_.Source) {
                $jobProgressParameters.Activity = $currentJobOperation -eq $jobOperations.Backup ? "Currently backing up: `"$($_.Description)`"" : "Currently restoring: `"$($_.Description)`""
                $helperVariables.EntryFileCount = $_.EntryFileCount

                #region robocopy parameter processing
                $toFromPaths = @( $_.Source, $_.Destination )
                $fileList = $_.FileMatching -split '/' # if there is no entries inside here, it will simply be an empty array which the robocopy executible will ignore
                $additionalRoboCopyParams = [System.Collections.Generic.List[string]]::new()
                if ([string]::IsNullOrEmpty($_.FileMatching)) { $additionalRoboCopyParams.Add("/MIR") }
                if (-not [string]::IsNullOrEmpty($Global:userDefinedThreads)) { $additionalRoboCopyParams.Add("/MT:$Global:userDefinedThreads") }
                #endregion

                # This will store the robocopy executible and the parameters for robocopy in variables so that we will simply have to call "& $executable $params" to have it be executed https://stackoverflow.com/questions/29562598/powershell-with-robocopy-and-arguments-passing
                $executable = "Robocopy.exe"
                $params = $toFromPaths + $fileList + $additionalRoboCopyParams + $commonRobocopyParams

                Write-Verbose "`tRunning the command '$executable $params'"
                & $executable $params | Get-RobocopyProgress $overallProgressParameters $jobProgressParameters $helperVariables    
            }
            else {
                Write-Verbose "`tSkipping this entry for because the Source directory `"$($_.Source)`" doesn't exist"
            }
        }
    }

    Clear-ProgressScreen
}

#region Main Code that jump starts the script
Get-MainScreen
#endregion