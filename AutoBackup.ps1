# This will prevent the script from running unless the user is running the script in at least powershell version 7.0 https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_requires?view=powershell-7.3#-version-nn
#Requires -Version 7.0

# To enter debugging mode, uncomment the following line (will not be applied to the Helper-Functions.psm1 file, you have to go to that file and uncomment the same line of code)
# $VerbosePreference = "continue"

<#
 This is added because after PowerShell 7.2, it introduced this new variable and it is set to 'Minimal' by default.
 However, it causes my Write-Progress to not work as it should.
 So I have to manually set it to 'Classic' to get the old view back and have it work as it should.
#>
$PSStyle.Progress.View = "Classic"

#region Library Importing
Remove-Module Helper-Functions -Force -ErrorAction SilentlyContinue # This is added because an imported module is not removed unless you restart the powershell.  So if you modify the original file, the changes are not applied until it is removed and then re-imported
Import-Module -DisableNameChecking $PSScriptRoot\util\Helper-Functions.psm1
#endregion

#region Global variables used
# the @() defines an array
$YesNoCharAnswer = @('Y', 'y', 'N', 'n')
$NoCharAnswer = @('N', 'n')
$YesCharAnswer = @('Y', 'y')
$QuitCharAnswer = @('Q', 'q')
$BackCharAnswer = @('B', 'b')
$ClearCharAnswer = @('C', 'c')
# The variable $JobOperations is defined inside the file Helper-Functions.psm1 file because it used in both files and when we import the file into here, we get access the that variable, it will still work if you leave it here.
# However, if you make use of the file else where, it will not work 
$JobOperations = @{
    Backup  = "backup"
    Restore = "restore"
}
# Explanation for this found here https://stackoverflow.com/questions/30590972/global-variable-changed-in-function-not-effective and here https://techgenix.com/powershell-global-variable #>
$MaxThreadsNumber = Get-MaxThreads
$Global:UDThreadUsage = $Null
$AvailableJobs = Get-AvailableJobs # an array of objects
$JobsContent = Get-JobsContent $AvailableJobs # a hashtable of file names and file contents (which is an array containing PSCustomObjects)
$Global:JobCount = 0
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
}

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
                JobName      = $Job.Name
                JobOperation = $Job.JobOperation
                Source       = ($Job.JobOperation -ne $JobOperations.Restore ? $_.Source : $_.Destination)
                Destination  = ($Job.JobOperation -ne $JobOperations.Restore ? $_.Destination : $_.Source)
                Description  = $_.Description
                FileMatching = $_.FileMatching
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
                    # Write-Verbose "$($Entry.Source) -> $($Entry.Destination -join ', ')"
                    $Message = $Message.Replace('<1>', '')
                    $Message = $Message.Replace('<2>', $($Entry.Source))
                    $Message = $Message.Replace('<3>', $(if ($Entry.Destination.Length -gt 1) { 's' }else { '' }))
                    $Message = $Message.Replace('<4>', $($Entry.Destination -join ', '))
                    Write-Host $Message
                }
                else {
                    # Write-Verbose "$($Entry.Source  -join ', ') -> $($Entry.Destination)"
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

            $PathsAreValid = Assert-ValidDrivesAndPaths -PathsToProcess $($ExtractedJobData | Select-Object Source, Destination, JobOperation)
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
(WIP) Need to make it so that $JObsData only contains the source and destination paths
#>
function Start-Backup {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, Position = 0)] [PSCustomObject] $JobsData
    )
    
    Clear-Host 
    
    Write-Host "Determining how many files are to be processed..."
    # (WIP) I am most likely going to use Start-ThreadJob here as documented here
    # https://learn.microsoft.com/en-us/powershell/module/threadjob/start-threadjob?view=powershell-7.3
    # https://www.saggiehaim.net/background-jobs-start-threadjob-vs-start-job/
    # Count the number of files to be processed
    foreach ($Entry in $JobsData) {
        $SourceFileCount = 0
        $DestinationFileCount = 0;
        #it is a directory
        if ([String]::IsNullOrEmpty($Entry.FileMatching)) {
            Write-Host "Counting the number of files in the directories
            `r`tSource: ""$($Entry.Source)""
            `r`tDestination: ""$($Entry.Destination)"""
            #attempted to multi-thread this using "Start-Job" and "Start-Threadjob", but can't get the jobs to return the number of files, it always returns 7 for some reason https://www.youtube.com/watch?v=8xqrdk5sYyE&ab_channel=MrAutomation
            #"-File" means only get files, "-Force" means find hidden/system files, and "-Recurse" means go through all folders
            $SourceFileCount = (Get-ChildItem -Path $Entry.Source -File -Force -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count
            $DestinationFileCount = (Get-ChildItem -Path $Entry.Destination -file -force -recurse -ErrorAction SilentlyContinue | Measure-Object).Count
        }
        #it is a file or set of files with a extension
        else {
            Write-Host "Counting the number of files in the directory `"$($Entry.Source)`" that matches one of the following `"$($Entry.FileMatching.Replace('/',", "))`"..."

            $AllowedFileTypes = $Entry.FileMatching.Replace('/', '|')

            foreach ($Item in Get-ChildItem -Path $entry.Source -File -Force -ErrorAction SilentlyContinue) {
                # If the file has has the supplied extension
                if (($Item.GetType().Name -eq "FileInfo") -and ($Item.Mode -notmatch 'l') -and ($Item.Name -match $AllowedFileTypes)) {
                    $SourceFileCount++
                }
            }
            foreach ($Item in Get-ChildItem -Path $entry.Destination -File -Force -ErrorAction SilentlyContinue) {
                # If the file has has the supplied extension
                if (($Item.GetType().Name -eq "FileInfo") -and ($Item.Mode -notmatch 'l') -and ($Item.Name -match $AllowedFileTypes)) {
                    $DestinationFileCount++
                }
            }
        }
        $Entry | Add-Member -MemberType NoteProperty -Name 'FileCount' -Value ($SourceFileCount -gt $DestinationFileCount ? $SourceFileCount : $DestinationFileCount)

        Write-Verbose "`tFile count discovered $SourceFileCount and $DestinationFileCount"
        
        $TotalFileCount += $($Entry.FileCount)
    }
    
    Clear-Host

    Write-Verbose "Total number of files to be processed: $TotalFileCount"

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

    #this is called splatting https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_splatting?view=powershell-5.1
    $RoboCopyParams = "/MIR", "/W:0", "/R:1", "/NDL", "/NC", "/BYTES", "/NJH", "/NJS"
    $ProgressParams = @{
        "JobName"        = "TBD"
        "JobOperation"   = "TBD"
        "JobFileCount"   = "TBD"
        "TotalFileCount" = $TotalFileCount
        "FilesProcessed" = 0
        "StartTime"      = Get-Date
    }
    
    # Start backing up\restoring the files
    foreach ($Entry in $JobsData) {
        Write-Verbose "$($Entry.JobName) : $($Entry | Select-Object Source, Destination)"

        $ProgressParams.JobName = $Entry.JobName
        $ProgressParams.JobOperation = $Entry.JobOperation
        $ProgressParams.JobFileCount = $Entry.FileCount

        #it is a directory we are copying
        if ([String]::IsNullOrEmpty($Entry.FileMatching)) {
            if ([string]::IsNullOrEmpty($Global:UDThreadUsage)) {
                Write-Verbose "`tRunning the command 'Robocopy ""$($Entry.Source)"" ""$($Entry.Destination)"" $RoboCopyParams'" # we use the $ instead of the @ as below because the @ can only be used as an argument to a command
                Robocopy.exe "$($Entry.Source)" "$($Entry.Destination)" @RoboCopyParams | Get-RobocopyProgress @ProgressParams
            }
            else {
                Write-Verbose "`tRunning the command 'Robocopy ""$($Entry.Source)"" ""$($Entry.Destination)"" /mt:$Global:UDThreadUsage $RoboCopyParams'"
                Robocopy.exe "$($Entry.Source)" "$($Entry.Destination)" /mt:$Global:UDThreadUsage @RoboCopyParams | Get-RobocopyProgress @ProgressParams
            }

            $ProgressParams.FilesProcessed += $Entry.FileCount
        }
        # It is a set of files we are copying
        else {
            if (-not (Test-Path $Entry.Destination)) {
                #the destination directory doesn't exist yet
                New-Item $Entry.Destination -ItemType Directory | Out-Null  # The Out-Null makes it is so it doesn't display the directories creation.  https://stackoverflow.com/questions/46586382/hide-powershell-output
            }

            $AllowedFileTypes = $Entry.FileMatching.Replace('/', '|')
            foreach ($Item in Get-ChildItem -Path $Entry.Source) {
                # If the file has has the supplied extension
                if (($Item.GetType().Name -eq "FileInfo") -and ($Item.Mode -notmatch 'l') -and ($Item.Name -match $AllowedFileTypes)) {
                    # Copy-ItemWithProgress -from "$($Entry.source+"\"+$Item.name)" -to $($Entry.Destination + "\" + $Item.name) @ProgressParams -StartTime $StartTime
                    Write-Verbose "`tRunning the command 'Copy-Item ""$($Entry.Source+"\"+$Item.Name)"" -Destination ""$($Entry.Destination)""'"
                    Copy-Item "$($Entry.Source+"\"+$Item.name)" -Destination "$($Entry.Destination)"
                    $ProgressParams.FilesProcessed += 1
                }
            }
        }
    }

    Write-Progress -Id 1 -Activity "temp" -Completed
    Write-Progress -Id 0 -Activity "temp" -Completed
}

<#
.SYNOPSIS
Get the progress of the robocopy command

.DESCRIPTION
This will parse the data from the robocopy command to find out how much the file is copied and will continue to do so until robocopy has finished processing the files

.PARAMETER InputObject
The data from the robocopy command that is piped into this function

.PARAMETER JobName
The name of the job that is being processed

.PARAMETER JobFileCount
The number of files to be processed for the current job

.PARAMETER TotalFileCount
The total number of files to be processed

.PARAMETER FilesProcessed
The number of files that have been processed

.PARAMETER StartTime
The datetime that the backup process has been initiated

.EXAMPLE
Robocopy "C:" "D:" /MIR /W:0 /R:1 | Get-RobocopyProgress -JobName "Game files" -JobFileCount = 123 -TotalFileCount 123 -FilesProcessed 0 -StartTime Get-Date

.NOTES
(WIP) I might rename some of the variables to make it easier to know what they stand for and the source for this function was found here https://www.reddit.com/r/PowerShell/comments/p4l4fm/better_way_of_robocopy_writeprogress/h97skef/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button
#>
function Get-RobocopyProgress {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, ValueFromPipeline)] $InputObject,
        [Parameter(Mandatory, Position = 0)] [String] $JobName,
        [Parameter(Mandatory, Position = 1)] [String] $JobOperation,
        [Parameter(Mandatory, Position = 2)] [double] $JobFileCount,        
        [Parameter(Mandatory, Position = 3)] [double] $TotalFileCount,
        [Parameter(Mandatory, Position = 4)] [double] $FilesProcessed,
        [Parameter(Mandatory, Position = 5)] [datetime] $StartTime
    )

    begin {
        #region RoboCopy variables
        [string]$FileName = " "
        [double]$FileCopyPercent = 0
        [double]$FileSize = $Null
        [double]$JobFilesLeft = $JobFileCount
        [double]$JobFilesCopied = 0
        #endregion
        #region Overall progress variables
        [double]$OverallCopyPercent = 0
        [double]$OverallFilesLeft = $TotalFileCount - $FilesProcessed + 1
        #endregion
    }

    process {
        #region Robocopy data parsing
        $data = $InputObject -split '\x09'  #the \x09 is the ASCII code for "Tab" Source https://buckwoody.wordpress.com/2017/01/18/data-wrangling-regular-expressions/

        #The file has been copied so get the name of file being copied and increment/de-increment the counting variables
        If (-not [String]::IsNullOrEmpty("$($data[4])")) {
            $FileName = $data[4] -replace '.+\\(?=(?:.(?!\\))+$)' # This Regex search command removes the folder path to the file only extracts the file's name from it
            $JobFilesLeft--
            $JobFilesCopied++
            $OverallFilesLeft--
        }
        #get the file's copy percent
        If (-not [String]::IsNullOrEmpty("$($data[0])")) {
            $FileCopyPercent = ($data[0] -replace '%') -replace '\s'  #issue with this line because it occasionally receives a string and not a number?
        }
        #get the file's size
        If (-not [String]::IsNullOrEmpty("$($data[3])")) {
            $FileSize = $data[3]  #issue with this line because it occasionally receives an empty string?
        }
        #convert the double file size to it't most readable format
        [string]$FileSizeString = switch ($FileSize) {
            { $_ -gt 1TB -and $_ -lt 1024TB } {
                "$("{0:n2}" -f ($FileSize / 1TB) + " TB")"
            }
            { $_ -gt 1GB -and $_ -lt 1024GB } {
                "$("{0:n2}" -f ($FileSize / 1GB) + " GB")"
            }
            { $_ -gt 1MB -and $_ -lt 1024MB } {
                "$("{0:n2}" -f ($FileSize / 1MB) + " MB")"
            }
            { $_ -ge 1KB -and $_ -lt 1024KB } {
                "$("{0:n2}" -f ($FileSize / 1KB) + " KB")"
            }
            { $_ -lt 1KB } {
                "$FileSize B"
            }
        }
        #endregion

        #region Variables shared by the "Overall progress calculation" and "Estimated time remaining calculation" regions
        $FilesProcessedNow = $FilesProcessed + $JobFilesCopied
        #endregion

        #region Overall progress calculation
        $OverallCopyPercent = if ($FilesProcessedNow -gt 0) { ((($FilesProcessedNow - 1) / $TotalFileCount) * 100).ToString("###.#") }else { 0 }
        #endregion

        #region Estimated time remaining calculation
        $TimeToCompletion = Get-TimeRemaining -StartTime $StartTime -ProgressPercent $OverallCopyPercent
        #endregion

        #see if using 'n (new line in powershell) will add a line between the two write-process (place inside the CurrentOperation argument for the first write-progress)
        #see about implementing the estimated time remaining using something like the code described here https://chuvash.eu/2020/09/22/estimated-completion-in-write-progress-in-powershell/
        #this is called splatting https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_splatting?view=powershell-5.1
        $BackupProgressParameters = @{
            ID               = 0
            Activity         = $JobOperation -eq $JobOperations.Backup ? "Generating backup" : "Restoring files"
            Status           = "Percent completed: $OverallCopyPercent%     Estimated time remaining: $TimeToCompletion"
            PercentComplete  = $OverallCopyPercent
            CurrentOperation = "Files copied: $(($FilesProcessed + $JobFilesCopied - 1).ToString('N0')) / $($TotalFileCount.ToString('N0'))     Files left: $($OverallFilesLeft.ToString('N0'))"
        }

        $RoboCopyProgressParameters = @{
            ID               = 1
            ParentID         = 0
            Activity         = $JobOperation -eq $JobOperations.Backup ? "Currently backing up: $JobName" : "Currently restoring: $JobName"
            Status           = "Percent completed: $FileCopyPercent%      File size: $([string]::Format('{0:N0}', $FileSizeString))     Processing file: $FileName"
            PercentComplete  = $FileCopyPercent
            CurrentOperation = "Copied: $(($JobFilesCopied - 1).ToString('N0')) / $($JobFileCount.toString('N0'))     Files Left: $($JobFilesLeft.ToString('N0'))"  # Copying: $($JobFilesCopied.ToString('N0')) of $($JobFileCount.toString('N0'))
        }

        Assert-Progress -OverallProgressParams $BackupProgressParameters -CurrentProgressParams $RoboCopyProgressParameters
    }
}

<#
.SYNOPSIS
Get the time remaining for the process

.DESCRIPTION
This function will return the time remaining for the process to finish

.PARAMETER StartTime
The start time of the process

.PARAMETER ProgressPercent
The percent of the overall copy progress

.EXAMPLE
Get-TimeRemaining -StartTime Get-Date -ProgressPercent 85.76

.NOTES
Source for the process (either with the 3 up votes, they are copies of each other) https://social.msdn.microsoft.com/Forums/vstudio/en-US/5d847962-2e7c-4b3b-bccd-7492936bef33/how-could-i-create-an-estimated-time-remaining?forum=csharpgeneral with some modifications on my end.
#>
function Get-TimeRemaining {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, Position = 0)] [datetime] $StartTime,
        [Parameter(Mandatory, Position = 1)] [double] $ProgressPercent
    )

    if ($ProgressPercent -gt 0) {
        $TimeSpent = $(Get-Date) - $StartTime
        $TimeRemainingInSeconds = [Math]::Ceiling($TimeSpent.TotalSeconds / $ProgressPercent * (100 - $ProgressPercent))
        Write-Verbose "TimeSpent: $($TimeSpent.TotalSeconds)
            `r`tProgressPercent: $ProgressPercent
            `r`tTimeRemainingInSeconds: $TimeRemainingInSeconds"
        Return New-TimeSpan -Seconds $TimeRemainingInSeconds #convert the variable "TimeRemainingInSeconds" to a timespan variable
    }
    else {
        Return "TBD"
    }
}

<#
.SYNOPSIS
Display the progress to the user

.DESCRIPTION
This will take the argument objects as described below and write the progress to the screen

.PARAMETER OverallProgressParams
The parameters required for Write-Progress to write out the progress for the overall progress

.PARAMETER CurrentProgressParams
The parameters required for Write-Progress to write out the progress for the current job

.EXAMPLE
$BackupProgressParameters = @{
    ID               = 0
    Activity         = "Generating backup"
    Status           = "Percent Completed: 0%     Estimated time remaining: 1:30"
    PercentComplete  = .753
    CurrentOperation = "Files Copied: $((1256).ToString('N0'))     Files Left: $((2546).ToString('N0'))"
}
            
$CopyItemProgressParameters = @{
    ID               = 1
    ParentID         = 0
    Activity         = "Currently Backing Up: Game files"
    Status           = "Currently Copying file: SomeGameFile     File Size: $([string]::Format('{0:N0}', "1267891585"))     Percent Completed: .485%"
    PercentComplete  = .931
    CurrentOperation = "Copied: $((188).ToString('N0')) / $((256).toString('N0'))     Files Left: $((66).ToString('N0'))"
}

Assert-Progress -OverallProgressParams $BackupProgressParameters -CurrentProgressParams $CopyItemProgressParameters
.NOTES
N.A.
#>
function Assert-Progress {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, Position = 0)] [Hashtable] $OverallProgressParams,
        [Parameter(Mandatory, Position = 1)] [Hashtable] $CurrentProgressParams
    )

    $Host.PrivateData.ProgressBackgroundColor = 'Cyan' 
    $Host.PrivateData.ProgressForegroundColor = 'Black'
    
    Write-Progress @OverallProgressParams
    Write-Progress @CurrentProgressParams
}

#region Main Code that jump starts the script
Get-MainScreen
#endregion