# This will prevent the script from running unless the user is running the script in at least powershell version 7.0 https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_requires?view=powershell-7.3#-version-nn
#Requires -Version 7.0

# Only put in the functions that are completed in this file because the Write-Verbose command will not be executed unless you uncomment out the below line
# $VerbosePreference = "Continue"

<#
.SYNOPSIS
    Returns a series of '=' symbols to represent a UI header divider.
.DESCRIPTION
    This function returns 80 '=' symbols as a string so you don't have to type out all of these characters when you are making a UI header section.
.EXAMPLE
    Get-UIHeaderDivider
.NOTES
    N.A.
#>
function Get-UIHeaderDivider {
    $returnString = ""

    # The 1..80 is a shorthand method of creating an array of sequential integers/characters starting at 1 and ending at 80.  This operator is called the "Range operator"
    1..80 | ForEach-Object {
        $returnString += "="
    }

    return $returnString
}

<#
.SYNOPSIS
    Dispaly the main menu UI.
.DESCRIPTION
    This funciton will display a bunch of text required for the user to know how to naviage around the main menu screen.
.PARAMETER numberOfJobsSelected
    An int16 representing the total number of jobs selected to be either backed up or restored
.EXAMPLE
    Get-MainMenuUI 5
.NOTES
    N.A.
#>
function Get-MainScreenUI {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)] [Int16] $numberOfJobsSelected
    )
    
    Clear-Host
    Write-Verbose "Argument supplied for `"Get-MainScreenUI`": $numberOfJobsSelected"

    Write-Host "$(Get-UIHeaderDivider)
    `rWelcome to the RoboCopy backup script utility.  This script will back up/restore
    `rfiles using the CSV files defined inside this project's `"Jobs`" folder.
    `r$(Get-UIHeaderDivider)" -ForegroundColor DarkYellow

    Write-Host "`nSelect one of the items below to start configuring what you want to do."
    
    Write-Host "(1) Select Operations/Jobs
    `r(2) Define Thread count"
    if ($numberOfJobsSelected -eq 0) {
        Write-Host "(Locked) Show work summary/Start work" -ForegroundColor DarkGray  
    }
    else {
        Write-Host "(3) Show work summary/Start work"
    }
}

<#
.SYNOPSIS
    Display the job processes screen UI.
.DESCRIPTION
    This funciton will display a bunch of text required for the user to know how to naviage around the job processes screen.
.EXAMPLE
    Get-JobProcessUI
.NOTES
    N.A.
#>
function Get-JobProcessUI {
    Clear-Host
    Write-Host "$(Get-UIHeaderDivider)
    `rHere are a list of operations that this script can do.  Type the number for the
    `roperation to add/remove jobs to the operation.
    `r$(Get-UIHeaderDivider)" -ForegroundColor DarkYellow
    
    Write-Host "
    `r(1) Backup
    `r(2) Restore"
}

<#
.SYNOPSIS
    Display the select jobs screen UI.
.DESCRIPTION
    This funciton will display a bunch of text required for the user to know how to naviage around the select jobs screen.
.PARAMETER operation
    The operation the user selected to be performed, I.E 'backup' or 'restore'.
.PARAMETER availableJobs
    An array of Objects/PSCustomObjects with at least the properties "JobName" and "JobOperation" that the user can select from.
.EXAMPLE
    $operation = 'backup'
    $availableJobs = @(
        @{JobName = "Job1"; JobOperation = 'backup'},
        @{JobName = "Job2"; JobOperation = ''},
        @{JobName = "Job3"; JobOperation = 'restore'}
    )

    Get-SelectJobsUI $operation $availableJobs
.NOTES
    N.A.
#>
function Get-SelectJobsUI {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)] [string] $operation,
        [Parameter(Mandatory, Position = 1)] [array] $availableJobs
    )

    Clear-Host
    
    Write-Verbose "Arguments supplied for `"Get-SelectJobsUI`":
    operation: $operation
    availableJobs: $($availableJobs | Format-Table | Out-String)"

    Write-Host "$(Get-UIHeaderDivider)
    `rHere are a list of jobs that this script can do for the $operation operation.  Type
    `rthe number of the item to add/remove the job to the queue.
    `r
    `rNote:
    `rJobs marked as 'Locked' can't be selected because they are being used by the
    `rother operation defined.
    `r$(Get-UIHeaderDivider)`n" -ForegroundColor DarkYellow

    $itemNumber = 1
    $availableJobs | ForEach-Object {
        if ($_.JobOperation -eq $operation) {
            Write-Host "[X] ($itemNumber) $($_.JobName)" -ForegroundColor Green
        }
        elseif ([String]::IsNullOrEmpty($_.JobOperation)) {
            Write-Host "[ ] ($itemNumber) $($_.JobName)"
        }
        else {
            Write-Host "[Locked] ($itemNumber) $($_.JobName)" -ForegroundColor DarkGray
        }
        $itemNumber++
    }
}

<#
.SYNOPSIS
    Display the define user defined thread screen UI.
.DESCRIPTION
    This funciton will display a bunch of text required for the user to know how to naviage use the user defined threads screen.
.PARAMETER maxSystemThreads
    An int16 representing the max number of threads for the system.
.PARAMETER userDefinedThreads
    An int16 representing an input the user supplied if they defined this information before.
.PARAMETER robocopyMaxThreads
    A hard coded value for the number of threads that the robocopy program can handle (128)
.EXAMPLE
    Get-UserDefinedThreadsUI 32 $null 128
.NOTES
    N.A.
#>
function Get-UserDefinedThreadsUI {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)] [Int16] $maxSystemThreads,
        [Parameter(Mandatory, Position = 1)] [Int16] $userDefinedThreads,
        [Parameter(Mandatory, Position = 2)] [Int16] $robocopyMaxThreads
    )

    Clear-Host

    Write-Verbose "Arguments supplied for `"Get-UserDefinedThreadsUI`":
    maxSystemThreads: $maxSystemThreads
    userDefinedThreads: $userDefinedThreads
    robocopyMaxThreads: $robocopyMaxThreads"

    Write-Host "$(Get-UIHeaderDivider)
    `rHere you type a number between 1-$(if($maxSystemThreads -gt $robocopyMaxThreads){$robocopyMaxThreads}else{$maxSystemThreads}) so this script can use that number of
    `rthreads for the backup process.
    `r
    `rImportant:
    `r1.  You don't need to worry if the default is greater than your processor's max
    `r    thread count, it will limit itself to your system's capabilities.
    `r2.  The max thread count that Robocopy can handle is $robocopyMaxThreads threads.
    `r$(Get-UIHeaderDivider)" -ForegroundColor DarkYellow
    
    Write-Host "$(if($userDefinedThreads){"Currently using user defined thread count: $userDefinedThreads"}else{"Currently using default thread count: 8"})`n"
}

<#
.SYNOPSIS
    This funciton will display a bunch of text required for the user to know how to naviage use the user defined threads screen.
.DESCRIPTION
    This funciton will display a bunch of text required for the user needs to know about what will happen before the script starts to backup/restore files.
.PARAMETER requiredDrives
    An hashtable conatining two properties "Local" and "Remote" each of which contains an array/list of required drives/network connections required for the jobs (This information is grabbed by using the function "Get-RequiredDrives" inside the Helper-Functions.psm1 file).
.PARAMETER compressedJobsToFromDrives
    A list of PSCustomObjects that follows the below syntax (This information is grabbed by using the function "Compress-RootDriveToFrom" inside the Helper-Functions.psm1 file):
    [PSCustomObjects]@{
            JobName               = "name of the job"
            JobOperation          = "backup OR restore"
            DestinationCompressed = "true OR false"
            CompressedToFromRoots = List[PSCustomObject]@(
                [PSCustomObject]@{
                    Source(s) = <drive letter or some list>
                    Destination(s) = <drive letter or some list>
                }
            )
        }
.EXAMPLE
    $requiredDrives = @{
        Local = @("C", "D")
        Remote = @("\\10.0.0.1\NetworkShare")
    }
    $compressedJobsToFromDrives = List[PSCustomObject]@(
        [PSCustomObject]@{
            JobName               = "NameOfJob"
            JobOperation          = "backup"
            DestinationCompressed = "false"
            CompressedToFromRoots = List[PSCustomObject]@(
                [PSCustomObject]@{
                    Sources = @("C", "D")
                    Destination = "\\10.0.0.1\NetworkShare"
                }
            )  
        }
    )

    Get-BackupRestoreSummaryScreenUI $requiredDrives $compressedJobsToFromDrives
.NOTES
    N.A.
#>
function Get-BackupRestoreSummaryScreenUI {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)] [hashtable] $requiredDrives,
        [Parameter(Mandatory, Position = 1)] [System.Collections.Generic.List[PSCustomObject]] $compressedJobsToFromDrives
    )

    Clear-Host

    Write-Verbose "Arguments supplied for `"Get-BackupRestoreSummaryScreenUI`":
    requiredDrives: $($requiredDrives | Format-Table | Out-String)
    compressedJobsToFromDrives: $($compressedJobsToFromDrives | Select-Object JobName, JobOperation, DestinationCompressed | Format-Table | Out-String)
    compressedJobsToFromDrives.CompressedToFromRoots: $($compressedJobsToFromDrives.CompressedToFromRoots | Format-Table | Out-String)"

    # Required drive portion of the below Write-Host
    if ($requiredDrives.Local.Length -gt 0 -and $requiredDrives.Remote.Length -gt 0) {
        $requiredDrivesMessage = "`tLocal connections: $($requiredDrives.Local -join ', ')
        `r`tRemote connections: $($requiredDrives.Remote -join ', ')"
    }
    elseif ($requiredDrives.Local.Length -gt 0 -and $requiredDrives.Remote.Length -eq 0) {
        $requiredDrivesMessage = "`t$($requiredDrives.Local -join ', ')"
    }
    else {
        $requiredDrivesMessage = "`t$($requiredDrives.Remote -join ', ')"
    }

    Write-Host "$(Get-UIHeaderDivider)
    `rYou are about to start the backup process for this script.  Please read the
    `rfollowing summary to validate your options and see what drives are required.
    `r$(Get-UIHeaderDivider)" -ForegroundColor DarkYellow
    
    Write-Host "
    `rThis script will require the following drives to be active before processing:
    `r$requiredDrivesMessage`n"

    $currentOperation = $null
    $compressedJobsToFromDrives | ForEach-Object {
        if ($currentOperation -ne $_.JobOperation) {
            Write-Host "This script will $($_.JobOperation) the following:"
            $currentOperation = $_.JobOperation
        }
        Write-Host "`t$($_.JobName)"

        $destinationCompressed = $_.DestinationCompressed

        $_.CompressedToFromRoots | ForEach-Object {
            # Build some variables that we will use latter on in this ForEach_Object loop
            $message = "`t`tCopying from drive<1> <2> to drive<3> <4>"
            $sourceGraber = $destinationCompressed ? "Source" : "Sources"
            $destinationGraber = $destinationCompressed ? "Destinations" : "Destination"
            
            # Verbose fuctions for debugging
            Write-Verbose "$($_.$sourceGraber -join ", ") -> $($_.$destinationGraber -join ", ")
            `r`t$sourceGraber -is [System.Collections.Generic.List[string]]: $($_.$sourceGraber -is [System.Collections.Generic.List[string]])
            `r`t$sourceGraber.Count -gt 1 ($($_.$sourceGraber.Count) -gt 1): $($_.$sourceGraber.Count -gt 1)
            `r`t$destinationGraber -is [System.Collections.Generic.List[string]]: $($_.$destinationGraber -is [System.Collections.Generic.List[string]])
            `r`t$destinationGraber.Count -gt 1 ($($_.$destinationGraber.Count) -gt 1): $($_.$destinationGraber.Count -gt 1)"
            
            # Replace portions of the message with the required info.  We don't have to worry about the single entry/string because -join will only affect arrays/lists, not strings.
            $message = $message.Replace('<1>', $(if ($_.$sourceGraber -is [System.Collections.Generic.List[string]] -and $_.$sourceGraber.Count -gt 1) { 's' } else { '' }))
            $message = $message.Replace('<2>', $($_.$sourceGraber -join ", "))
            $message = $message.Replace('<3>', $(if ($_.$destinationGraber -is [System.Collections.Generic.List[string]] -and $_.$destinationGraber.Count -gt 1) { 's' }else { '' }))
            $message = $message.Replace('<4>', $($_.$destinationGraber -join ", "))
            Write-Host $message
        }
    }

    Write-Host "`nWARNING:  This script will over-write and/or delete files inside the destination\source folder if the files are out of date or do not exist in the other folder." -ForegroundColor DarkRed
}

<#
.SYNOPSIS
    Display the backup/restore error summary screen UI.
.DESCRIPTION
    This funciton will display a bunch of text required for the user to know how to handle the errors detected before starting the backup/restoring of the files.
.PARAMETER errorData
    A PSCustomObject containing at least three properties "CanContinue" (a boolean), "DriveErrors" (an array/list of strings) and "PathErrors" (an array/list of PSCustomObjects with the properties "JobName", "JobOperation", and "Source" which is a array/list of strings).  This information can be grabed by running the function "Assert-PathsValid" inside the "Helper-Functions.psm1" module file.
.EXAMPLE
    $errorData = [PSCustomObject]@{
        CanContinue = $true
        DriveErrors = @()
        PathErrors = @(
            [PSCustomObject]@{
                JobName = "Testing"
                JobOperation = "backup"
                Source = @("C:\Bad", "C:\Bad2")
            },
            [PSCustomObject]@{
                JobName = "Testing2"
                JobOperation = "restore"
                Source = @("D:\Bad", "D:\Bad2")
            }
        )
    }

    Get-BackupRestoreErrorScreenUI $errorData
.NOTES
    General notes
#>
function Get-BackupRestoreErrorScreenUI {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)][PSCustomObject] $errorData
    )

    Clear-Host

    Write-Verbose "Arguments supplied for `"Get-BackupRestoreErrorScreenUI`":
    errorData: $($errorData | Format-Table | Out-String)"

    Write-Host "$(Get-UIHeaderDivider)
    `rThe following errors were detected when making sure all the drives and source
    `rpaths exists.
    `rPlease read the below issues and attempt to fix them if they are required.
    `r$(Get-UIHeaderDivider)`n" -ForegroundColor DarkYellow
    
    if ($errorData.DriveErrors) {
        Write-Verbose "Raw contents of errorData.DriveErrors: $($errorData.DriveErrors -join ", ")"

        $message = "Unable to detect the following Drive<1>:
        `r`t"
        $message = $errorData.DriveErrors.Count -gt 1 ? $message.Replace("<1>", 's') : $message.Replace("<1>", '')
        Write-Host "$($message + ($errorData.DriveErrors -join ", "))" -ForegroundColor DarkRed
    }
    if ($errorData.PathErrors) {
        Write-Verbose "Raw contents of errorData.PathErrors: $($errorData.PathErrors | Format-Table | Out-String)"

        $numberOfSourceErrors = $errorData.PathErrors.Source.Count
        $numberOfJobErrors = $errorData.PathErrors | Select-Object JobName -Unique | Measure-Object | Select-Object -ExpandProperty Count

        $message = "Path Error<1> detected, this script will skip the below entr<2> when performing the selected operation<3>:"
        $message = $numberOfSourceErrors -gt 1 ? $message.Replace("<1>", 's').Replace("<2>", "ies") : $message.Replace("<1>", '').Replace("<2>", 'y')
        $message = $numberOfJobErrors -gt 1 ? $message.Replace("<3>", 's') : $message.Replace("<3>", '')
        Write-Host $message -ForegroundColor DarkRed

        $errorData.PathErrors | Foreach-Object {
            $message = "`tCan't $($_.JobOperation) from the below director<1> for the job `"$($_.JobName)`" because <2> do not exist:"
            $message = $_.Source.Count -gt 1 ? $message.Replace("<1>", "ies").Replace("<2>", "they") : $message.Replace("<1>", "y").Replace("<2> do", "it does")
            Write-Host $message -ForegroundColor DarkRed
            $_.Source | ForEach-Object {
                Write-Host "`t$_"
            }
        }
    }

    $totalDriveErrors = $errorData.DriveErrors.Count
    $totalPathErrors = $errorData.PathErrors.Source | Measure-Object | Select-Object -ExpandProperty Count
    Write-Verbose "totalDriveErrors: $totalDriveErrors and totalPathErrors: $totalPathErrors"
    $totalErrors = $totalDriveErrors + $totalPathErrors

    # Adds some space between this error message an anything else added after this function call
    if ($errorData.CanContinue) {
        $message = "`nIf the above issue<1> are expected, then you can continue with the backup/restore."
        $message = $totalErrors -gt 1 ? $message.Replace("<1>", "s") : $message.Replace("<1>", "")
        Write-Host $message
    }
}