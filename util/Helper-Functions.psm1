# Only put in the functions that are completed in here because the Write-Verbose command will not be executed unless you uncomment out the below line
# $VerbosePreference = "Continue"

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
    [PSCustomObject]@{JobName="Game Files"; JobOperation='backup'; Source="R:\Steam\steamapps\common"; Destination="A:\Steam\steamapps\common"}, # Fails on Drives letters
    [PSCustomObject]@{JobName="Game Files"; JobOperation='backup'; Source="C:\Steam\steamapps"; Destination="D:\Steam\steamapps"}, # Fails on Source path
    [PSCustomObject]@{JobName="WorkShop Game Files"; JobOperation='restore';Source="D:\Steam\steamapps\workshop\content"; Destination="C:\Steam\steamapps\workshop\content"}, # Fails on Destination path, because we are restoring
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
        Write-Verbose "Is the JobOperation restoring: $($Entry.JobOperation -eq $JobOperations.Restore)
        `r`tSource: $SPath
        `r`tDestination: $DPath"

        $SDrive = $SPath.substring(0, 2).ToUpper()
        $DDrive = $DPath.substring(0, 2).ToUpper()

        $SDriveDetected = Test-Path $SDrive
        Write-Verbose "Results of Test-Path for source drive $SDrive = $SDriveDetected"
        $DDriveDetected = Test-Path $DDrive
        Write-Verbose "Results of Test-Path for destination drive $DDrive = $DDriveDetected"
        $SPathDetected = Test-Path $SPath
        Write-Verbose "Results of Test-Path for source path $SPath = $SPathDetected"

        if (-not $SDriveDetected -and $SDrive[0] -notin $ErrorData.Drives) {
            Write-Verbose "`tSource drive ""$($SDrive[0])"" not detected"
            $DriveErrors = $true
            $ErrorData.Drives += $SDrive[0]
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
            $ErrorData.Drives += $DDrive[0]
        }
        
        Write-Verbose ""
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

<#
.SYNOPSIS
A new like operator that allows for multiple like conditions in one easy to use function
Source for this function but converting it into powershell https://stackoverflow.com/a/13019721

.DESCRIPTION
This will take two arguments, FileName and ValidFileTypes, and it will determine if the file should be processed

.PARAMETER FileName
The name of the file you wish to check

.PARAMETER ValidFileTypes
An array of valid like operators that says the file should be selected

.EXAMPLE
New-LikeOperator -FileName 'This is a new file.txt' -ValidFileTypes @(This*, *new*, *.txt)

.NOTES
N.A.
#>
function Compare-FileMatch {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, Position = 0)] [string] $FileName,
        [Parameter(Mandatory, Position = 1)] [array] $ValidFileTypes
    )
    
    # We don't have to inclose the pattern variable inside a set of "" inside the below if statment, they are not required.  They are only required if you manauly use the like comparison operator inside a terminal
    foreach ($pattern in $ValidFileTypes) { if ($FileName -like $pattern) { return $true; } }
    return $false;
}

<#
.SYNOPSIS
Gets the total number of files to be processed

.DESCRIPTION
This will go through every 
.PARAMETER FileName
The name of the file you wish to check

.PARAMETER ValidFileTypes
An array of valid like operators that says the file should be selected

.EXAMPLE
New-LikeOperator -FileName 'This is a new file.txt' -ValidFileTypes @(This*, *new*, *.txt)

.NOTES
N.A.
#>
function Get-TotalFileCount {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)] [PSCustomObject] $JobsData
    )
    Clear-Host 
    
    Write-Host "Determining how many files are to be processed..."
    # (WIP) I am most likely going to use Start-ThreadJob here as documented here
    # https://learn.microsoft.com/en-us/powershell/module/threadjob/start-threadjob?view=powershell-7.3
    # https://www.saggiehaim.net/background-jobs-start-threadjob-vs-start-job/
    # Count the number of files to be processed

    $TotalFileCount = 0
    $GetOnlyFiles = { ($_.GetType().Name -eq "FileInfo") -and ($_.Mode -notmatch 'l') }  # This contains the logic for filtering for the Where-Object so we only have one copy of it.  To use this we simply say "Where-Object { & $GetOnlyFils }"  https://stackoverflow.com/questions/49071951/powershell-cast-conditional-statement-to-a-variable

    foreach ($Entry in $JobsData) {
        $InSourceAndDestination = 0;
        $InSourceXorDestination = 0;

        #it is a directory
        if ([String]::IsNullOrEmpty($Entry.FileMatching)) {
            Write-Host "Counting the number of files in the directories
            `r`tSource: ""$($Entry.Source)""
            `r`tDestination: ""$($Entry.Destination)"""
            # Attempted to multi-thread this using "Start-Job" and "Start-Threadjob", but can't get the jobs to return the number of files, it always returns 7 for some reason https://www.youtube.com/watch?v=8xqrdk5sYyE&ab_channel=MrAutomation
            # "-File" means only get files, "-Force" means find hidden/system files, and "-Recurse" means go through all folders
            # Goes through each file located inside the source directory and checks to see if the file exists in the targeted destination directory
            Get-ChildItem -Path $Entry.Source -File -Force -Recurse -ErrorAction SilentlyContinue |
            ForEach-Object {
                # We supply the argument -LiteralPath for the cmdlet Test-Path so that it uses exactly as it is typed. No characters are interpreted as wildcard characters. A complete list of these can be found here https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_wildcards?view=powershell-7.4  Where I found this solution https://stackoverflow.com/questions/10145775/test-path-fails-to-return-true-on-a-file-that-exists
                if (Test-Path -LiteralPath ($Entry.Destination + $_.FullName.Substring($Entry.Source.Length))) { $InSourceAndDestination += 1 }
                else { $InSourceXorDestination += 1 }
            }
            # Goes through each file located inside the destination directory and checks to see if the file exists in the targeted source directory
            Get-ChildItem -Path $Entry.Destination -File -Force -Recurse -ErrorAction SilentlyContinue |
            ForEach-Object {
                # We supply the argument -LiteralPath for the cmdlet Test-Path so that it uses exactly as it is typed. No characters are interpreted as wildcard characters. A complete list of these can be found here https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_wildcards?view=powershell-7.4  Where I found this solution https://stackoverflow.com/questions/10145775/test-path-fails-to-return-true-on-a-file-that-exists
                if (-not (Test-Path -LiteralPath ($Entry.Source + $_.FullName.Substring($Entry.Destination.Length)))) { $InSourceXorDestination += 1 }
            }
        }
        #it is a file or set of files
        else {
            Write-Host "Counting the number of files in the directory `"$($Entry.Source)`" that matches one of the following `"$($Entry.FileMatching.Replace('/',", "))`"..."

            # Split the list of allowed file types after every '/' so we make an array of items
            $AllowedFileTypes = $Entry.FileMatching -split '/'

            Get-ChildItem -Path $Entry.Source -File -Force -ErrorAction SilentlyContinue |
            Where-Object { (& $GetOnlyFiles) -and (Compare-FileMatch -FileName $_.Name -ValidFileTypes $AllowedFileTypes) } |
            ForEach-Object {
                if (Test-Path -LiteralPath ($Entry.Destination + "/" + $_.Name)) { $InSourceAndDestination += 1 }
                else { $InSourceXorDestination += 1 }
            }
            Get-ChildItem -Path $Entry.Destination -File -Force -ErrorAction SilentlyContinue |
            Where-Object { (& $GetOnlyFiles) -and (Compare-FileMatch -FileName $_.Name -ValidFileTypes $AllowedFileTypes) } |
            ForEach-Object {
                if (-not (Test-Path -LiteralPath ($Entry.Source + "/" + $_.Name))) { $InSourceXorDestination += 1 }
            }
        }

        Write-Verbose "File count common: $InSourceAndDestination
        `r`tdifferent: $InSourceXorDestination
        `r`tFiles to be processed: $($InSourceAndDestination + $InSourceXorDestination)"

        # Compares the two arrays and determine the number of files that will be processed, I.E. it will find the unique number of files in the source and destination https://java2blog.com/compare-contents-of-two-folders-powershell/
        # $FileCount = Compare-Object -ReferenceObject $SourceFiles -DifferenceObject $DestinationFiles -IncludeEqual |
        #     Measure-Object |
        #     Select-Object -ExpandProperty Count

        $Entry | Add-Member -MemberType NoteProperty -Name 'FileCount' -Value ($InSourceAndDestination + $InSourceXorDestination)
        
        $TotalFileCount += $($Entry.FileCount)
    }
    
    Clear-Host

    Write-Verbose "Total number of files to be processed: $TotalFileCount"

    return $TotalFileCount
}

<#
.SYNOPSIS
Get the progress of the robocopy command

.DESCRIPTION
This will parse the data from the robocopy command to find out how much the file is copied and will continue to do so until robocopy has finished processing the files

.PARAMETER InputObject
The data from the robocopy command that is piped into this function

.PARAMETER OverallProgressParameters
A hashtable containing the parameters that will be used for the Write-Progress command to display the overall progress

.PARAMETER JobProgressParameters
A hashtable containing the parameters that will be used for the Write-Progress command to display the job progress

.PARAMETER HelperVariables
A hashtable containing any extra variables that this function can use

.EXAMPLE
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

$HelperVariables = @{
    "TotalFileCount" = $TotalFileCount
    "JobFileCount"   = "TBD"
    "FilesProcessed" = -1 # We set it to -1 because inside the function "Get-RobocopyProgress", it will auto increment it by one for when it gets to the first file.  This would result in it saying that a file has been completely proecessed when in reality it is starting to work on the first one
    "StartTime"      = Get-Date
}

Robocopy "C:" "D:" /MIR /W:0 /R:1 | Get-RobocopyProgress -OverallProgressParameters $OverallProgressParameters -JobProgressParameters $JobProgressParameters -HelperVariables $HelperVariables

.NOTES
Source for this function was found here https://www.reddit.com/r/PowerShell/comments/p4l4fm/better_way_of_robocopy_writeprogress/h97skef/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button
#>
function Get-RobocopyProgress {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, ValueFromPipeline)] $InputObject,
        [Parameter(Mandatory, Position = 0)] [hashtable] $OverallProgressParameters,
        [Parameter(Mandatory, Position = 1)] [hashtable] $JobProgressParameters,
        [Parameter(Mandatory, Position = 2)] [hashtable] $HelperVariables
    )

    begin {
        #region Overall progress variables
        [double]$OverallCopyPercent = 0
        [double]$OverallFilesLeft = $HelperVariables.TotalFileCount - $HelperVariables.FilesProcessed - 1
        #endregion
        #region Job progress variables
        [string]$FileName = " "
        [double]$FileCopyPercent = 0
        [double]$FileSize = $Null
        [double]$JobFilesLeft = $HelperVariables.JobFileCount
        [double]$JobFilesCopied = 0
        #endregion
    }

    process {
        #region Robocopy data parsing
        $data = $InputObject -split '\x09'  #the \x09 is the ASCII code for "Tab" Source https://buckwoody.wordpress.com/2017/01/18/data-wrangling-regular-expressions/

        #A new file is being copied, so get the name of file being copied and increment/de-increment the counting variables
        If (-not [String]::IsNullOrEmpty("$($data[4])")) {
            $FileName = $data[4] -replace '.+\\(?=(?:.(?!\\))+$)' # This Regex search command removes the folder path to the file only extracts the file's name from it
            $HelperVariables.FilesProcessed++
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

        #region Progress calculations
        $OverallCopyPercent = if ($HelperVariables.FilesProcessed -gt 0) { (($HelperVariables.FilesProcessed / $HelperVariables.TotalFileCount) * 100).ToString("###.#") } else { 0 }
        $TimeToCompletion = Get-TimeRemaining -StartTime $HelperVariables.StartTime -ProgressPercent $OverallCopyPercent

        $OverallProgressParameters.Status = "Percent completed: $OverallCopyPercent%     Estimated time remaining: $TimeToCompletion"
        $OverallProgressParameters.PercentComplete = $OverallCopyPercent
        $OverallProgressParameters.CurrentOperation = "Files copied: $(($HelperVariables.FilesProcessed -ge 0 ? $HelperVariables.FilesProcessed : 0).ToString('N0')) / $(($HelperVariables.TotalFileCount).ToString('N0'))     Files left: $($OverallFilesLeft.ToString('N0'))"

        $JobProgressParameters.Status = "Percent completed: $FileCopyPercent%      File size: $([string]::Format('{0:N0}', $FileSizeString))     Processing file: $FileName"
        $JobProgressParameters.PercentComplete  = $FileCopyPercent
        $JobProgressParameters.CurrentOperation = "Copied: $(($JobFilesCopied - 1).ToString('N0')) / $(($HelperVariables.JobFileCount).toString('N0'))     Files Left: $($($JobFilesLeft).ToString('N0'))"
        #endregion

        Assert-Progress -OverallProgressParams $OverallProgressParameters -CurrentProgressParams $JobProgressParameters
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
The percent for the overall copy progress in whole number percentage, NOT decimal

.EXAMPLE
Get-TimeRemaining -StartTime Get-Date -ProgressPercent 85.76

.NOTES
Source for the process (either comment from Andreas Johansson, they are copies of the post) https://social.msdn.microsoft.com/Forums/vstudio/en-US/5d847962-2e7c-4b3b-bccd-7492936bef33/how-could-i-create-an-estimated-time-remaining?forum=csharpgeneral with some modifications on my end.
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
        <#Write-Verbose "TimeSpent: $($TimeSpent.TotalSeconds)
            `r`tProgressPercent: $ProgressPercent
            `r`tTimeRemainingInSeconds: $TimeRemainingInSeconds"#>
        return New-TimeSpan -Seconds $TimeRemainingInSeconds #convert the variable "TimeRemainingInSeconds" to a timespan variable
    }
    else {
        return "TBD"
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
$OverallProgressParameters = @{
    ID               = 0
    Activity         = Generating backup for the job ""Some Job Name"""
    Status           = "Percent Completed: 75.3%     Estimated time remaining: 1:30"
    PercentComplete  = .753
    CurrentOperation = "Files Copied: 1,256     Files Left: 2,546"
}
            
$JobProgressParameters = @{
    ParentID         = 0
    ID               = 1
    Activity         = "Currently backing up: ""Job description for the above job name"""
    Status           = "Percent Completed: 48.5%      File Size: 3.78 GB     Processing file: Game file.exe"
    PercentComplete  = .485
    CurrentOperation = "Copied: 188 / 256     Files Left: 66"
}

Assert-Progress -OverallProgressParams $OverallProgressParameters -CurrentProgressParams $JobProgressParameters

.NOTES

#>
function Assert-Progress {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, Position = 0)] [Hashtable] $OverallProgressParams,
        [Parameter(Mandatory, Position = 1)] [Hashtable] $CurrentProgressParams
    )
    
    # this uses splatting to pass parameters to the Write-Progress cmdlet https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_splatting?view=powershell-5.1
    Write-Progress @OverallProgressParams
    Write-Progress @CurrentProgressParams
}
