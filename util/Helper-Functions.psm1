# This will prevent the script from running unless the user is running the script in at least powershell version 7.4 (this is because of the -CaseInsensitive flag for "Select-Object -Unique -CaseInsensitive") https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_requires?view=powershell-7.3#-version-nn
#Requires -Version 7.4

# Only put in the functions that are completed in this file because the Write-Verbose command will not be executed unless you uncomment out the below line
# $VerbosePreference = "Continue"

#region variables
<# Strings you can test for the root drive regex
Valid options (you can include an extra '\' at the end of the path, it is accpeted):
A:\Steam\steamapps\common
b:\my games\Steam\Common folder
C:\Steam\steamapps
d:\my games\Steam\Detection files\Games
E:\Steam\steamapps\workshop\content
f:\my games\Steam\Workshop content
G:\Steam\steamapps\workshop
h:\my games\Steam\Detection files\Workshop items
\\255.255.255.255\Network share
\\10.0.0.124\IPV4_network_share\SubFolder
\\Workstation\Another_network_share
\\ValidLongComput\LongComputerEntry\Sub_name

Invalid options (remove everything after the "#' and the previous space for testing the strings.  They simply explain why they are wrong"):
Bad LongComputerEntry # not a path
D\folder name # missing a ":" after D
DF:\Folder # Extra letter for drive letter
\\255.255.255.256\VM_Shared # Invalid IPV4 format
\\10.25.149.86\ # Missing a folder for a network connection
\\InvalidLongCompu\Folder # Computer name is greater than 15 characters (16 in this option)

Strings you can test against for getting full paths:
Valid options (use any of the above options in the first set of items)
Invalid options
G:\Steam\steamapps\workshop\G:\Steam\steamapps\workshop  # A ":" inside a folder name
C:\\Workstation\Another_network_share # Combination of a local and remote connection
\\Workstation\Another_network_share\C: # Another combination of a local and remote connection
#>

<# My understanding on how the IPV4 regex works:
# 25[0-5] searches for 250-255
# (2[0-4]|1\d|[1-9]|) searches for 20-24|10-19|1-9|(Zero-Length match).  This is immediately followed by \d which searches for 0-9, so it results in the range 0-249
# \.? searches for a literal period 0 or 1 time
# \b searches for a word boundary (in this instance it looks for last character in the string, if the last character is a word character [a-zA-Z0-9_])
# {4} says that the previous conditions have to repeat 4 times
#>

$IPV4Regex = "((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)\.?\b){4}" # Source for this found here https://stackoverflow.com/questions/5284147/validating-ipv4-addresses-with-regexp
# The below two variables are seperated out so we can use the folder name varaible in multiple places.  Combined Regex command found here https://learn.microsoft.com/en-us/answers/questions/862484/regex-to-validate-a-valid-windows-folder-directory
$localDriveRegex = "[a-zA-Z]:\\"  # Looks for "A-Z:\" captible insensitive.  The '\' is required because otherwise, it uses the current directory where the script file is located as the source/destination
$folderNameRegex = "(?:[\w -]+\\?)"  # Looks for the name of a folder with or without a '\' at the end
$remoteDriveRegex = "\\\\($IPV4Regex|[\w -]{1,15})\\$folderNameRegex" # Looks for "\\IPV4Address\FolderName" or "\\Computer_name_max_15_characters\FolderName"
$rootDirectoryRegex = "^($localDriveRegex|$remoteDriveRegex){1}"  # Looks for either a local drive or a remote drive, but not both https://stackoverflow.com/questions/247167/exclusive-or-in-regular-expression
$fullPathRegex = "($rootDirectoryRegex)$folderNameRegex*$" # Looks for either the full path to a local or remote folder

$quitAnswer = @('Q', 'q')
#endregion

<#
.SYNOPSIS
    Gets the number of thread on your system.
.DESCRIPTION
    Grabs the nubmer of threads on your CPU by grabbing the information from your environment varaibles.
.EXAMPLE
    $maxThreadCount = Get-SystemThreadCount
.NOTES
    Source for where I learned this https://stackoverflow.com/questions/69868053/how-can-i-get-the-number-of-cpu-cores-in-powershell
#>
function Get-SystemThreadCount {
    return [System.Environment]::ProcessorCount
}

<#
.SYNOPSIS
    A function that grabs all of the available csv file (Jobs) from the "Jobs" folder.
.DESCRIPTION
    This function will grab all the jobs/csv files from the "Jobs" folder so the user knows what jobs are available to them.
.EXAMPLE
    $availableJobs = Get-JobsFromJobFolder
.NOTES
    Returns an array of PSCustomObjects containing three properties.
    The name of the job "JobName", the operation of the job "JobOperation" (set to null as a default), and the contents of the file as a list of PSCustomObjects "JobContent" (this content is extracted by using the function "Get-JobContent").
#>
function Get-JobsFromJobFolder {
    # Get a list of possible jobs from the "Jobs" folder
    Write-Host "Discovering all the jobs inside the `"Jobs`" folder..."
    # The below variable "Jobs" is an array of PSCustomObjects
    $jobs = Get-ChildItem ./Jobs -Filter *.csv | ForEach-Object {
        Write-Verbose "Job file discovered: $($_.Name)"
        [PSCustomObject]@{
            JobName      = $_.BaseName
            JobOperation = $null
            JobContent   = Get-JobContent $_.Name
        }
    }

    Write-Verbose "Data type of jobs: $($jobs.GetType())"

    $jobs | Sort-Object JobName # Sort the Jobs by their names

    return  # We don't have to add "return $Jobs" because the above command returns the object back to the calling function because of this reason https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_return?view=powershell-7.3#examples
}

<#
.SYNOPSIS
    Grab the contents of the CSV file.
.DESCRIPTION
    This will grab the contents of the CSV file specfied from the "Jobs" folder.
.PARAMETER csvFileName
    The name of the CSV file with it's extention included.
.EXAMPLE
    $csvContent = Get-JobContent "file.csv"
.NOTES
    If something happens when it is attempting to import the CSV file and it is unable to import it, this function will terminate the script.
    This function also contains the nessary logic to make sure that each combination of "Source" and "Destination" paths are unique and propertly formatted.  If there are errors, such a copy of the Source and Destination paths or a incorrectly formatted source/destination path, it will then display an error message saying what the issue is and on what line of the file it is found on.  It will then ask the user to fix the issues and then it will then re-evaulate the contents of the file or they can quit the script.
#>
function Get-JobContent {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string] $csvFileName
    )

    Write-Verbose "Argument supplied for `"Get-JobContent`": $csvFileName"

    do {
        Write-Verbose "Attempting to process the file: `"$csvFileName`""
        #Attempt to import the csv file so that the script can read it (returns an array of objects)
        try {
            $csvImported = Import-Csv "./Jobs/$csvFileName" -Delimiter ','
        }
        #Something happened and script is unable to import the file
        catch {
            # the "$_" is the current item/error generated
            Write-Host "The following error occured while opening the CSV file `"$csvFileName`":
            `r$_
            `r
            `rTerminating the script..."
            Exit-ScriptDeployment
        }
    
        #region Process the imported csv file
        $uniqeSDComboArray = [System.Collections.Generic.List[PSCustomObject]]::new() # This list is used to detect if a Source->Destination combiantion has been previsouly used in the csv file
        $jobContents = [System.Collections.Generic.List[PSCustomObject]]::new() # This will store the contents of the file to be returned once it has finished processing each line in the csv file
        $errorList = [System.Collections.Generic.List[string]]::new()
        $lineNumber = 2 # Starting at line #2 because line #1 contains the headers for the columns inside the file
    
        foreach ($line in $csvImported) {
            Write-Verbose "`tProcessing line #$($lineNumber): $line"
            $lineChecked = Assert-CsvLineValid $line $lineNumber
            if ($lineChecked.Valid) {
                $jobContents.Add($line)
                $uniqeSDComboArray.Add($line.Source + $line.Destination)
            }
            else {
                $errorList.Add($lineChecked.ErrorMessage)
            }
            
            $lineNumber++
        }
        #endregion
        
        $errorsDetected = $errorList.Count -gt 0
        if ($errorsDetected) {
            # Clear-Host
            Write-Verbose "Contents of errorList: $($errorList -join ", ")"
            Write-Host "The below errors were detected in the file `"$csvFileName`".
            `rPlease fix the issues and press ENTER to re-validate the file.`n"

            $errorList | ForEach-Object {
                Write-Host $_
            }

            $userInput = Read-Host "`nPress ENTER to re-validate or 'Q'uit"
        }
        # Continue to loop until there is no errors detected or the user quits the script
    } while ($errorsDetected -xor $userInput -in $quitAnswer)

    Write-Verbose "Exit reason:
    `rerrors detected: $errorsDetected
    `r-xor
    `ruser quiting: $($userInput -in $quitAnswer)"

    if ($userInput -in $quitAnswer) {
        Exit-ScriptDeployment
    }

    Write-Verbose "Data from CSV file being returned:$($jobContents | Format-Table | Out-String)"
    return $jobContents
}

<#
.SYNOPSIS
    Validates the line inside a CSV file for a job.
.DESCRIPTION
    This function makes sure that the line imported from the CSV job file is correctly formatted for the "Source" and "Destination" fields.
.PARAMETER line
    The line (which is a PSCustomObject) of the CSV file you wish to process containing at least the headers/properties "Source" and "Destination".
.PARAMETER lineNumber
    The line number for where this line is found.
.EXAMPLE
    $line = [PSCustomObject]@{
        Source	= "D:\Folder1"
        Destination = "C:\Folder2"
    }
    $lineNumber = 2

    $results = Assert-CsvLineValid $line $lineNumber
.NOTES
    This returns a hashtable with two properties "Valid" (telling you if the line is valid) and "ErrorMessage" (contains the error message to be displayed to the user when the line is not valid).
#>
function Assert-CsvLineValid {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)] [pscustomobject] $line,
        [Parameter(Mandatory, Position = 1)] [Int16] $lineNumber
    )

    Write-Verbose "Argument supplied for `"Assert-CSVpathValid`":
    `r`tline: $line
    `r`tlineNumber: $lineNumber"

    $returnHashtable = @{ Valid = $true; ErrorMessage = "" }
    
    $source = $line.Source
    $destination = $line.Destination

    # If we never enter into any of the below if/else conditions, then nothing is incorrect with the line
    # Make sure that either of the paths are not left empty
    $sourceNotSupplied = [string]::IsNullOrEmpty($source)
    $destinationNotSupplied = [string]::IsNullOrEmpty($destination)
    Write-Verbose "if ($sourceNotSupplied -or $destinationNotSupplied)"
    $sourceNotValid = $source -notmatch $fullPathRegex
    $destinationNotValid = $destination -notmatch $fullPathRegex
    Write-Verbose "elseif ($sourceNotValid -or $destinationNotValid)"
    $sourceDestinationUsedBefore = $source + $destination -in $uniqeSDComboArray
    $destinationSourceUsedBefore = $destination + $source -in $uniqeSDComboArray
    Write-Verbose "elseif ($sourceDestinationUsedBefore -or $destinationSourceUsedBefore)"

    # Make sure that the source and desination fields are supplied
    if ($sourceNotSupplied -or $destinationNotSupplied) {
        $errorMessage = "Error on line #$($lineNumber): The "
        if ($sourceNotSupplied -and $destinationNotSupplied) {
            $errorMessage += "`"Source`" and `"Destination`" fields are required, however they are"
        }
        elseif ($sourceNotSupplied) {
            $errorMessage += "`"Source`" field is required, however it is"
        }
        else {
            $errorMessage += "`"Destination`" field is required, however it is"
        }
        $errorMessage += " not supplied"
        Write-Verbose "Contents of errorMessage: $errorMessage"
        $returnHashtable.Valid = $false
        $returnHashtable.ErrorMessage = $errorMessage
    }
    # Make sure that either of the paths are paths using a regex command
    elseif ($sourceNotValid -or $destinationNotValid) {
        $errorMessage = "Error on line #$($lineNumber): The "
        if ($sourceNotValid -and $destinationNotValid) {
            $errorMessage += "`"Source`" and `"Destination`" fields are"
        }
        elseif ($sourceNotValid) {
            $errorMessage += "`"Source`" field is"
        }
        else {
            $errorMessage += "`"Destination`" field is"
        }
        $errorMessage += " incorrectly formatted"
        Write-Verbose "Contents of errorMessage: $errorMessage"
        $returnHashtable.Valid = $false
        $returnHashtable.ErrorMessage = $errorMessage
    }
    # Make sure this combination of Source/Destiantion fields has not been used before for either the same source -> destination or it's inverse destination -> source
    elseif ($sourceDestinationUsedBefore -or $destinationSourceUsedBefore) {
        $errorMessage = "Error on line #$($lineNumber): This combination of the `"Source`" and `"Destination`" fields has already been used before"
        if ($destinationSourceUsedBefore) {
            $errorMessage += ", but in each other's fields"
        }
        Write-Verbose "Contents of errorMessage: $errorMessage"
        $returnHashtable.Valid = $false
        $returnHashtable.ErrorMessage = $errorMessage
    }

    return $returnHashtable
}

<#
.SYNOPSIS
    A function that gets a unique list of required root drives/network connections.
.DESCRIPTION
    This function will take an array of PSCustomObjects with the properties "Source" and "Destiation" and will extract the root drive.  This can be either a local drive such as C, D, E, F, ect. or a remote drive such as "\\125.45.13.148\Folder" or "\\ComputerName12\Folder2".
.PARAMETER sourceDestinations
    An array of PSCustomObjects of the style below containing two properties "Source" and "Destination".
.EXAMPLE
    $pathsToCheck = @(
        @{Source="C:\Users"; Destination="D:\Users"},
        @{Source="C:\Data"; Destination="E:\Data"},
        @{Source="C:\Test"; Destination="F:\Test"},
        @{Source="G:\five"; Destination="H:\five"},
        @{Source="\\10.0.0.3\Network"; Destination="I:\file"},
        @{Source="J:\tow"; Destination="\\PCName\Share"}
    )

    $requiredDrives = Get-RequiredDrives $pathsToCheck
.NOTES
    This will then return a single hashtable with two properties "Local" and "Remote" both of which are UNIQUE sorted lists of root drives.
#>
function Get-RequiredDrives {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [array] $sourceDestinations
    )

    Write-Verbose "Argument supplied for `"Get-RequiredDrives`": $($sourceDestinations | Format-Table | Out-String)"

    # We have as a set of lists instead of arrays "@()" because it is faster to add items to it using the .Add() method instead of the += https://theposhwolf.com/howtos/PS-Plus-Equals-Dangers/
    $returnHashtable = @{
        Local  = [System.Collections.Generic.List[string]]::new()
        Remote = [System.Collections.Generic.List[string]]::new()
    }

    # the "$null = " is added so that it doesn't output any additional information that this function might output
    # For every entry inside the property "JobContent" of the variable "sourceDestinations"
    $null = $sourceDestinations | ForEach-Object {
        Write-Verbose "Current object processing for required drives: $_"
        
        # In the below if statments, We replace ":\" with '' so we only get the local drive letter
        # Process the source drive
        $match = Get-RootDrivePath $_.Source
        $match -match $localDriveRegex ? $returnHashtable.Local.Add((Remove-DriveExtraText $match)) : $returnHashtable.Remote.Add($match)

        # Process the destination drive
        $match = Get-RootDrivePath $_.Destination
        $match -match $localDriveRegex ? $returnHashtable.Local.Add((Remove-DriveExtraText $match)) : $returnHashtable.Remote.Add($match)
    }

    # Simplifly each entry inside the hashtable so we only have unique entries (that are case insensitive)
    $returnHashtable.Local = $returnHashtable.Local | Sort-Object | Get-Unique -CaseInsensitive
    $returnHashtable.Remote = $returnHashtable.Remote | Sort-Object | Get-Unique -CaseInsensitive

    Write-Verbose "Data being returned: $($returnHashtable | Format-Table | Out-String)"

    return $returnHashtable
}

<#
.SYNOPSIS
    A function that compresses a list of paths into a set of unique root drives/network connections
.DESCRIPTION
    This function will take an array of PSCustomObjects with the properties "JobName", "JobOperation", and "JobContent" (which itself contains at a minimum the propterties "Source" and "Destination") and will go through each item and will compress either the Source or Destination side into an array so they are easy to read.
.PARAMETER dataToProcess
    An array of PSCustomObjects with the properties "JobName", "JobOperation", and "JobContent" (which itself is an array of PSCustomObjects with at minimum the properties "Source" and "Destination")
.EXAMPLE
    # The below varaible will result in the Destination side to be compressed 
    $dataToBeProcessed = @(
        [PSCustomObject]@{
            JobName = "Name of Job"
            JobOperation = "backup"
            JobContent = @(
                [PSCustomObject]@{
                    Source = "C:\Folder1"
                    Destination = "C:\Folder2"
                },
                [PSCustomObject]@{
                    Source = "C:\Folder3"
                    Destination = "\\10.0.0.4\Folder4"
                }
            )
        }
    )

    $returned = Compress-RootDriveToFrom $dataToBeProcessed
.NOTES
    This will return a list of PSCustomObjects containing four properties.
    The name of the job "JobName", the operation of the job "JobOperation", a boolean representing whether the destination was compressed "DestinationCompressed", and a list of PSCustomObjects containing the following properties "Source" or "Sources" and "Destination" or "Destinations" depending on if the source or destination was compressed "CompressedToFromRoots"
#>
function Compress-RootDriveToFrom {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [array] $dataToProcess
    )

    Write-Verbose "Argument supplied for `"Compress-RootDriveToFrom`": $($dataToProcess | Format-Table | Out-String)"

    $returnList = [System.Collections.Generic.List[PSCustomObject]]::new()  # Will contain a list of PSCustomObjects of the style defined below depending on if we are compressing the source or destination side
    <#
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
    #>

    $dataToProcess | ForEach-Object {
        Write-Verbose "Current object processing for commpressing root drives: $($_ | Format-Table | Out-String)"

        #region preprocessing to determine if we are going to compress the source or destination side of the data
        # Extract all the root drives from the "JobContent" property
        $rootDrives = $_.JobContent | ForEach-Object {
            Write-Verbose "`tChecking the entry: $($_ | Select-Object Source, Destination)"

            $sRoot = Remove-DriveExtraText (Get-RootDrivePath $_.Source)
            $dRoot = Remove-DriveExtraText (Get-RootDrivePath $_.Destination)
            [PSCustomObject]@{
                SourceRoot      = $sRoot
                DestinationRoot = $dRoot
            }
        } | Sort-Object SourceRoot, DestinationRoot

        Write-Verbose "Contents of rootDrives: $($rootDrives | Format-Table | Out-String)"

        # If the number of UNIQUE source drives is less than the number of UNIQUE destination drives (both case insensitive), then we will compress the destination side into an array, otherwise it will compress the source side into an array
        # For Example instead of getting the first item below, we get the second that is easier to read:
        # 1. # of UNIQUE source drives IS less than the # of UNIQUE destination drives
        #   (C->X, C->Y, C->Z) we would get (C -> X, Y, Z) (Compress Destination)
        # 2. # of UNIQUE source drives IS NOT less than the # of UNIQUE destination drives
        #   (X->C, Y->C, Z->C) we would get (X, Y, Z -> C) (Compress Source)
        $sourceDriveCount = $rootDrives.SourceRoot | Select-Object -Unique -CaseInsensitive | Measure-Object | Select-Object -ExpandProperty Count
        $destinationDriveCount = $rootDrives.DestinationRoot | Select-Object -Unique -CaseInsensitive | Measure-Object | Select-Object -ExpandProperty Count
        $compressDestination = $destinationDriveCount -ge $sourceDriveCount ? $true : $false

        Write-Verbose "Unique destination drives `"$destinationDriveCount`" -ge Unique source drives `"$sourceDriveCount`": $($compressDestination)"
        #endregion

        $itemToBeAddedToList = [PSCustomObject]@{
            JobName               = $_.JobName
            JobOperation          = $_.JobOperation
            DestinationCompressed = $compressDestination
            CompressedToFromRoots = [System.Collections.Generic.List[PSCustomObject]]::new()
        }

        #region compress the root drives into their most readable state
        # The "Select-Object SourceRoot, DestinationRoot -Unique -CaseInsensitive" will select all unique combinations (case insensitive) of the two properties "SourceRoot" and "DestinationRoot"
        $rootDrives | Select-Object SourceRoot, DestinationRoot -Unique -CaseInsensitive | ForEach-Object {
            $sourceDrive = $_.SourceRoot
            $destinationDrive = $_.DestinationRoot
            Write-Verbose "Processing sourceDrive: $sourceDrive and destinationDrive: $destinationDrive"

            # See about simplfilying the below code so instead of two if/else statments, we have one combined section (might not be recommended because we are adding in 4 different ways (2 for new entries and 2 for appending to currenlty existing entries))
            # We are compressing the destination drives
            if ($compressDestination) {
                # A new source drive as been detected
                if ($sourceDrive -notin $itemToBeAddedToList.CompressedToFromRoots.Source) {
                    $dataToBeAdded = [PSCustomObject]@{
                        Source       = $sourceDrive
                        Destinations = [System.Collections.Generic.List[string]]@($destinationDrive)
                    }

                    Write-Verbose "Creating new entry: $($dataToBeAdded | Format-Table | Out-String)"
                    $itemToBeAddedToList.CompressedToFromRoots.Add($dataToBeAdded)
                }
                # Append the new destination drive for the current source drive
                else {
                    $listItemReference = $itemToBeAddedToList.CompressedToFromRoots | Where-Object Source -eq $sourceDrive
                    $listItemReference.Destinations.Add($destinationDrive)
                    Write-Verbose "Appended `"$destinationDrive`" to Destinations: $($listItemReference | Format-Table | Out-String)"
                }
            }
            # We are compressing the source drives
            elseif (-not $DDriveCompress) {
                # A new destination drive detected
                if ($destinationDrive -notin $itemToBeAddedToList.CompressedToFromRoots.Destination) {
                    $dataToBeAdded = [PSCustomObject]@{
                        Sources     = [System.Collections.Generic.List[string]]@($sourceDrive)
                        Destination = $destinationDrive
                    }

                    Write-Verbose "Creating new entry: $($dataToBeAdded | Format-Table | Out-String)"
                    $itemToBeAddedToList.CompressedToFromRoots.Add($dataToBeAdded)
                }
                # Append the new source drive for the current destination drive
                else {
                    $listItemReference = $itemToBeAddedToList.CompressedToFromRoots | Where-Object Destination -eq $destinationDrive
                    $listItemReference.Sources.Add($sourceDrive)
                    Write-Verbose "Appended `"$sourceDrive`" to Sources: $($listItemReference | Format-Table | Out-String)"
                }
            }
        }

        $returnList.Add($itemToBeAddedToList)
        #endregion
    }

    Write-Verbose "Data being returned:
    `r`tJobName: $($returnList.JobName)
    `r`tDestinationCompressed: $($returnList.DestinationCompressed)
    `r`tCompressedToFromRoots: $($returnList.CompressedToFromRoots | Format-Table | Out-String)"

    return $returnList
}

<#
.SYNOPSIS
    A function to validate that the drives are connected and source paths exist.
.DESCRIPTION
    This function will determine if the script has access to all the required drives and the source paths.
.PARAMETER dataToProcess
    An array/list of PSCustomObjects with the properties "JobName", "JobOperation", and "JobContent" (which itself is an array of PSCustomObjects with at minimum the properties "Source" and "Destination").
.EXAMPLE
    $dataToBeProcessed = @(
        [PSCustomObject]@{
            JobName = "Name of Job"
            JobOperation = "backup"
            JobContent = @(
                [PSCustomObject]@{
                    Source = "C:\Folder1\Sub folder"
                    Destination = "C:\Folder2\Sub folder"
                },
                [PSCustomObject]@{
                    Source = "C:\Folder3"
                    Destination = "\\10.0.0.4\Folder4"
                }
            )
        }
    )

    $returned = Assert-PathsValid $dataToBeProcessed
.NOTES
    This function returns a hashtable with four properties.
    A boolean repersenting that no issues were detected "AllValid", a boolean repersenting if errors occured, but they can continue with the backup "CanContinue", a list of strings for the drives, if any, that it was uanble to detect "DriveErrors", and a list of PSCustomObjects with the properties "JobName", "JobOperation", and "Source" (which is an array of string containing the source paths not detected)
#>
function Assert-PathsValid {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)] [array] $dataToProcess
    )

    Write-Verbose "Argument supplied for `"Assert-PathsValid`": $($dataToProcess | Format-Table | Out-String)"
    
    $returnHashtable = @{
        AllValid    = $true
        CanContinue = $true
        DriveErrors = [System.Collections.Generic.List[string]]::new()
        PathErrors  = [System.Collections.Generic.List[PSCustomObject]]::new() # will have PSCUstomObjects with the format as defined below
    }
    <#
        [PSCustomObjects]@{
        JobName      = "name of the job"
        JobOperation = "backup OR restore"
        Source       = [System.Collections.Generic.List[string]]@() # a list of string containing the source paths not detected
    #>

    $dataToProcess | ForEach-Object {
        Write-Verbose "Current object processing: $_"
        $jobName = $_.JobName
        $jobOperation = $_.JobOperation

        $_.JobContent | Select-Object Source, Destination -Unique | ForEach-Object {
            Write-Verbose "Current object inside JobContent checking that drives and paths are valid: $_"

            # Test the root paths
            $sRoot = Get-RootDrivePath $_.Source
            $sRootDetected = Test-Path $sRoot
            if (-not $sRootDetected) {
                Write-Verbose "Adding `"$(Remove-DriveExtraText $sRoot)`" to DriveErrors"
                $returnHashtable.DriveErrors.Add((Remove-DriveExtraText $sRoot))
                $returnHashtable.AllValid = $false
                $returnHashtable.CanContinue = $false
            }
            $dRoot = Get-RootDrivePath $_.Destination
            $dRootDetected = Test-Path $dRoot
            if (-not $dRootDetected) {
                Write-Verbose "Adding `"$(Remove-DriveExtraText $dRoot)`" to DriveErrors"
                $returnHashtable.DriveErrors.Add((Remove-DriveExtraText $dRoot))
                $returnHashtable.AllValid = $false
                $returnHashtable.CanContinue = $false
            }
    
            # Test the full path for the sources
            $sPathDetected = Test-Path $_.Source
            if ($sRootDetected -and -not $sPathDetected) {
                Write-Verbose "Adding `"$($_.Source)`" to PathErrors because it doesn't exist"
                Write-Verbose "Before adding:$($returnHashtable.PathErrors | Format-Table | Out-String)"
                $objectReference = $returnHashtable.PathErrors | Where-Object JobName -eq $jobName
                if ($objectReference) {
                    Write-Verbose "Appending to an existing object"
                    $objectReference.Source.Add($_.Source)
                }
                else {
                    Write-Verbose "Adding a new object"
                    $returnHashtable.PathErrors.Add(
                        [PSCustomObject]@{
                            JobName      = $jobName
                            JobOperation = $jobOperation
                            Source       = [System.Collections.Generic.List[string]]@($_.Source)
                        }
                    )
                }
                Write-Verbose "After adding:$($returnHashtable.PathErrors | Format-Table | Out-String)"
                $returnHashtable.AllValid = $false
            }
            Write-Verbose "Results of processing the above object for the source and destinations:
            `r`tsRootDetected: $sRootDetected
            `r`tdRootDetected: $dRootDetected
            `r`tsPathDetected: $sPathDetected"
        }
    }

    # Get a unique sorted list of Drives that caused issues
    $returnHashtable.DriveErrors = $returnHashtable.DriveErrors | Sort-Object | Select-Object -Unique

    Write-Verbose "Data being returned:
    `r`tAllValid: $($returnHashtable.AllValid)
    `r`tCanContinue: $($returnHashtable.CanContinue)
    `r`tDriveErrors: $($returnHashtable.DriveErrors.Count -ge 1 ? $returnHashtable.DriveErrors -join ", " : "None")
    `r`tPathErrors: $($returnHashtable.PathErrors.Count -ge 1 ? {$returnHashtable.PathErrors | Format-Table | Out-String} : "None")"

    return $returnHashtable
}

<#
.SYNOPSIS
    A function to get the root drive of a local or remote path.
.DESCRIPTION
    Using a Regex match condition, it will extract the root drive for either a local "C:\" or remote "\\<IPV4 OR pc name>\Folder" from the full path.
.PARAMETER path
    The full path to a folder or file.
.EXAMPLE
    $rootPath = Get-RootDrivePath "C:\folder1\folder2".
.EXAMPLE
    $rootPath = Get-RootDrivePath "\\145.571.27.6\NetworkShare\Sub folder".
.EXAMPLE
    $rootPath = Get-RootDrivePath "\\LongComputerNam\VM_Shared\Windows_Share".
.NOTES
    If it fails to find a root path, it will return false.
#>
function Get-RootDrivePath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)] [string] $path
    )

    Write-Verbose "Argument supplied for `"Get-RootDrivePath`": $path"

    if ($path -match $rootDirectoryRegex) {
        $returnData = $matches[0]
    }

    Write-Verbose "Returning: $returnData"
    return $returnData
}

<#
.SYNOPSIS
    A function to remove any ":\" from a root drive and if it is a local drive, it will capilizes the drive letter.
.DESCRIPTION
    This function will remove extra text not required for the user to read the drives such as ":\".  If the drive is a local drive, it will captilized the drive letter.
.PARAMETER rootDrivePath
    The root path to a network share or a local drive.  This information can be extracted by using the function "Get-RootDrivePath".
.EXAMPLE
    $modifiedRootDrive = Remove-DriveExtraText "C:\"
.Example
    # Does nothing to the results but it is accepted
    $modifiedRootDrive = Remove-DriveExtraText "\\10.0.0.1\NetworkShare"
.NOTES
    It is up to the user to get the root path, this function simply removes ":\" from the argument supplied.
#>
function Remove-DriveExtraText {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)] [string] $rootDrivePath
    )

    Write-Verbose "Argument supplied for `"Remove-DriveExtraText`": $rootDrivePath"

    # if it matches the local drive regex
    if ($rootDrivePath -match $localDriveRegex) {
        $returnString = $matches[0].replace(":\", '').ToUpper()
    }
    # if it matches the remote drive regex
    elseif ($rootDrivePath -match $remoteDriveRegex) {
        $returnString = $matches[0]
    }

    Write-Verbose "Returning: $returnString"
    return $returnString
}

<#
.SYNOPSIS
    A new like operator that allows for multiple like conditions in one easy to use function.
.DESCRIPTION
    This function will take two arguments, "fileName" and "validFileTypes", and it will then determine if the file matches at least one of the file types supplied.
.PARAMETER FileName
    The name of the file you wish to check.
.PARAMETER ValidFileTypes
    An array of valid like operators that says the file should be selected.
.EXAMPLE
    Compare-FileMatch 'This is a new file.txt' @(This*, *new*, *.txt)
.NOTES
    Source for this function but modified how arguments are supplied https://stackoverflow.com/a/13019721
#>
function Compare-FileMatch {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, Position = 0)] [string] $fileName,
        [Parameter(Mandatory, Position = 1)] [array] $validFileTypes
    )
    Write-Verbose "Arguments supplied for `"Compare-FileMatch`":
    FileName: $fileName
    ValideFileTypes: $($validFileTypes -join ", ")"
    
    # We don't have to inclose the pattern variable inside a set of "" inside the below if statment, they are not required when they are contains inside a variable.  They are only required if you manauly use the like comparison operator inside a terminal in raw text.
    foreach ($pattern in $validFileTypes) { if ($fileName -like $pattern) { return $true; } }
    return $false;
}

<#
.SYNOPSIS
    A function to count the number of unique files inside the source and destination paths for the selected jobs
.DESCRIPTION
    This function will count the number of UNIQUE files inside both the source and destination fields for the jobs.  This function will in addition add a new property "EntryFileCount" to the parameter supplied.  So it is required that you pass the entire object to this function instead of selecting only the properties it needs because otherwise the new property will not be added to the argument supplied after this function is done being executed
.PARAMETER dataToProcess
    An array of PSCustomObjects with the following properties "Source", "Destination", and "FileMatching".  This function requires that you pass the entire object to this function and not just the required fields.  This is because if you don't, it will add the property "EntryFileCount" to a copy of the data instead of to the reference of the data, thus you lose the information when you leave this function.
.EXAMPLE
    $dataToBeProcessed = @(
        [PSCustomObject]@{Source = "C:\Folder1"; Destination = "C:\Folder2"; FileMatching = "*.exe"},
        [PSCustomObject]@{Source = "C:\Folder3"; Destination = "D:\Folder1"; FileMatching = ""},
        [PSCustomObject]@{Source = "D:\documents"; Destination = "F:\documents"; FileMatching = "*.pdf\*.docx\*.doc"},
        [PSCustomObject]@{Source = "\\10.0.0.45\NetworkShare"; Destination = "\\ComputerName\NetworkFolder"; FileMatching = ""}
    )

    $totalFileCount = Get-TotalFileCount $dataToBeProcessed
.NOTES
    (WIP) I am most likely going to use Start-ThreadJob here as documented here for counting the files.  However when I attempted to do so before I couldn't get the jobs to return the number of files, it always returned 7 for some reason.
    https://learn.microsoft.com/en-us/powershell/module/threadjob/start-threadjob?view=powershell-7.3
    https://www.saggiehaim.net/background-jobs-start-threadjob-vs-start-job/
    https://www.youtube.com/watch?v=8xqrdk5sYyE&ab_channel=MrAutomation
#>
function Get-TotalFileCount {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)] [array] $dataToProcess
    )

    Write-Verbose "Argument supplied for `"Get-TotalFileCount`": $($dataToProcess | Format-Table | Out-String)"
    Write-Host "Determining how many files are to be processed..."

    $totalFileCount = 0
    $getOnlyFiles = { ($_.GetType().Name -eq "FileInfo") -and ($_.Mode -notmatch 'l') }  # This contains the logic for filtering for the Where-Object so we only have one copy of it.  To use this we simply say "Where-Object { & $GetOnlyFils }"  https://stackoverflow.com/questions/49071951/powershell-cast-conditional-statement-to-a-variable

    $dataToProcess | ForEach-Object {
        #region local variables used below
        # The below two variables are used for conting the number of unique files
        $inSourceAndDestination = 0;
        $inSourceXorDestination = 0;
        # The below three varaibles are used to store a friendly name to the properties so we can easly reference them inside the below Where-Object and ForEach-Object cmdlets
        $sPath = $_.Source;
        $dPath = $_.Destination
        $allowedFileTypes = $_.FileMatching -split '/'
        # If the FileMatching property is null or empty, then this will have the -Recurse flag below in the Get-ChildItem cmdlet be executed
        $useRecursion = [String]::IsNullOrEmpty($_.FileMatching)
        # Split the list of allowed file types after every '/' so we make an array of items
        $message = "Counting the number of files in the directories<1>
        `r`tSource: `"$($sPath)`"
        `r`tDestination: `"$($dPath)`""
        #endregion
        $message = $useRecursion ? $message.Replace("<1>", '') : $message.Replace("<1>", " that matches one of the following: $($allowedFileTypes -join ", ")")
        Write-Host $message

        #region Count the files in the source and destinations
        # We have the below if/else blocks around the Get-ChildItem and inside the ForEach-Object cmdlet because if the source path and/or destination paths don't exist, it will hang for 20-30 seconds attempting to check the items when it should simply skip them.  These if/else blocks will make it so it only processes the entries if it makes sense to do so, I.E. they exist.  This issue is caused by the Get-ChildeItem Cmdlet for when the supplied directory doesn't exist.
        $sPathExists = Test-Path $sPath
        $dPathExists = Test-Path $dPath

        # "-File" means only get files, "-Force" means find hidden/system files, and "-Recurse" means go through all folders
        # If the source path exists, then go through each file located inside the source directory and check to see if the files exists in the targeted destination directory
        if ($sPathExists) {
            Get-ChildItem -Path $sPath -File -Force -Recurse:$useRecursion -ErrorAction SilentlyContinue |
            Where-Object {
                if ($useRecursion) { $true } # This will return all files
                else { (& $getOnlyFiles) -and (Compare-FileMatch $_.Name $allowedFileTypes) }
            } |
            ForEach-Object {
                # If the destiantion directory exists, then check to see if the files exists in that directory
                if ($dPathExists) {
                    # The contents of $_ in here is the full path to the SOURCE file
                    Write-Verbose "Current source item checking: $_"
                    $dPathToTest = $dPath + $_.FullName.Substring($sPath.Length)
                    Write-Verbose "Contents of dPathToTest: $dPathToTest"
                    if (Test-Path $dPathToTest) { $inSourceAndDestination++ }
                    else { $inSourceXorDestination++ }
                }
                # otherwise, the directory doesn't exist so we simply add to inSourceXorDestination
                else {
                    $inSourceXorDestination++
                }
            }    
        }
        else {
            Write-Verbose "Skipping source path `"$sPath`" because it doesn't exist"
        }

        # If the source (because if the source doesn't exist, we don't have to process the destination) and destination paths exists, then we will go through each file located inside the destination directory and check to see if the file exists in the targeted source directory
        if ($sPathExists -and $dPathExists) {
            Get-ChildItem -Path $dPath -File -Force -Recurse:$useRecursion -ErrorAction SilentlyContinue |
            Where-Object {
                if ($useRecursion) { $true } # # This will return all files
                else { (& $getOnlyFiles) -and (Compare-FileMatch $_.Name $allowedFileTypes) }
            } |
            ForEach-Object {
                # The contents of $_ in here is the full path to the DESTINATION file
                Write-Verbose "Current destination item checking: $_"
                $sPathToTest = $sPath + $_.FullName.Substring($dPath.Length)
                Write-Verbose "Contents of sPathToTest: $dPathToTest"
                if (-not (Test-Path $sPathToTest)) { $inSourceXorDestination++ }
            }
        }
        else {
            Write-Verbose "Skipping destination path `"$dPath`" because it doesn't exist"
        }
        #endregion

        Write-Verbose "inSourceAndDestination: $inSourceAndDestination
        `r`tinSourceXorDestination: $inSourceXorDestination
        `r`tFiles to be processed: $($inSourceAndDestination + $inSourceXorDestination)"

        # Add a new member to the varaible "JobContent" referenced above with it's value being the total number of unique files in the source and destinations
        $_ | Add-Member -MemberType NoteProperty -Name 'EntryFileCount' -Value ($inSourceAndDestination + $inSourceXorDestination)
        
        $totalFileCount += $inSourceAndDestination + $inSourceXorDestination
    }
    
    Write-Verbose "Total number of files to be processed: $totalFileCount"

    return $totalFileCount
}

<#
.SYNOPSIS
    A function that acts as a pipe for the RoboCopy executible.
.DESCRIPTION
    This function will extract various information from the Robocopy executible and will display the information using the Write-Progress cmdlet.  This function requires you to add the following arguments to the robocopy executible /NDL, /NC, /BYTES, /NJH, and /NJS for this function to work as intended.
.PARAMETER inputObject
    This parameter you don't explictly define, you simply pipe the Robocopy process into this parameter.
.PARAMETER overallProgressParameters
    A hashtable containing the parameters that will be used for the Write-Progress command to display the overall progress.
    It has to have the following properties "ID", "Activity", "Status", "PercentComplete", and "CurrentOperation"
.PARAMETER jobProgressParameters
    A hashtable containing the parameters that will be used for the Write-Progress command to display the job progress.
    It has to have the following properties "ParentID", "ID", "Activity", "Status", "PercentComplete", and "CurrentOperation"
.PARAMETER helperVariables
    A hashtable containing any extra variables that this function uses.
    It has to have the following properties "TotalFileCount", "EntryFileCount", "FilesProcessed", and "StartTime"
.EXAMPLE
    $overallProgressParameters = @{
        ID               = 0
        Activity         = "TBD" # To be either 'Generating backup for the job "JobName"' OR 'Restoring files for the job "JobName"'
        Status           = "Percent completed: 0%     Estimated time remaining: TDB"
        PercentComplete  = 0
        CurrentOperation = "Files copied: 0 / TBD     Files left: TBD"
    }
    $jobProgressParameters = @{
        ParentID         = 0
        ID               = 1
        Activity         = "TBD" # To be either 'Currently backing up: "JobDescription"' OR 'Currently restoring: "JobDescription"'
        Status           = "Percent completed: 0%      File size: TBD     Processing file: TBD"
        PercentComplete  = 0
        CurrentOperation = "Copied: 0 / TBD     Files Left: TBD"
    }
    $helperVariables = @{
        "TotalFileCount" = The total number of UNQUIE files for every source -> destination argument for the Robocopy executible.
        "EntryFileCount" = $null # The total number UNIQUE files for the current source destination argument.
        "FilesProcessed" = -1 # We set it to -1 because inside the function "Get-RobocopyProgress", it will auto increment it by one when it gets to the first file.  If it was 0, when it would start processing the first one, it would result in it saying that the file has been processed when it has not yet been processed.
        "StartTime"      = Get-Date
    }

    Robocopy.exe "C:\" "D:\" /NDL /NC /BYTES /NJH /NJS | Get-RobocopyProgress $overallProgressParameters $jobProgressParameters $helperVariables
.NOTES
    Source for this function was found here with some additional code added for my use case https://www.reddit.com/r/PowerShell/comments/p4l4fm/better_way_of_robocopy_writeprogress/h97skef/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button
#>
function Get-RobocopyProgress {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, ValueFromPipeline)] $inputObject,
        [Parameter(Mandatory, Position = 0)] [hashtable] $overallProgressParameters,
        [Parameter(Mandatory, Position = 1)] [hashtable] $jobProgressParameters,
        [Parameter(Mandatory, Position = 2)] [hashtable] $helperVariables
    )

    begin {
        Write-Verbose "Got inside `"Get-RobocopyProgress`" pipe"
        #region Overall progress variables
        [double]$overallCopyPercent = 0
        [double]$overallFilesLeft = $helperVariables.TotalFileCount - $helperVariables.FilesProcessed - 1
        #endregion
        #region Job progress variables
        [string]$fileName = $null # To be set inside the progress{} block
        [double]$fileCopyPercent = 0
        [double]$fileSize = $Null
        [double]$jobFilesLeft = $helperVariables.EntryFileCount
        [double]$jobFilesCopied = 0
        #endregion
    }

    process {
        Write-Verbose "Now inside progress of `"Get-RobocopyProgress`" pipe"
        #region Robocopy data parsing
        $data = $inputObject -split '\x09'  #the \x09 is the ASCII code for "Tab" Source https://buckwoody.wordpress.com/2017/01/18/data-wrangling-regular-expressions/

        # A new file is being copied, so get the name of file being copied and increment/de-increment the counting variables
        If (-not [String]::IsNullOrEmpty("$($data[4])")) {
            Write-Verbose "Grabbing name of file inside `"Get-RobocopyProgress`" pipe"
            $fileName = $data[4] -replace '.+\\(?=(?:.(?!\\))+$)' # This Regex search command removes the folder path to the file and only grabs the file's name from it
            $helperVariables.FilesProcessed++
            $jobFilesLeft--
            $jobFilesCopied++
            $overallFilesLeft--
        }
        # Get the file's copy percent
        If (-not [String]::IsNullOrEmpty("$($data[0])")) {
            Write-Verbose "Grabbing name of file copy percent inside `"Get-RobocopyProgress`" pipe"
            $fileCopyPercent = ($data[0] -replace '%') -replace '\s'  # issue with this line because it occasionally receives a string and not a number?
        }
        # Get the file's size
        If (-not [String]::IsNullOrEmpty("$($data[3])")) {
            Write-Verbose "Grabbing name of file size inside `"Get-RobocopyProgress`" pipe"
            $fileSize = $data[3]  #issue with this line because it occasionally receives an empty string?
        }
        # Convert the double file size to it't most readable format
        Write-Verbose "Converting the file size to most readable format inside `"Get-RobocopyProgress`" pipe"
        [string]$fileSizeString = switch ($fileSize) {
            { $_ -gt 1TB -and $_ -lt 1024TB } {
                "$("{0:n2}" -f ($fileSize / 1TB) + " TB")"
            }
            { $_ -gt 1GB -and $_ -lt 1024GB } {
                "$("{0:n2}" -f ($fileSize / 1GB) + " GB")"
            }
            { $_ -gt 1MB -and $_ -lt 1024MB } {
                "$("{0:n2}" -f ($fileSize / 1MB) + " MB")"
            }
            { $_ -ge 1KB -and $_ -lt 1024KB } {
                "$("{0:n2}" -f ($fileSize / 1KB) + " KB")"
            }
            { $_ -lt 1KB } {
                "$fileSize B"
            }
        }
        #endregion

        #region Progress calculations
        Write-Verbose "Performing progress calculations inside `"Get-RobocopyProgress`" pipe"
        #region extract variables out of $helperVaraibles for the below code block
        $totalFileCount = $helperVariables.TotalFileCount
        $entryFileCount = $helperVariables.EntryFileCount
        $filesProcessed = $helperVariables.FilesProcessed
        $startTime = $helperVariables.StartTime
        #endregion

        $overallCopyPercent = if ($filesProcessed -gt 0) { (($filesProcessed / $totalFileCount) * 100).ToString("###.##") } else { 0 }
        $timeToCompletion = Get-TimeRemaining $startTime $overallCopyPercent

        $overallProgressParameters.Status = "Percent completed: $overallCopyPercent%     Estimated time remaining: $timeToCompletion"
        $overallProgressParameters.PercentComplete = $overallCopyPercent -le 100 ? $overallCopyPercent : 100 
        $overallProgressParameters.CurrentOperation = "Files copied: $($filesProcessed.ToString('N0')) / $($totalFileCount.ToString('N0'))     Files left: $($overallFilesLeft.ToString('N0'))"
        
        $jobProgressParameters.Status = "Percent completed: $fileCopyPercent%      File size: $([string]::Format('{0:N0}', $fileSizeString))     Processing file: $fileName"
        $jobProgressParameters.PercentComplete = $fileCopyPercent
        $jobProgressParameters.CurrentOperation = "Copied: $(($jobFilesCopied - 1).ToString('N0')) / $($entryFileCount.toString('N0'))     Files Left: $($($jobFilesLeft).ToString('N0'))"
        Write-Verbose "Finished performing progress calculations inside `"Get-RobocopyProgress`" pipe"
        #endregion

        Assert-Progress $overallProgressParameters $jobProgressParameters
    }
}

<#
.SYNOPSIS
    A function to return the estimated time remaining.
.DESCRIPTION
    This function uses the start time and the progress percentage to estimate the time remaining for the jobs to be completed.
.PARAMETER startTime
    The time at which the processing of the jobs has started.
.PARAMETER progressPercent
    The overall percentage of the total number of files processed.
.EXAMPLE
    $startTime = Get-Date
    $doublePercentage = [double]54.653

    $timeRemaining = Get-TimeRemaining $startTime $doublePercentage
.NOTES
    This function works, however it is only consistant if the time spent copying each file is about the same (which is is rarly the case).  Idealy we would use the copy rate of the files in this function, however I don't know if robocopy exposes the copy rate for the files, so this is the best option currently available.
#>
function Get-TimeRemaining {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, Position = 0)] [datetime] $startTime,
        [Parameter(Mandatory, Position = 1)] [double] $progressPercent
    )

    if ($progressPercent -gt 0) {
        $timeSpent = $(Get-Date) - $startTime
        $timeRemainingInSeconds = [Math]::Ceiling($timeSpent.TotalSeconds / $progressPercent * (100 - $progressPercent))
        <#Write-Verbose "TimeSpent: $($TimeSpent.TotalSeconds)
            `r`tprogressPercent: $progressPercent
            `r`tTimeRemainingInSeconds: $TimeRemainingInSeconds"#>
        return New-TimeSpan -Seconds $timeRemainingInSeconds #convert the variable "TimeRemainingInSeconds" to a timespan variable
    }
    else {
        return "TBD"
    }
}

<#
.SYNOPSIS
    Function to write the progress of the backup/restore, both for the overall progress and for the job progress.
.DESCRIPTION
    This will write the contents of two hashtables using Write-Progress so the programmer only has run a single command for both Write-Progress cmdlets.
.PARAMETER overallProgressParams
    A hashtable containing the parameters that will be used for the Write-Progress command to display the overall progress.
.PARAMETER jobProgressParams
    A hashtable containing the parameters that will be used for the Write-Progress command to display the job progress.
.EXAMPLE
    $overallProgressParameters = @{
        ID               = 0
        Activity         = "TBD" # To be either 'Generating backup for the job "JobName"' OR 'Restoring files for the job "JobName"'
        Status           = "Percent completed: 0%     Estimated time remaining: TDB"
        PercentComplete  = 0
        CurrentOperation = "Files copied: 0 / TBD     Files left: TBD"
    }
    $jobProgressParameters = @{
        ParentID         = 0
        ID               = 1
        Activity         = "TBD" # To be either 'Currently backing up: "JobDescription"' OR 'Currently restoring: "JobDescription"'
        Status           = "Percent completed: 0%      File size: TBD     Processing file: TBD"
        PercentComplete  = 0
        CurrentOperation = "Copied: 0 / TBD     Files Left: TBD"
    }

    Assert-Progress $overallProgressParameters $jobProgressParameters
.NOTES
    This function will work for any instance where you want to write a 2-level progress menu.  Just make sure that the hashtable keys are arguments that Write-Progress knows.
#>
function Assert-Progress {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, Position = 0)] [Hashtable] $overallProgressParams,
        [Parameter(Mandatory, Position = 1)] [Hashtable] $jobProgressParams
    )
    
    # this uses splatting to pass parameters to the Write-Progress cmdlet https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_splatting?view=powershell-5.1
    Write-Progress @overallProgressParams
    Write-Progress @jobProgressParams
}

<#
.SYNOPSIS
    Function to remove the progress bars used to display the progress of the backup/restore.
.DESCRIPTION
    This function will remove the two progress bars so that the progress windows will be removed from the terminal.
.EXAMPLE
    Clear-ProgressScreen
.NOTES
    This function is expecting a 2-level progress bar.
#>
function Clear-ProgressScreen {
    # Remove the progress bars because occasionally, the progress bars will stay on the terminal after it is done processing all the jobs
    Write-Progress -Id 1 -Activity "Completed" -Completed
    Write-Progress -Id 0 -Activity "Completed" -Completed
}

<#
.SYNOPSIS
    A function to terminate the script during the development phase.
.DESCRIPTION
    This function will remove two modeules "UI-Functions" and "Helper-Functions" before terminating the powershell script so you can run this script again and pull in any changes from the modules.
.EXAMPLE
    Exit-ScriptDevelopment
.NOTES
    This is used only for the production phase of the script.
#>
function Exit-ScriptDevelopment {
    Clear-Host
    Remove-Module 'UI-Functions'
    Remove-Module 'Helper-Functions'

    Write-Verbose "Exiting script"
    exit 1
}

<#
.SYNOPSIS
    A function to terminate the script duing the deployment phase.
.DESCRIPTION
    This function will terminate the powershell script but will not remove the modules "UI-Functions" and "Helper-Functions" from the shell instance.
.EXAMPLE
    Exit-ScriptDeployment
.NOTES
    This is used only for the deployment phase of the script.
#>
function Exit-ScriptDeployment {
    Clear-Host
    exit 1
}