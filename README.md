# Auto Backup Utility
This Powershell script uses Robocopy and some predefined CSV files to allow you to choose one or more of the CSV files to either backup and/or restore directories/files you defined inside the file.

## Important Information
This Powershell script requires at least Powershell 7.4 to be installed for it to run, so if you don't have at least this version installed, then go to the [Powershell Github Repository](https://github.com/PowerShell/PowerShell) and install the most recent version.

## Building the CSV file
### Bare minimum
1. Figure out where you want to save the files from/to and add them to the example template in the `Source` and `Destination` columns.  The script is configured so when you perform a backup, it saves the files from `Source` and will copy them to `Destination` and restoring does the reverse.
2. Save the file as a `CSV (Comma delimited)` file with it being the name of what you want it to be displayed in the script.
### Optional configurations
3. Supply a description for the desired row inside the `Description` column for each entry, this will be what will be displayed when it is working on this line inside the script.
4. If you want to copy only specific files, then in the `FileMatching` column you add the name of the file.  You can use a pattern using the powershell wildcards `*` and `?` in the name if you desired.  If you want to supply more than one file to be copied, then separate each entry with a `/`.
    
    **Important Information:**
      - You can't supply the path to the file, only the name/pattern of the file
    
    Examples (caps-insensitive):
      - `New Text Document.txt` Will select only the files with the exact name "New Text Document.txt"
      - `*.docx` Will select only the files that end in ".docx"
      - `file?.jpeg` Will select the files that start with "file", followed by a single character, and ending in ".jpeg"
      - `*New*` Will select only the files that contain "New" inside it's name
5. If you want to exclude specific files/directories, then in the respective columns `ExcludedFiles` and `ExcludedDirectories`, supply the name/path of the files/directories you want to exclude.  If you are supplying the name of the files/directories, you can also use a pattern using the powershell wildcards `*` and `?` just like with copying specific files.  If you want to supply more than one file/directory to be excluded, then separate each entry with a `/`.
    
    **Important Information**
      - These entries have to be either the absolute path or the name/pattern of the file/directory.  I.E. you can't have a file structure pattern like `\parentFolder\New Text Document.txt` or `\parentFolder\sub folder`, this script will simply error out when it tries to run the command to backup/restore the files.
      - If you supply the full path and you want it to be excluded when both backing up/restoring the files, then you have to add 2 absolute paths using both the `Source` and `Destination` where the file will be.

    File examples (caps-insensitive):
      - `New Text Document.txt` Will exclude the files with the exact name "New Text Document.txt"
      - `*.docx` Will exclude the files that end in ".docx"
      - `file?.jpeg` Will exclude the files that start with "file", followed by a single character, and ending in ".jpeg"
      - `*New*` Will exclude the files that contain "New" inside it's name
      - `C:\New Text Document.txt` Will exclude the file "New Text Document.txt" stored inside the directory "C:\\"

    Directory examples (caps-insensitive):
      - `New folder` Will exclude the directories with the exact name "New folder"
      - `*folder` Will exclude the directories that end with "folder"
      - `New folder?` Will exclude the directories that start with "New folder" that is followed by a single character
      - `*New*` Will exclude the directories that contain "New" inside it's name
      - `C:\New folder` Will exclude the directory "New folder" stored inside the directory "C:\\"
      - `*` Will exclude all directories, I.E. it will only do the files in the directory supplied by the `Source`/`Destination` columns

## Startup Instructions
To start the script, run the PowerShell script "Start.ps1" in any Powershell terminal or "AutoBackup.ps1" in a Powershell 7 terminal.
If you get an error saying something along the lines of `(Start.ps1 or AutoBackup.ps1) cannot be loaded because running scripts is disabled on this system`, then you need to change your execution policy from either `Undefined` or `Restricted` to `RemoteSigned` for either the current user (recommend) or the local machine.
### How to view/change your execution policies
To view all of the execution policies for your system, run the following command in any Powershell terminal: `Get-ExecutionPolicy -List`

To change your execution policy for the current user or the local machine, you need to run one of the following commands in an administrator Powershell instance: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` or `Set-ExecutionPolicy -Scope LocalMachine RemoteSigned`
