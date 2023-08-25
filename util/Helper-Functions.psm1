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
Returns an array of PSCustomObjects
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
                Name     = "$([System.IO.Path]::GetFileNameWithoutExtension($csv.Name))"
                JobOperation = $Null
            }
    }

    $Jobs | Sort-Object Name # Sort the Jobs by the job's file name

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

.EXAMPLE
Get-JobContent -Entry "Game Files" -ProcessType "backup"
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

    foreach ($JobName in $Entry.Name) {
        $SourceDestProcess = @() # this array is used to store a unique list of Source-Destination combinations

        Write-Verbose "Importing the file from here ""./Jobs/$JobName.csv"""
        try {
            $CSVImported = Import-csv "./Jobs/$JobName.csv" -Delimiter ","  #Attempt to import the csv file so that the script can read it (returns an array of objects)
        }
        catch {
            #Something happened and script is unable to import the file
            Write-Host "Error opening the CSV file `"$($JobName)`", error generated:
            `r$_
            `rTerminating the script"  # the "$_" is the current item/error
            exit 1
        }

        $JobsData.Add($JobName, [System.Collections.ArrayList]::new())

        $CurrentLineNumber = 2 # Starting at 2 because line 1 contains the headers for the file
        foreach ($Line in $CSVImported) {
            if ("$($Line.Source + $Line.Destination)" -notin $SourceDestProcess) {
                Write-Verbose "`tAdding the line ""$Line"""
                $JobsData.$JobName += $Line
                $SourceDestProcess += $($Line.Source + $Line.Destination)
            }
            else {
                Write-Host "Copy of a process was discovered in the file ""$JobName"" on line $CurrentLineNumber
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
(WIP) It works, but I am thinking about reworking it so it only process the drive letters and not have to go through all the job data
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
        Write-Verbose "Processing file ""$($Job.Name)"" for the process ""$($Job.JobOperation)"" with the content"
        #this formatting found here https://www.itprotoday.com/powershell/powershell-basics-arrays-and-hash-tables#:~:text=Accessing%20Items%20in%20a%20Hash%20Table
        foreach ($Entry in $JobsContent.($Job.Name)) {
            Write-Verbose "`t$Entry"
        }
        foreach ($Entry in $JobsContent.$($Job.Name)) {
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
.SYNOPSIS
Return a unique list of source and destination combinations from the supplied data

.DESCRIPTION
This will read from the array of objects supplied and will pick out the unique source -> destination drive letters that the job will perform

.PARAMETER SourceDestinations
An array of HashTables with the keys "Source" and "Destination" to read from

.PARAMETER Restoring
A switch to determine if the Source and Destination paths should be reversed because we are going to perform the restore operation on it

.EXAMPLE
$GameFiles = @(
    @{Source="C:\Users"; Destination="D:\Users"},
    @{Source="C:\Data"; Destination="E:\Data"},
    @{Source="C:\Test"; Destination="F:\Test"},
    @{Source="G:\five"; Destination="H:\five"},
    @{Source="C:\file"; Destination="I:\file"},
    @{Source="J:\tow"; Destination="K:\tow"}
)
OR
$GameSaves = @(
    @{Source="D:\Users"; Destination="C:\Users:},
    @{Source="E:\Data"; Destination="C:\Data:},
    @{Source="F:\Test"; Destination="C:\Test:},
    @{Source="H:\five"; Destination="G:\five:},
    @{Source="I:\file"; Destination="C:\file:},
    @{Source="K:\tow"; Destination"J:\tow"}
)
$Results = Get-UniqueDriveToFrom -SourceDestinations $GameFiles -Restoring
# OR
$Results = Get-UniqueDriveToFrom -SourceDestinations $GameFiles -Restoring:$true OR $false

.NOTES
Returns an array of objects of the style @{Source = 'Char or Array'; Destination = 'Char or Array'} depending on if the Source or Destination has the least number of Drive letters, in which case that side is the char and the other is the Array.
#>
function Get-UniqueDriveToFrom {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)] [array] $SourceDestinations,
        [Parameter()] [switch] $Restoring
    )
    
    $ReturnArray = @() # Will contain an array of objects of the style @{Source = ...; Destination = ...}
    
    # Make a new array of PSCustomObjects that only contains the drive letters
    # I can modify this so it is able to use remote/shared drives by replacing the [0] after the $_.(Source/Destination) with a regex matching command to match for one of the following conditions "DriveLetter:\" or "\\ipv4AddressORComputerName\FolderName" See your win-PE Semi-Auto imaging capturing utility for this regex command
    $ExtractedDrivesUsed = $SourceDestinations | ForEach-Object { [pscustomobject]@{ SDrive = $(if(-not $Restoring) {$_.Source[0]} else{$_.Destination[0]}); DDrive = $(if(-not $Restoring) {$_.Destination[0]} else{$_.Source[0]}) } } | Sort-Object SDrive, DDrive
    # Get the number of unique drive letters from both the source and destination drives and extract the number of unique items from them.  This is done by selecting only the unique (S/D)Drives and them measuring the object returned, and lastly selecting and expanding the property Count from the returned data
    $UniqueSDrivesCount = $ExtractedDrivesUsed | Select-Object SDrive -Unique | Measure-Object | Select-Object -ExpandProperty Count
    $UniqueDDrivesCount = $ExtractedDrivesUsed | Select-Object DDrive -Unique | Measure-Object | Select-Object -ExpandProperty Count
    # This will determine if we compress the source or destination drives list
    # More readable explanation: If the number of UNIQUE source drives is less than the number of UNIQUE destination drives, then we will compress the destination side into an array, otherwise it will compress the source side into an array
    # For Example instead of getting the first item below, we get the second that is easier to read:
    # 1. # of UNIQUE SDrives IS less than the # of UNIQUE DDrives
    #   (C->X, C->Y, C->Z) we would get (C -> X, Y, Z) (Compress Destination)
    # 2. # of UNIQUE SDrives IS NOT less than the # of UNIQUE DDrives
    #   (X->C, Y->C, Z->C) we would get (X, Y, Z -> C) (Compress Source)
    $DDriveCompress = if ($UniqueSDrivesCount -le $UniqueDDrivesCount) { $true } else { $false }
    Write-Verbose "Unique SDrive count($UniqueSDrivesCount) -le Unique DDrive count($UniqueDDrivesCount): $DDriveCompress"

    foreach ($Entry in $ExtractedDrivesUsed) {
        # If we are restoring what is after the ? is the source/destination, otherwise what is after the : is the source/destination
        $SDrive = ([string]$Entry.SDrive).ToUpper()
        $DDrive = ([string]$Entry.DDrive).ToUpper()
        if ($DDriveCompress -and $SDrive -notin $ReturnArray.Source) {
            Write-Verbose "New source drive ""$SDrive"" detected, creating new object for it for the destination drive ""$DDrive""..."

            $ReturnArray += [PSCustomObject]@{
                Source = $SDrive
                Destination = @($DDrive)
            }

            Write-Verbose "Entry created:
            `r`tSource: $($ReturnArray[$ReturnArray.Count - 1].Source) Type: $($ReturnArray[$ReturnArray.Count - 1].Source.GetType().Name)
            `r`tDestination: $($ReturnArray[$ReturnArray.Count - 1].Destination) Type: $($ReturnArray[$ReturnArray.Count - 1].Destination.GetType().BaseType)"
        }
        elseif (-not $DDriveCompress -and $DDrive -notin $ReturnArray.Destination) {
            Write-Verbose "New destination drive ""$DDrive"" detected, creating new object for it for the source drive ""$SDrive""..."

            $ReturnArray += [PSCustomObject]@{
                Source = @($SDrive)
                Destination = $DDrive
            }

            Write-Verbose "Entry created:
            `r`tSource: $($ReturnArray[$ReturnArray.Count - 1].Source) Type: $($ReturnArray[$ReturnArray.Count - 1].Source.GetType().BaseType)
            `r`tDestination: $($ReturnArray[$ReturnArray.Count - 1].Destination) Type: $($ReturnArray[$ReturnArray.Count - 1].Destination.GetType().Name)"
        }
        elseif ($DDriveCompress -and $SDrive -in $ReturnArray.Source -and $DDrive -notin $ReturnArray.Destination) {
            $ObjectReference = $ReturnArray | Where-Object Source -eq $SDrive
            $ObjectReference.Destination += $DDrive

            Write-Verbose "Entry modified for a new destination drive:
            `r`tSource: $($ObjectReference.Source)
            `r`tDestination: $($ObjectReference.Destination -join ', ')"
        }
        elseif (-not $DDriveCompress -and $DDrive -in $ReturnArray.Destination -and $SDrive -notin $ReturnArray.Source) {
            $ObjectReference = $ReturnArray | Where-Object Destination -eq $DDrive
            $ObjectReference.Source += $SDrive

            Write-Verbose "Entry modified for a new source drive:
            `r`tSource: $($ObjectReference.Source -join ', ')
            `r`tDestination: $($ObjectReference.Destination)"
        }
        else {
            Write-Verbose "Un-processed entry because the combination has been used before: $Entry"
        }
    }

    return $ReturnArray
}