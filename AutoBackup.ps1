# This will prevent the script from running unless the user is running the script in at least powershell version 7.0 https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_requires?view=powershell-7.3#-version-nn
#Requires -Version 7.0

# To enter debugging mode, uncomment the following line (will not be applied to the Helper-Functions.psm1 file, you have to go to that file and uncomment the same line of code)
# $VerbosePreference = "continue"

#region Library Importing
Import-Module -DisableNameChecking $PSScriptRoot\util\Helper-Functions.psm1
#endregion

#region Global variables used / Pre-configuring
# the @() defines an array
$YesNoCharAnswer = @('Y', 'y', 'N', 'n')
$NoCharAnswer = @('N', 'n')
$YesCharAnswer = @('Y', 'y')
$QuitCharAnswer = @('Q', 'q')
$BackCharAnswer = @('B', 'b')
$ClearCharAnswer = @('C', 'c')
# The below variable is also used inside the file Helper-Functions.psm1.  However, for some reason that file pulls this variable into itself so you can use it there as well?
$JobOperations = @{
    Backup  = "backup"
    Restore = "restore"
}
# The reason for having $Global in front of some variables are not in others is because those that have this identifier can be modified inside function calls.  Explanation for this found here https://stackoverflow.com/questions/30590972/global-variable-changed-in-function-not-effective and here https://techgenix.com/powershell-global-variable
$MaxThreadsNumber = Get-MaxThreads
$Global:UDThreadUsage = $Null
Write-Host "Getting all available jobs from the ""Jobs"" folder..."
$AvailableJobs = Get-AvailableJobs # an array of objects
$JobsContent = Get-JobsContent $AvailableJobs # a hashtable of file names and file contents (which is an array containing PSCustomObjects)
$Global:JobCount = 0

<#
 This is added because after PowerShell 7.2, it introduced this new variable and it is set to 'Minimal' by default.
 However, it causes my Write-Progress to not work as it should.
 So I have to manually set it to 'Classic' to get the old view back and have it work as it should.
#>
$PSStyle.Progress.View = "Classic"

$Host.PrivateData.ProgressBackgroundColor = 'Cyan' 
$Host.PrivateData.ProgressForegroundColor = 'Black'
#endregion

#region Screen Functions
<#
.SYNOPSIS
    Main menu for the script

.DESCRIPTION
    The main menu for the script so the user can get started with the backup/restoring of files

.NOTES
    This function takes no arguments

.EXAMPLE
    Get-MainScreen
    Displays the main menu that the user can interact with to either backup or restore files
#>
function Get-MainScreen {
    [CmdletBinding()]
    param ()

    do {
        Clear-Host

        Write-Host "================================================================================
        `rWelcome to the RoboCopy backup script utility.  This script will back-up/restore
        `rfiles using the CSV files defined inside this project's `"Jobs`" folder.
        `r================================================================================"

        Write-Host "`nSelect one of the items below to start configuring what you want to do."
        
        $UserInput = ""
        Write-Host "(1) Select Operations/Jobs
        `r(2) Define Thread count"
        if ($Global:JobCount -eq 0) {
            Write-Host "(Locked) Show work summary/Start work" -ForegroundColor DarkGray  
        }
        else {
            Write-Host "(3) Show work summary/Start work"
        }

        $UserInput = Read-Host "`nSelection or 'Q'uit"

        if ($UserInput -as [int] -is [int]) {
            switch ([int]$UserInput) {
                1 { Select-JobOperation }
                2 { Get-UserDefinedThreads }
                3 { if ($Global:JobCount -ne 0) { Get-BackupDataScreen } }
            }
        }
    } While ($QuitCharAnswer -notcontains $UserInput)

    Clear-Host
}

#region Backup/restore screens
<#
.SYNOPSIS
Select either to backup or restore a job

.DESCRIPTION
You will select one of two options that will take you into a menu to define a job as backing up or restoring

.EXAMPLE
Select-JobOperation

.NOTES
N.A.
#>
function Select-JobOperation {
    [CmdletBinding()]
    param ()

    do {
        Clear-Host

        Write-Host "Here are a list of operations that this script can do.  Type the number for the operation to add/remove jobs to the operation.
        `r(1) Backup
        `r(2) Restore"

        $UserInput = Read-Host "`nSelection or 'B'ack"
        Write-Verbose "User input is an int: $($UserInput -as [int] -is [int])"
        if ($UserInput -as [int] -is [int]) {
            if ([int]$UserInput -eq 1) {
                Write-Verbose "Running the command ""Select-Jobs -Operation $($JobOperations.Backup)"""
                Select-Jobs -Operation $JobOperations.Backup
            }
            elseif ([int]$UserInput -eq 2) {
                Write-Verbose "Running the command ""Select-Jobs -Operation $($JobOperations.Restore)"""
                Select-Jobs -Operation $JobOperations.Restore
            }
        }
    } While ($BackCharAnswer -notcontains $UserInput)
}

<#
.SYNOPSIS
Select a job you want to perform

.DESCRIPTION
Allows you to select from a list of jobs to either backup or restore files from that job

.PARAMETER Operation
Either "backup" or "restore"

.EXAMPLE
Select-Jobs -operation "backup"
Select-Jobs "restore"

.NOTES
N.A.
#>
function Select-Jobs {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, Position = 0)] [string] $Operation
    )
    do {
        Clear-Host

        Write-Host "Here are a list of jobs that this script can do for the $Operation operation.  Type the number of the item to add/remove the job to the queue.
        `rNote:  Jobs marked as 'Locked' are because they are being used by the other operation defined."

        $ItemNumber = 1
        foreach ($Job in $AvailableJobs) {
            if ($Job.JobOperation -eq $Operation) {
                Write-Host "[X] ($ItemNumber) $($Job.Name)"
            }
            elseif ([String]::IsNullOrEmpty($Job.JobOperation)) {
                Write-Host "[ ] ($ItemNumber) $($Job.Name)"
            }
            else {
                Write-Host "[Locked] ($ItemNumber) $($Job.Name)" -ForegroundColor DarkGray
            }
            $ItemNumber += 1
        }
        $UserInput = Read-Host "`nIndex or go 'B'ack"
        Write-Verbose "User input is an int: $($UserInput -as [int] -is [int])"
        $UserInputInt = 0
        if ($UserInput -as [int] -is [int]) {
            $UserInputInt = [int]$UserInput
        }
        Write-Verbose "The user input is between 1 and $($AvailableJobs.count): $($UserInputInt -in 1..$AvailableJobs.count)"
        # The user input is the valid range for the selection
        if ($UserInputInt -in 1..$AvailableJobs.count) {
            Write-Verbose "Before change:  $($AvailableJobs[$UserInputInt - 1].JobOperation)"
            if ([String]::IsNullOrEmpty($AvailableJobs[$UserInputInt - 1].JobOperation)) {
                $AvailableJobs[$UserInputInt - 1].JobOperation = $Operation
                $Global:JobCount += 1
            }
            elseif ($AvailableJobs[$UserInputInt - 1].JobOperation -eq $Operation) {
                $AvailableJobs[$UserInputInt - 1].JobOperation = $Null
                $Global:JobCount -= 1
            }
            Write-Verbose "After change:  $($AvailableJobs[$UserInputInt - 1].JobOperation)"
        }
    } while ($BackCharAnswer -notcontains $UserInput)
}
#endregion

<#
.SYNOPSIS
Open a menu to define the number of threads to use

.DESCRIPTION
Open a menu for the user to defines the number of threads that the job is to use 

.EXAMPLE
Get-UserDefinedThreads

.NOTES
N.A.
#>
function Get-UserDefinedThreads {
    [CmdletBinding()]
    param ()

    $UserInput = $Null
    $FirstStartUp = $True
    do {
        Clear-Host

        Write-Host "================================================================================
        `rHere you type a number between 1-$(if($MaxThreadsNumber -gt 128){128}else{$MaxThreadsNumber}) so this script can use that number of
        `rthreads for the backup process.
        `n`rIMPORTANT NOTES:
        `r1.  You don't need to worry if the default is greater than your processor's max
        `r    thread count, it will limit itself to your system's capabilities.
        `r2.  The max thread count that this script can handle is 128 threads.
        `r================================================================================"

        Write-Host `n$(if([String]::IsNullOrEmpty($Global:UDThreadUsage)){"Currently using default thread count: 8"}else{"Currently using user defined thread count: $Global:UDThreadUsage"})`n

        #checks to see if the input is a integer
        if (-not $FirstStartUp -and ([String]::IsNullOrEmpty($UserInput) -or -not ($UserInput -as [int] -is [int]) -and ($UserInput -ne "b" -and $UserInput -ne "B" -and $UserInput -ne "c" -and $UserInput -ne "C"))) {
            Write-Verbose "Failing Condition:"
            Write-Verbose "First startup: $FirstStartUp"
            Write-Verbose "Input is Null/Emtpy: $([String]::IsNullOrEmpty($UserInput))"
            Write-Verbose "Input an integer: $(-not ($UserInput -as [int] -is [int]))"
            Write-Verbose "Input is not 'b', 'B', or 'CLEAR': $(-not ($UserInput -eq "b" -or $UserInput -eq "B" -or $UserInput -eq "CLEAR"))"
            
            Write-Host "ERROR:  Your input `"$UserInput`" is not an integer."
        }
        #checks to see if input (which is an integer) is between 1 and the maximum number of threads for the system or 128 (that max thread count that RoboCopy can handle)
        elseif (-not $FirstStartUp -and ($UserInput -as [int] -le 0 -or $UserInput -as [int] -gt $MaxThreadsNumber -or $UserInput -as [int] -gt 128)) {
            Write-Host "ERROR:  " -NoNewline
            if ($UserInput -as [int] -gt 128) {
                Write-Host "The max thread count that this script can handle is 128 threads."
            }
            else {
                Write-Host "Your input `"$UserInput`" is out of the capabilities of your system."
            }
        }

        $FirstStartUp = $False

        $UserInput = Read-Host -Prompt "Number of threads, 'C'lear, or 'B'ack"
        $UserInputInt = $UserInput -as [int]
    } while ((-not ($UserInputInt) -or ($UserInputInt -le 0 -or $UserInputInt -gt $MaxThreadsNumber -or $UserInputInt -gt 128)) -and ($BackCharAnswer -notcontains $UserInput -and $ClearCharAnswer -notcontains $UserInput))

    if ($UserInput -as [int] -is [int]) {
        $Global:UDThreadUsage = [int]$UserInput
    }
    elseif ($ClearCharAnswer.Contains($UserInput)) {
        $Global:UDThreadUsage = $Null
    }
}

<#
.SYNOPSIS
Display a summary of the selected jobs before it starts processing

.DESCRIPTION
This will display a small summary of the jobs you selected and what the script will do when processing them.
It will also warn the user that the process will overwrite\delete any files that do or do not exist inside the other folder 

.EXAMPLE
Get-BackupDataScreen

.NOTES
WIP: I need to make it so that this function displays what drive letters it needs and use the Test-Path cmdlet to see if the Drives are connected and test to see if the source exist to be processed
#>
function Get-BackupDataScreen {
    [CmdletBinding()]
    param ()

    $JobsToProcess = $AvailableJobs | Where-Object JobOperation -ne $Null | Sort-Object JobOperation, Name # This only gets the jobs that have been queued and sorts first by the JobOperation then by the job's Name
    $ExtractedJobData = @() # This will hold the array of Source and destination drives used check to see if they are connected or exists
    foreach ($Job in $JobsToProcess) {
        $ExtractedJobData += $JobsContent.$($Job.Name) | ForEach-Object {
            [PSCustomObject]@{
                JobName        = $Job.Name
                JobOperation   = $Job.JobOperation
                Source         = ($Job.JobOperation -ne $JobOperations.Restore ? $_.Source : $_.Destination)
                Destination    = ($Job.JobOperation -ne $JobOperations.Restore ? $_.Destination : $_.Source)
                JobDescription = $_.Description
                FileMatching   = $_.FileMatching
            }
        }
    }

    $RequiredDrives = Get-RequiredDrives -Paths $($ExtractedJobData | Select-Object Source, Destination)
    Write-Verbose "RequiredDrives returned: $($RequiredDrives -join ', ')"

    do {
        Clear-Host
        
        Write-Host "================================================================================
        `rYou are about to start the backup process for this script.  Please read the
        `rfollowing summary to validate your options and see what drives are required.
        `r================================================================================`n"

        Write-Host "This script will require the following drives to be active before processing:
        `r`t$($RequiredDrives -join ", ")`n"

        $JobDescriber = ""
        foreach ($Job in $JobsToProcess) {
            if ($JobDescriber -ne $Job.JobOperation) {
                Write-Host "This script will $($Job.JobOperation) the following:"
                $JobDescriber = $Job.JobOperation
            }
            Write-Host "`t$($Job.Name)"

            # $SourceDestinations = $ExtractedJobData | Where-Object $_.JobName -eq $Job.Name | Select-Object Source, Destination
            $CopyFromTo = Get-UniqueDriveToFrom -SourceDestinations $($ExtractedJobData | Where-Object JobName -eq $Job.Name | Select-Object Source, Destination)
            foreach ($Entry in $CopyFromTo) {
                # If the Destination is an array object, then make it more readable by adding a ', ' after every drive letter
                $Message = "`t`tCopying from the drive<1> <2> to the drive<3> <4>"
                if ($Entry.Destination -is [array]) {
                    Write-Verbose "$($Entry.Source) -> $($Entry.Destination -join ', ')"
                    $Message = $Message.Replace('<1>', '')
                    $Message = $Message.Replace('<2>', $($Entry.Source))
                    $Message = $Message.Replace('<3>', $(if ($Entry.Destination.Length -gt 1) { 's' }else { '' }))
                    $Message = $Message.Replace('<4>', $($Entry.Destination -join ', '))
                    Write-Host $Message
                }
                else {
                    Write-Verbose "$($Entry.Source  -join ', ') -> $($Entry.Destination)"
                    $Message = $Message.Replace('<1>', $(if ($Entry.Source.Length -gt 1) { 's' }else { '' }))
                    $Message = $Message.Replace('<2>', $($Entry.Source -join ', '))
                    $Message = $Message.Replace('<3>', '')
                    $Message = $Message.Replace('<4>', $($Entry.Destination))
                    Write-Host $Message
                }
            }
        }

        Write-Host "`nWARNING:  This script will over-write and/or delete files inside the destination\source folder if the files are out of date or do not exist in the other folder."

        $UserInput = Read-Host -Prompt "Do you want to continue with the process 'Y'es or 'N'o"

        if ($YesCharAnswer.Contains($UserInput)) {
            $UserInput = Read-Host -Prompt "This is a final confirmation of your input 'Y'es or 'N'o"
        }
    }while ($YesNoCharAnswer -notcontains $UserInput)
    
    if ($YesCharAnswer.Contains($UserInput)) {
        do {
            Clear-Host

            $PathsAreValid = Assert-ValidDrivesAndPaths -PathsToProcess $($ExtractedJobData | Select-Object Source, Destination, JobOperation, JobName)
            $ExtractedJobData | ForEach-Object { Write-Verbose $_ }
            if ($PathsAreValid) {
                #NEED TO SEE IF THERE IS A PERFORMANCE HIT USING THE TIME REMAINING FUNCTION
                #use the Measure-Command cmdlet to achieve this
                Start-Backup -JobsData $ExtractedJobData
                exit 1  #stop the program
            }
            else {
                $UserInput = Read-Host "Press any key to continue or press 'B'ack to go back to the main menu"
            }
        } while ($BackCharAnswer -notcontains $UserInput)
    }
}
#endregion

#region Perform backup
<#
.SYNOPSIS
Start the backup process

.DESCRIPTION
Start up the backup process given the supplied job data

.PARAMETER JobsData
The job data to copy from/to

.EXAMPLE
Start-Backup -JobsData $JobsData

.NOTES
(WIP) Need to make it so that $JobsData only contains the source and destination paths
#>
function Start-Backup {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, Position = 0)] [PSCustomObject] $JobsData
    )
    
    $TotalFileCount = Get-TotalFileCount -JobsData $JobsData
    Write-Verbose "File Count returned: $($TotalFileCount)"

    #region Robocopy parameters and what they do
    # MIR = Mirror mode
    # E = Copy subdirectories
    # W = Wait time between fails
    # R = Retry times
    # NP  = Don't show progress percentage in log
    # NDL = Don't log directory names
    # NC  = Don't log file classes (existing, new file, etc.)
    # BYTES = Show file sizes in bytes
    # NJH = Do not display robocopy job header (JH)
    # NJS = Do not display robocopy job summary (JS)
    # TEE = Display log in stdout AND in target log file

    #$CommonRobocopyParams = '/MIR /NP /NDL /NC /BYTES /NJH /NJS';
    #(/MIR) (/E) (/IS) (/NP) /NDL /NC /BYTES /NJH /NJS
    #endregion

    #This and the below two varaibles will use what is called splatting to replace the contents of the array/hashtable into a cmdlet https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_splatting?view=powershell-5.1
    $CommonRoboCopyParams = "/W:0", "/R:1", "/NDL", "/NC", "/BYTES", "/NJH", "/NJS"

    $OverallProgressParameters = @{
        ID               = 0
        Activity         = "TBD" # $JobOperation -eq $JobOperations.Backup ? "Generating backup for the job ""$JobName""" : "Restoring files for the job ""$JobName"""
        Status           = "Percent completed: 0%     Estimated time remaining: TDB" # "Percent completed: $OverallCopyPercent%     Estimated time remaining: $TimeToCompletion"
        PercentComplete  = 0 # $OverallCopyPercent
        CurrentOperation = "Files copied: 0 / TBD     Files left: TBD" # "Files copied: $(($TotalFilesProcessed + $JobFilesCopied - 1).ToString('N0')) / $($TotalFileCount.ToString('N0'))     Files left: $($OverallFilesLeft.ToString('N0'))"
    }

    $JobProgressParameters = @{
        ParentID         = 0
        ID               = 1
        Activity         = "TBD" # $JobOperation -eq $JobOperations.Backup ? "Currently backing up: ""$JobDescription""" : "Currently restoring: ""$JobDescription"""
        Status           = "Percent completed: 0%      File size: TBD     Processing file: TBD" # "Percent completed: $FileCopyPercent%      File size: $([string]::Format('{0:N0}', $FileSizeString))     Processing file: $FileName"
        PercentComplete  = 0 # $FileCopyPercent
        CurrentOperation = "Copied: 0 / TBD     Files Left: TBD" # "Copied: $(($JobFilesCopied - 1).ToString('N0')) / $($JobFileCount.toString('N0'))     Files Left: $($($JobFilesLeft + 1).ToString('N0'))"
    }

    # This object is used for passing additional variables that are required for the function "Get-RobocopyProgress" to work correctly
    $HelperVariables = @{
        "TotalFileCount" = $TotalFileCount
        "JobFileCount"   = "TBD"
        "FilesProcessed" = -1 # We set it to -1 because inside the function "Get-RobocopyProgress", it will auto increment it by one for when it gets to the first file.  This would result in it saying that a file has been completely proecessed when in reality it is starting to work on the first one
        "StartTime"      = Get-Date
    }
    
    # Start backing up\restoring the files
    foreach ($Entry in $JobsData) {
        Write-Verbose "Job being processed `"$($Entry.JobName)`": $($Entry | Select-Object Source, Destination, JobDescription)"

        $OverallProgressParameters.Activity = $Entry.JobOperation -eq $JobOperations.Backup ? "Generating backup for the job ""$($Entry.JobName)""" : "Restoring files for the job ""$($Entry.JobName)"""
        $JobProgressParameters.Activity = $Entry.JobOperation -eq $JobOperations.Backup ? "Currently backing up: ""$($Entry.JobDescription)""" : "Currently restoring: ""$($Entry.JobDescription)"""
        $HelperVariables.JobFileCount = $Entry.FileCount

        # it is a directory we are copying
        if ([String]::IsNullOrEmpty($Entry.FileMatching)) {
            if ([string]::IsNullOrEmpty($Global:UDThreadUsage)) {
                Write-Verbose "`tRunning the command 'Robocopy ""$($Entry.Source)"" ""$($Entry.Destination)"" /MIR $CommonRoboCopyParams'" # we use the $ instead of the @ as below because the @ can only be used as an argument to a command
                Robocopy.exe "$($Entry.Source)" "$($Entry.Destination)" /MIR @CommonRoboCopyParams | Get-RobocopyProgress -OverallProgressParameters $OverallProgressParameters -JobProgressParameters $JobProgressParameters -HelperVariables $HelperVariables
            }
            else {
                Write-Verbose "`tRunning the command 'Robocopy ""$($Entry.Source)"" ""$($Entry.Destination)"" /MIR /mt:$Global:UDThreadUsage $CommonRoboCopyParams'"
                Robocopy.exe "$($Entry.Source)" "$($Entry.Destination)" /MIR /mt:$Global:UDThreadUsage @CommonRoboCopyParams | Get-RobocopyProgress -OverallProgressParameters $OverallProgressParameters -JobProgressParameters $JobProgressParameters -HelperVariables $HelperVariables
            }
        }
        # It is a set of files we are copying
        else {
            # Split the list of allowed file types after every '/'.  In the powershell window if we were to do this command manually, we would have to enclose each one of these file conditions inside a set of quotation marks.  But for some reason, we don't have to do it here and it will not work with them included.
            $AllowedFileTypes = $Entry.FileMatching -split '/'

            if ([string]::IsNullOrEmpty($Global:UDThreadUsage)) {
                Write-Verbose "`tRunning the command 'Robocopy ""$($Entry.Source)"" ""$($Entry.Destination)"" $AllowedFileTypes $CommonRoboCopyParams'" # we use the $ instead of the @ as below because the @ can only be used as an argument to a command
                Robocopy.exe "$($Entry.Source)" "$($Entry.Destination)" @AllowedFileTypes @CommonRoboCopyParams | Get-RobocopyProgress -OverallProgressParameters $OverallProgressParameters -JobProgressParameters $JobProgressParameters -HelperVariables $HelperVariables
            }
            else {
                Write-Verbose "`tRunning the command 'Robocopy ""$($Entry.Source)"" ""$($Entry.Destination)"" $AllowedFileTypes /mt:$Global:UDThreadUsage $CommonRoboCopyParams'"
                Robocopy.exe "$($Entry.Source)" "$($Entry.Destination)" @AllowedFileTypes /mt:$Global:UDThreadUsage @CommonRoboCopyParams | Get-RobocopyProgress -OverallProgressParameters $OverallProgressParameters -JobProgressParameters $JobProgressParameters -HelperVariables $HelperVariables
            }
        }

        # $ProgressParams.TotalFilesProcessed += $Entry.FileCount
    }

    # Remove the progress bars because occasionally, the progress bars will stay on the terminal after processing the jobs
    Write-Progress -Id 1 -Activity "Completed" -Completed
    Write-Progress -Id 0 -Activity "Completed" -Completed
}
#endregion

#region Main Code that jump starts the script
Get-MainScreen
#endregion