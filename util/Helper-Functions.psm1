<#
Only put in the functions that are completed in here because the Write-Verbose command will not be accepted here
The variable $JobOperations is stored inside the AutoBackup.ps1 file
#>
$VerbosePreference = 'Continue'

<#
.SYNOPSIS
Gets the number of thread on your system

.DESCRIPTION
Using the WMIC utility, this function parses the number of thread on your system

.EXAMPLE
$MaxThreads = Get-MaxThreads

.NOTES
N.A.
#>
function Get-MaxThreads {
    [CmdletBinding()]
    param ()

    #get the max thread number of threads that the system can handle
    $MaxThreadsCommandResult = WMIC CPU Get NumberOfLogicalProcessors
    $ProcessedResult = ''

    Write-Verbose "Finding all digits from the string ""$([string]$MaxThreadsCommandResult)""" # the [string] converts the array of characters that WMIC returns into a string for printing out to the console
    foreach ($char in $MaxThreadsCommandResult) {
        if ($char -match '\d') {
            #if the character is a digit, append that digit to the variable $ProcessedResult
            Write-Verbose "Digit found"
            $ProcessedResult += $char
        }
    }
    
    return [int]$ProcessedResult  #return the data back as an integer
}

<#
.SYNOPSIS
Gets all the jobs you have defined inside the "Jobs" folder

.DESCRIPTION
This will fetch all the jobs you have created inside the "Jobs" folder and return a list of the file names without the extension of the file

.EXAMPLE
$Entry = Get-AvailableJobs

.NOTES
N.A.
#>
Function Get-AvailableJobs {
    [CmdletBinding()]
    param ()
    $Jobs = @()

    #Get a list of possible jobs from the "Jobs" folder
    Write-Verbose "Discovering all the jobs inside the folder ""Jobs""..."
    foreach ($csv in (Get-ChildItem ./Jobs -Filter *.csv | Select-Object Name)) {
        Write-Verbose "Job Discovered: ""$($csv.Name)"""
        $Jobs += [PSCustomObject]@{
                FileName     = "$([System.IO.Path]::GetFileNameWithoutExtension($csv.Name))"
                JobOperation = $Null
            }
    }

    $Jobs | Sort-Object FileName # Sort the Jobs by the job's file name

    # How you will iterate through this data that is returned
    # foreach ($Entry in $Jobs) {
    #     Write-Verbose $Entry
    # }
    # You can access them by using the following and replacing the 0 with anything between 0 and the length of the array - 1
    # Write-Verbose $Jobs[0]
    
    return # We don't have to add "return $Jobs" because the above command returns the object back to the calling function because of this reason https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_return?view=powershell-7.3#examples
}

<#
.SYNOPSIS
Reads the contents of the job to determine what the job should do

.DESCRIPTION
This will read the contents of the supplied job do determine how it script should handle the process
This will return a hashtable with the name of the job file as the key and it contains an arraylist of entries read from the job

.PARAMETER Entry
The name of the job to read

.PARAMETER ProcessType
Either "backup" or "restore"

.EXAMPLE
Get-JobContent -AllJobs "Game Files" -ProcessType "backup"
Get-JobContent "Game Saves" "restore"

.NOTES
(WIP) Working however, I would like to rework the function to make a more readable to the programmer
#>
function Get-JobsContent {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, Position = 0)] [array] $Entry
    )

    $JobsData = @{}  #makes a HashTable to store the jobs data
    $DuplicatedProcesses = $false

    foreach ($JobFileName in $Entry.FileName) {
        $SourceDestProcess = @() # this array is used to store a unique list of Source-Destination combinations

        Write-Verbose "Importing the file from here ""./Jobs/$JobFileName.csv"""
        try {
            $CSVImported = Import-csv "./Jobs/$JobFileName.csv" -Delimiter ","  #Attempt to import the csv file so that the script can read it (returns an array of objects)
        }
        catch {
            #Something happened and script is unable to import the file
            Write-Host "Error opening the CSV file `"$($JobFileName)`", error generated:
            `r$_
            `rTerminating the script"  # the "$_" is the current item/error
            exit 1
        }

        $JobsData.Add($JobFileName, [System.Collections.ArrayList]::new())

        $CurrentLineNumber = 2 # Starting at 2 because line 1 contains the headers for the file
        foreach ($Line in $CSVImported) {
            if ("$($Line.Source + $Line.Destination)" -notin $SourceDestProcess) {
                Write-Verbose "`tAdding the line ""$Line"""
                $JobsData.$JobFileName += $Line
                $SourceDestProcess += $($Line.Source + $Line.Destination)
            }
            else {
                Write-Host "Copy of a process was discovered in the file ""$JobFileName"" on line $CurrentLineNumber
                `r`tSource: $($Line.Source)
                `r`tDestination: $($Line.Destination)"
                $DuplicatedProcesses = $true
            }
            $CurrentLineNumber++
        }
    }

    if ($DuplicatedProcesses) {
        Write-Host "This script will not include the above duplicated process."
        Write-Host "Press any button to continue..."
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')    
    }

    # How you will iterate/access this data that is returned
    # foreach ($Job in $JobsData.Keys) {
    #     Write-Verbose "Job ""$Job"" Entries"
    #     foreach ($Entry in $JobsData.$Job) {
    #         Write-Verbose "`t$Entry"
    #     }
    # }

    return $JobsData
}

function Select-Data {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)] [PSCustomObject] $JobsData,
        [Parameter(Mandatory, Position = 1)] [PSObject] $Data
    )

    foreach ($Process in $JobsData.Keys) {
        foreach ($File in $JobsData.$Process.Keys) {
            foreach ($Entry in $JobsData.$Process.$File) {
                $Entry | Select-Object $Data
            }
        }
    }
}

<#
.SYNOPSIS
Determines if all the required drives and source folders are connected/exists 

.DESCRIPTION
This will determine if all of the required drives and source are connected/accessible to the PC for the supplied job data
It will return true if all the drives are connected and false otherwise

.PARAMETER Data
The data that contains all the information about the job

.EXAMPLE
Assert-ValidDrivesAndPaths -Data $Data

.NOTES
(WIP) going to reword so it only process the drive letters and not have to go through all the job data
#>
function Assert-ValidDrivesAndPaths {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, Position = 0)] [PSCustomObject] $Data
    )

    $PathsValid = $true
    $DriveErrors = $false
    $PathErrors = $false
    $ErrorData = @{}  #defines a hashtable to contain the errors detected
    $ErrorData["Drives"] = [System.Collections.ArrayList]::new()
    $ErrorData["Paths"] = [System.Collections.ArrayList]::new()

    #count the number of files inside each of the source directories    
    foreach ($ProcessType in $Data.Keys) {
        #for each 'backup' and 'restore' process
        Write-Verbose "Processing $ProcessType"
        foreach ($CurrentJob in $Data[$ProcessType].Keys) {
            #for each 'job' to process
            Write-Verbose "`tProcessing file $Entry"
            foreach ($Entry in $Data.$ProcessType.$CurrentJob) {
                #for each 'entry' inside the job, this formatting found here https://fercorrales.com/having-fun-with-nested-hash-tables-building-a-hard-coded-db/#:~:text=Let%27s%20see%20one,Enterprise
                $SourceDriveDetected = Test-Path $Entry.Source.substring(0, 2)
                $DestinationDriveDetected = Test-Path $Entry.Destination.substring(0, 2)
                if (!($SourceDriveDetected -and $DestinationDriveDetected)) {
                    #Drive not detected
                    $PathsValid = $false
                    $DriveErrors = $true
                    $ErrorData["Drives"] += if (!$SourceDriveDetected) { ([String]$Entry.Source[0]).ToUpper() } else { ([String]$Entry.Destination[0]).ToUpper() }
                }
                elseif (!(Test-Path $Entry.Source)) {
                    #source directory not detected   
                    $PathsValid = $false
                    $PathErrors = $true
                    $ErrorData["Paths"] += [PSCustomObject]@{
                        ProcessType = $ProcessType
                        Source      = $Entry.Source
                        Job         = $CurrentJob
                    }
                }
            }
        }
    }

    if (!$PathsValid) {
        if ($ErrorData["Drives"].size -ne 0) {
            Write-Host "Drive Error(s) detected:"
            $ErrorData["Drives"].foreach({ Write-Host "`tDrive `"$_`" is not detected." })  #the $_ means itself or current item
        }
        if ($ErrorData["Paths"].size -ne 0) {
            Write-Host "Path Error(s) detected:"
            $ErrorData["Paths"].foreach({
                    Write-Host "`tUnable to perform the $($_.ProcessType) process because the directory `"$($_.Source)`" doesn't exist for the job `"$($_.Job)`"." #the $_ means itself or current item
                })
        }

        #the void prevents it from adding additional entries for the output.  Why this happens is explained here https://stackoverflow.com/questions/8671602/problems-returning-hashtable
        Write-Host "`nPossible fixes for the above error(s):"
        if ($DriveErrors -and !$PathErrors) {
            Write-Host "1)  Connect the drive(s) to the PC so they can be detected.
            `r2)  Make sure that you have the correct drive letter for the source and destination paths inside the .csv file(s) (will require you to restart this script)."
        }
        elseif (!$DriveErrors -and $PathErrors) {
            Write-Host "1)  Make sure that your job(s) are using the correct process (Restore/Backup).
            `r2)  Make sure that the source and destination paths inside the .csv file(s) are correct (will require you to restart this script)."
        }
        else {
            # I don't know about option 4, because it reads the files inside the function Get-JobContent
            Write-Host "Drive Fixes:
            `r1)  Connect the drive(s) to the PC so they can be detected.
            `r2)  Make sure that you have the correct drive letter for the source and destination paths inside the .csv file(s) (will require you to restart this script).
            `rPath Fixes:
            `r3)  Make sure that your job(s) are using the correct process (Restore/Backup).
            `r4)  Make sure that the source and destination paths inside the .csv file(s) are correct (will require you to restart this script)."
        }    
    }

    return $PathsValid
}

<#
.SYNOPSIS
Gets the required drive letters for the supplied jobs

.DESCRIPTION
This will loop through every process -> job -> entry and pick out all unique drive letters from the jobs

.PARAMETER JobsToProcess
The data that was generated by the function Get-AvailableJobs

.PARAMETER JobsContent
The data that was generated by the function Get-JobsContent

.EXAMPLE
Get-RequiredDrives -AvailableJobs Get-AvailableJobs -JobsContent Get-JobsContent

.NOTES
N.A.
#>
function Get-RequiredDrives {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)] [array] $JobsToProcess,
        [Parameter(Mandatory, Position = 1)] [hashtable] $JobsContent
    )

    $RequiredDrives = @()  #defines an array to store the drives required for the job

    foreach ($Job in $JobsToProcess) {
        # If the information is queued to be processed
        Write-Verbose "Processing file ""$($Job.FileName)"" for the process ""$($Job.JobOperation)"" with the content"
        #this formatting found here https://www.itprotoday.com/powershell/powershell-basics-arrays-and-hash-tables#:~:text=Accessing%20Items%20in%20a%20Hash%20Table
        foreach ($Entry in $JobsContent.($Job.FileName)) {
            Write-Verbose "`t$Entry"
        }
        foreach ($Entry in $JobsContent.$($Job.FileName)) {
            Write-Verbose "Processing paths ""$($Entry.Source)"" and ""$($Entry.Destination)"""
            $SourceDrive = ([string]$Entry.Source[0]).ToUpper() # Get the drive letter
            $DestDrive = ([string]$Entry.Destination[0]).ToUpper() # Get the drive letter
            if ($RequiredDrives -notcontains $SourceDrive) {
                $RequiredDrives += $SourceDrive
                Write-Verbose "Drive ""$SourceDrive"" added to RequiredDrives"
                Write-Verbose "New contents of RequiredDrives: $($RequiredDrives -join ", ")"
            }
            if ($RequiredDrives -notcontains $DestDrive) {
                $RequiredDrives += $DestDrive
                Write-Verbose "Drive ""$DestDrive"" added to RequiredDrives"
                Write-Verbose "New contents of RequiredDrives: $($RequiredDrives -join ", ")"
            }
        }
    }

    $RequiredDrives | Sort-Object  #sorts the array in alphabetical order

    return # We don't have to add "return $RequiredDrives" because the above command returns the object back to the calling function because of this reason https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_return?view=powershell-7.3#examples

}

<#
<#
.SYNOPSIS
Return a unique list of source and destination combinations from the supplied data

.DESCRIPTION
This will read from the array of objects supplied and will pick out the unique source -> destination drive letters that the job will perform

.PARAMETER SourceDestination
An array of objects with the properties "Source" and "Destination" to read from

.PARAMETER Restoring
A switch to determine if the Source and Destination paths should be reversed because we are going to perform the restore operation on it

.EXAMPLE
$Data = @(
    @{Source="C:"; Destination="D:"},
    @{Source="C:"; Destination="E:"},
    @{Source="C:"; Destination="F:"},
    @{Source="G:"; Destination="H:"},
    @{Source="C:"; Destination="I:"},
    @{Source="J:"; Destination="K:"}
)
$Results = Get-UniqueDriveToFrom -SourceDestination $Data -Restoring
# OR
$Results = Get-UniqueDriveToFrom -SourceDestination $Data -Restoring:$true OR $false

.NOTES
N.A.
#>
#>
function Get-UniqueDriveToFrom {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)] [array] $SourceDestination,
        [Parameter()] [switch] $Restoring
    )

    $ReturnArray = @() # Will contain an array of objects of the style @{Source = ...; Destination = ...}

    foreach ($Entry in $SourceDestination) {
        # If we are restoring what is after the ? is the source/destination, otherwise what is after the : is the source/destination
        $SDrive = (-not $Restoring ? [string]$Entry.Source[0] : [string]$Entry.Destination[0] ).ToUpper()
        $DDrive = (-not $Restoring ? [string]$Entry.Destination[0] : [string]$Entry.Source[0]).ToUpper()
        if ($SDrive -notin $ReturnArray.Source) {
            Write-Verbose "New source drive ""$SDrive"" detected, creating new object for it for the destination drive ""$DDrive""..."
            # This has to be a PSCustomObject for the data to be more readable, it might work for the logic, however I don't know
            $ReturnArray += [PSCustomObject]@{
                Source = $SDrive
                Destination = @($DDrive)
            }
        }
        elseif ($SDrive -in $ReturnArray.Source) {
            Write-Verbose "A source drive ""$SDrive"" exists, appending to it for the destination drive ""$DDrive""..."
            $ObjectReference = $ReturnArray | Where-Object Source -eq $SDrive
            $ObjectReference.Destination += $DDrive
        }
        else {
            Write-Verbose "Un-processed entry $Entry"
        }
    }

    return $ReturnArray
}