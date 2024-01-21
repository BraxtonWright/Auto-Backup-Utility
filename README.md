# Auto Backup Utility
This Powershell script uses Robocopy and some predefined CSV files to allow you to choose one or more of the CSV files to either backup and/or restore directories/files you defined inside the file.

## Important Information
This Powershell script requires at least Powershell 7.4 to be installed for it to run, so if you don't have at least this version installed, then go to the [Powershell Github Repository](https://github.com/PowerShell/PowerShell) and install the most recent version.

## Startup Instructions
To start the script, run the PowerShell script "Start.ps1" in any Powershell terminal or "AutoBackup.ps1" in a Powershell 7 terminal.
If you get an error saying something along the lines of `(Start.ps1 or AutoBackup.ps1) cannot be loaded because running scripts is disabled on this system`, then you need to change your execution policy from either `Undefined` or `Restricted` to `RemoteSigned` for either the current user (recommend) or the local machine.
### How to view/change your execution policies
To view all of the execution policies for your system, run the following command in any Powershell terminal: `Get-ExecutionPolicy -List`<br />
To change your execution policy for the current user or the local machine, you need to run one of the following commands in an administrator Powershell instance: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` or `Set-ExecutionPolicy -Scope LocalMachine RemoteSigned`.
