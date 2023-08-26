<#
Only put in the functions that are completed in here because the Write-Verbose command will not be accepted here
The variable $JobOperations is stored inside the AutoBackup.ps1 file
#>
#$VerbosePreference = 'Continue'

# the @{} defines a hashtable (which can be cast to a PSCustomObject by adding [PSCustomObject] in front of the @)
$JobOperations = @{
    Backup  = "backup"
    Restore = "restore"
}

<#
.SYNOPSIS
Gets the number of thread on your system.

.DESCRIPTION
Using the WMIC utility, this function parses the number of thread on your system.

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
Gets all the jobs you have defined inside the "Jobs" folder.

.DESCRIPTION
This will fetch all the jobs you have created inside the "Jobs" folder.
It will return an array of PSCustomObjects of the style @{Name="Job Name"; JobOperation = $Null}

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
            Name         = "$([System.IO.Path]::GetFileNameWithoutExtension($csv.Name))"
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
This will read the contents of the supplied job do see what the content of the job is.
This will return a hashtable with the name of the job file as the key and it's value contains an arraylist of entries read from the job

.PARAMETER Entry
The name of the job to read.

.EXAMPLE
Get-JobContent -Entry "Job Name"
Get-JobContent "Job Name"

.NOTES
N.A.
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

<#
.SYNOPSIS
Gets the required drive letters for the supplied jobs.

.DESCRIPTION
This will loop through every path supplied and and pick out all unique drive letters from the jobs

.PARAMETER Paths
An array of PSCustomObject or HashTables that contains the the properties/keys "Source" and "Destination"

.EXAMPLE
Get-RequiredDrives -AvailableJobs Get-AvailableJobs -JobsContent Get-JobsContent

.NOTES
N.A.
#>
function Get-RequiredDrives {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)] [array] $Paths
    )

    $RequiredDrives = @()  #defines an array to store the drives required for the job

    foreach ($Entry in $Paths) {
        # If the information is queued to be processed
        Write-Verbose "Processing the paths Source: ""$($Entry.Source)"" and Destination: ""$($Entry.Destination)"""
        $SDrive = ([string]$Entry.Source[0]).ToUpper() # Get the drive letter
        $DDrive = ([string]$Entry.Destination[0]).ToUpper() # Get the drive letter
        if ($RequiredDrives -notcontains $SDrive) {
            $RequiredDrives += $SDrive
            Write-Verbose "Drive ""$SDrive"" added to RequiredDrives"
            Write-Verbose "New contents of RequiredDrives: $($RequiredDrives -join ", ")"
        }
        if ($RequiredDrives -notcontains $DDrive) {
            $RequiredDrives += $DDrive
            Write-Verbose "Drive ""$DDrive"" added to RequiredDrives"
            Write-Verbose "New contents of RequiredDrives: $($RequiredDrives -join ", ")"
        }
    }

    $RequiredDrives | Sort-Object  #sorts the array in alphabetical order
    Write-Verbose "Data that should be returned: $($($RequiredDrives | Sort-Object) -join ', ')"

    return # We don't have to add "return $RequiredDrives" because the above command returns the object back to the calling function because of this reason https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_return?view=powershell-7.3#examples
}

<#
.SYNOPSIS
Return a unique list of source and destination combinations from the supplied data

.DESCRIPTION
This will read from the array of objects supplied and will pick out the unique source -> destination drive letters that the job will perform.  It will also compress the list as much as possible so there is as little to read as possible

.PARAMETER SourceDestinations
An array of PSCustomObjects or HashTables with the properties\keys "Source" and "Destination"

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
    @{Source="D:\Users"; Destination="C:\Users"},
    @{Source="E:\Data"; Destination="C:\Data"},
    @{Source="F:\Test"; Destination="C:\Test"},
    @{Source="H:\five"; Destination="G:\five"},
    @{Source="I:\file"; Destination="C:\file"},
    @{Source="K:\tow"; Destination"J:\tow"}
)
$Results = Get-UniqueDriveToFrom -SourceDestinations $GameFiles
# OR
$Results = Get-UniqueDriveToFrom $GameFiles

.NOTES
Returns an array of objects of the style @{Source = 'Char or Array'; Destination = 'Char or Array'} depending on if the Source or Destination has the least number of Drive letters, in which case that side is the char and the other is the Array.
#>
function Get-UniqueDriveToFrom {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)] [array] $SourceDestinations
    )
    
    $ReturnArray = @() # Will contain an array of objects of the style @{Source = ...; Destination = ...}
    
    # Make a new array of PSCustomObjects that only contains the drive letters
    # I can modify this so it is able to use remote/shared drives by replacing the [0] after the $_.(Source/Destination) with a regex matching command to match for one of the following conditions "DriveLetter:\" or "\\ipv4AddressORComputerName\FolderName" See your win-PE Semi-Auto imaging capturing utility for this regex command
    $SourceDestinationDrives = $SourceDestinations | ForEach-Object { [pscustomobject]@{ SDrive = $_.Source[0]; DDrive = $_.Destination[0] } } | Sort-Object SDrive, DDrive

    # Get the number of unique drive letters from both the source and destination drives and extract the number of unique items from them.  This is done by selecting only the unique (S/D)Drives and them measuring the object returned, and lastly selecting and expanding the property Count from the returned data
    $UniqueSDrivesCount = $SourceDestinationDrives | Select-Object SDrive -Unique | Measure-Object | Select-Object -ExpandProperty Count
    $UniqueDDrivesCount = $SourceDestinationDrives | Select-Object DDrive -Unique | Measure-Object | Select-Object -ExpandProperty Count

    # This will determine if we compress the source or destination drives list
    # More readable explanation: If the number of UNIQUE source drives is less than the number of UNIQUE destination drives, then we will compress the destination side into an array, otherwise it will compress the source side into an array
    # For Example instead of getting the first item below, we get the second that is easier to read:
    # 1. # of UNIQUE SDrives IS less than the # of UNIQUE DDrives
    #   (C->X, C->Y, C->Z) we would get (C -> X, Y, Z) (Compress Destination)
    # 2. # of UNIQUE SDrives IS NOT less than the # of UNIQUE DDrives
    #   (X->C, Y->C, Z->C) we would get (X, Y, Z -> C) (Compress Source)
    $DDriveCompress = $UniqueSDrivesCount -le $UniqueDDrivesCount ? $true : $false
    Write-Verbose "Unique SDrive count($UniqueSDrivesCount) -le Unique DDrive count($UniqueDDrivesCount): $DDriveCompress"

    foreach ($Entry in $SourceDestinationDrives) {
        # If we are restoring what is after the ? is the source/destination, otherwise what is after the : is the source/destination
        $SDrive = ([string]$Entry.SDrive).ToUpper()
        $DDrive = ([string]$Entry.DDrive).ToUpper()
        if ($DDriveCompress -and $SDrive -notin $ReturnArray.Source) {
            Write-Verbose "New source drive ""$SDrive"" detected, creating new object for it for the destination drive ""$DDrive""..."

            $ReturnArray += [PSCustomObject]@{
                Source      = $SDrive
                Destination = @($DDrive)
            }

            Write-Verbose "Entry created:
            `r`tSource: $($ReturnArray[$ReturnArray.Count - 1].Source) Type: $($ReturnArray[$ReturnArray.Count - 1].Source.GetType().Name)
            `r`tDestination: $($ReturnArray[$ReturnArray.Count - 1].Destination) Type: $($ReturnArray[$ReturnArray.Count - 1].Destination.GetType().BaseType)"
        }
        elseif (-not $DDriveCompress -and $DDrive -notin $ReturnArray.Destination) {
            Write-Verbose "New destination drive ""$DDrive"" detected, creating new object for it for the source drive ""$SDrive""..."

            $ReturnArray += [PSCustomObject]@{
                Source      = @($SDrive)
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

<#
.SYNOPSIS
Determines if all the required drives and source folders are connected/present.

.DESCRIPTION
This will determine if all of the required drives and source folders are connected/present to the PC for the supplied job data
It will return true if all the drives are connected and the source paths exists and false otherwise

.PARAMETER PathsToProcess
The data that contains at a minimum, an array of PSCustomObject (I have tested) or HashTables (I have not tested) that contains the properties\keys "JobName", "JobOperation", "Source", and "Destination"

.EXAMPLE
$Data = @(
    [PSCustomObject]@{JobName="Game Files"; JobOperation='backup'; Source="R:\Steam\steamapps\common"; Destination="A:\Steam\steamapps\common"}, # Fails on Drives
    [PSCustomObject]@{JobName="Game Files"; JobOperation='backup'; Source="C:\Steam\steamapps"; Destination="D:\Steam\steamapps"}, #Fails on Source path
    [PSCustomObject]@{JobName="WorkShop Game Files"; JobOperation='restore';Source="D:\Steam\steamapps\workshop\content"; Destination="C:\Steam\steamapps\workshop\content"}, # Fails on Destination path
    [PSCustomObject]@{JobName="WorkShop Game Files"; JobOperation='backup'; Source="D:\Steam\steamapps\workshop"; Destination="C:\Steam\steamapps\workshop"} # Valid entry (Destination path is not processed, only the Destination drive path will be)
)

Assert-ValidDrivesAndPaths -PathsToProcess $Data
Assert-ValidDrivesAndPaths $Data

.NOTES
N.A.
#>
function Assert-ValidDrivesAndPaths {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, Position = 0)] [array] $PathsToProcess
    )

    $DriveErrors = $false
    $PathErrors = $false
    $ErrorData = @{
        Drives = @()
        Paths  = @()
    }  #defines a hashtable that has two arrays inside it to contain the errors detected

    foreach ($Entry in $PathsToProcess) {
        Write-Verbose "Processing ""$Entry"""

        $SPath = $Entry.Source
        $DPath = $Entry.Destination
        Write-Verbose "JobOperation: $($Entry.JobOperation -eq $JobOperations.Restore)
        `r`tSource: $SPath
        `r`tDestination: $DPath"

        $SDrive = $SPath.substring(0, 2)
        $DDrive = $DPath.substring(0, 2)

        $SDriveDetected = Test-Path $SDrive
        Write-Verbose "Results of Test-Path $SDrive = $SDriveDetected"
        $DDriveDetected = Test-Path $DDrive
        Write-Verbose "Results of Test-Path $DDrive = $DDriveDetected"
        $SPathDetected = Test-Path $SPath
        Write-Verbose "Results of Test-Path $SPath = $SPathDetected"

        if (-not $SDriveDetected -and ([String]$SDrive[0]).ToUpper() -notin $ErrorData.Drives) {
            Write-Verbose "`tSource drive ""$(([String]$SDrive[0]).ToUpper())"" not detected"
            $DriveErrors = $true
            $ErrorData.Drives += ([String]$SDrive[0]).ToUpper()
        }
        elseif (-not $SPathDetected) {
            # -and $SPath -notin $ErrorData.Paths
            Write-Verbose "`tSource path ""$SPath"" not detected"
            $PathErrors = $true
            $ErrorData.Paths += [PSCustomObject]@{
                JobName     = $Entry.JobName
                ProcessType = $Entry.JobOperation
                Source      = $SPath
            }
        }
        if (-not $DDriveDetected -and ([String]$DDrive[0]).ToUpper() -notin $ErrorData.Drives) {
            Write-Verbose "`tDestination drive ""$(([String]$DDrive[0]).ToUpper())"" not detected"
            $DriveErrors = $true
            $ErrorData.Drives += ([String]$DDrive[0]).ToUpper()
        }
    }

    if ($DriveErrors) {
        Write-Host ""
        $Message = "Drive Error<1> detected:
        `r`tDrive<1> <2> was not detected."
        $Message = $ErrorData.Drives.Count -gt 1 ? $Message.Replace("<1>", 's').Replace("was", "were") : $Message.Replace("<1>", '')
        $ErrorData.Drives = $ErrorData.Drives | Sort-Object
        Write-Host $Message.Replace("<2>", $ErrorData.Drives -join ', ')
    }
    if ($PathErrors) {
        $Message = "Path Error<1> detected, unable to perform the below job<2> for the reason<1> below:"
        $Message = $ErrorData.Paths.Count -gt 1 ? $Message.Replace("<1>", 's') : $Message.Replace("<1>", '')
        $NumJobsHaveErrors = $ErrorData.Paths | Select-Object JobName -Unique | Measure-Object | Select-Object -ExpandProperty Count
        $Message = $NumJobsHaveErrors -gt 1 ? $Message.Replace("<2>", 's') : $Message.Replace("<2>", '')
        Write-Host $Message
        $ErrorData.Paths.foreach({
                Write-Host "`tCan't $($_.ProcessType)$(if($_.ProcessType -eq $JobOperations.Restore){" from"}) the directory `"$($_.Source)`" for the job `"$($_.JobName)`" because it doesn't exist." #the $_ means itself or current item
            })
    }
    
    if ($DriveErrors -or $PathErrors) { Write-Host "`nPossible fixes for the above error(s):" }
    if ($DriveErrors -and -not $PathErrors) {
        Write-Host "1)  Connect the drive(s) to the PC so they can be detected.
        `r2)  Make sure that you have the correct drive letter for the source and destination paths inside the .csv file(s) (will require you to restart this script)."
    }
    elseif (-not $DriveErrors -and $PathErrors) {
        Write-Host "1)  Make sure that your job(s) are using the correct process (Restore/Backup).
        `r2)  Make sure that the source and destination paths inside the .csv file(s) are correct (will require you to restart this script)."
    }
    elseif ($DriveErrors -and $PathErrors) {
        # I don't know about option 4, because it reads the files inside the function Get-JobContent
        Write-Host "Drive Fixes:
        `r1)  Connect the drive(s) to the PC so they can be detected.
        `r2)  Make sure that you have the correct drive letter for the source and destination paths inside the .csv file(s) (will require you to restart this script).
        `rPath Fixes:
        `r3)  Make sure that your job(s) are using the correct process (Restore/Backup) for the folders\files on your system.
        `r4)  Make sure that the source and destination paths inside the .csv file(s) are correct (will require you to restart this script)."
    }

    return -not $DriveErrors -and -not $PathErrors
}