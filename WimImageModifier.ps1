$QUIT = 10 # Used to exit the program
$errorProceed = "Press any key to continue..."

function Print-Menu() {
    Write-Host "What would you like to do?`n"
    Write-Host "1) Mount ISO Image"
	Write-Host "2) Extract ISO Image"
    Write-Host "3) Dismount ISO Image"
    Write-Host "4) Find Indexes within ESD/WIM Image" # Index means an individual OS, such as Windows Pro
    Write-Host "5) Mount WIM Image"
    Write-Host "6) Dismount WIM Image"
    Write-Host "7) Convert ESD to WIM Image/Export Index of ESD/WIM Image"
    Write-Host "8) Import Application Association XML File into WIM Image"
    Write-Host "9) Repackage ISO from Source Files"
    Write-Host "$QUIT) Exit"
    Write-Host # Empty line for separation between menu and user input
}


function Mount-ISO([string]$path) {
    Write-Host "`nMounting ISO...`n"
    $mountResult = Mount-DiskImage -ImagePath "$path"
    $mountDrive = ($mountResult | Get-Volume).DriveLetter + ":\"
    $mountDriveFriendlyName = ($mountResult | Get-Volume).FileSystemLabel

    Write-Host "Successfully mounted $pathToISO on $mountDrive ($mountDriveFriendlyName)"
}

function Print-ISOPath($letter) {
    return (Get-Volume -ErrorAction SilentlyContinue -DriveLetter $letter  | % { Get-DiskImage -ErrorAction SilentlyContinue -DevicePath $($_.Path -replace "\\$")}).ImagePath
}

function CheckFor-ISOs() {
    Write-Host "Checking for mounted ISOs..."
    # Create an array of drive letters to check for mounted ISOs the user could be modifying
    $mountedISOs = @() # Start with an empty array so we don't end up with duplicates
    65..90 | ForEach-Object {
        $letter = "$([char]$_)" # Convert ASCII to a drive letter (A-Z)
        try {
            # See if an image path is present for the given drive letter. If so, add it to our array:
            $imagePath = Print-ISOPath($letter)
            if ($imagePath) {$mountedISOs += $letter}
        }
        catch {} # Do nothing
    }
    return $mountedISOs
}

function Dismount-ISO([char]$letterToDismount) {
    Write-Host "Dismounting $(Print-ISOPath($letterToDismount))...`n"
    $pathToISO = Print-ISOPath($letterToDismount)
    Dismount-DiskImage -ImagePath $pathToISO | Out-Null # Redirect input to Out-Null so nothing shows up on the console
    Write-Host "The ISO was dismounted successfully."
}

function Print-ISODrives($ISODrives) {
    Write-Host # Empty line for separation of terminal output
    if ($ISODrives.Count -gt 0) {
        Write-Host "The following drives appear to contain mounted ISO files:`n"
        # Show a table above our list of mounted ISOs:
        Write-Host "Drive:`t`t`tISO Mounted:"
        Write-Host "------`t`t`t-----------------------------------------------------------"

        foreach ($driveLetter in $ISODrives) {
            $driveLetter += ":\"
            Write-Host "$driveLetter"`t`t`t$(Print-ISOPath($driveLetter))
        }
        return $true
    }
    return $false
}

function Get-DestinationDir() {
    $destinationDir = Read-Host "Enter the destination you'd like to extract the files to"
    $destinationDir = ($destinationDir -replace "`"", "") # Remove quotation marks in case the user adds them.
    $destinationDir = $destinationDir.TrimEnd() # Remove ending spaces because they will conflict with using the variable later despite Windows still understanding the path
    $canProceed = $false
    while($canProceed -eq $false) {
        while ([string]::IsNullOrEmpty($destinationDir)) {
            $destinationDir = Read-Host "Invalid folder name. Please enter a different name"
            $destinationDir = ($destinationDir -replace "`"", "")
            $destinationDir = $destinationDir.TrimEnd() # Remove ending spaces because they will conflict with using the variable later despite Windows still understanding the path
        }
        if ($(Test-Path -PathType Container $destinationDir) -eq $false) {
            try {
                New-Item $destinationDir -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
                if ($(Test-Path -PathType Container $destinationDir) -eq $true) { Write-Host "Destination $destinationDir does not exist, so it will be created" }
            }
            catch [ArgumentException] {}
            if ($(Test-Path -PathType Container $destinationDir) -eq $false) {
                $destinationDir = Read-Host "Invalid folder name. Please enter a different name"
                $destinationDir = ($destinationDir -replace "`"", "")
                $destinationDir = $destinationDir.TrimEnd() # Remove ending spaces because they will conflict with using the variable later despite Windows still understanding the path
            }
        }
        if (($destinationDir) -and $(Test-Path -PathType Container $destinationDir) -eq $true) { $canProceed = $true }
    }
    return $destinationDir
}

function Extract-ISOFiles([string]$sourcePath, [string]$destinationPath) {
    $files = Get-ChildItem -Path $sourcePath -Recurse
    $filecount = $files.count
    $i=0
    Foreach ($file in $files) {
        $i++
        Write-Progress -activity "Extracting files..." -status "($i of $filecount) $file" -percentcomplete (($i/$filecount)*100)
    
        # Determine the absolute path of this object's parent container.  This is stored as a different attribute on file and folder objects so we use an if block to cater for both
        if ($file.psiscontainer) {$sourcefilecontainer = $file.parent} else {$sourcefilecontainer = $file.directory}
    
        # Calculate the path of the parent folder relative to the source folder
        $relativepath = $sourcefilecontainer.fullname.SubString($sourcePath.length)
    
        # Copy the object to the appropriate folder within the destination folder
        copy-Item $file.fullname ($destinationPath + $relativepath)
    }
}

function Perform-Choice([int]$userChoice) {
    switch ($userChoice) {
        1 {
            $pathToISO = Read-Host "Please specify a path to your ISO image"
            $pathToISO = ($pathToISO -replace "`"", "") # Remove quotation marks in case the user adds them.
            $pathToISO = $pathToISO.TrimEnd() # Remove ending spaces because they will conflict with using the variable later despite Windows still understanding the path
            while (([string]::IsNullOrEmpty($pathToISO)) -or (-not (Test-Path -Path $pathToISO -PathType Leaf)) -or (-not $pathToISO.EndsWith(".iso"))) {
                $pathToISO = Read-Host "The ISO was not found. Please try again"
                $pathToISO = ($pathToISO -replace "`"", "")
                $pathToISO = $pathToISO.TrimEnd() # Remove ending spaces because they will conflict with using the variable later despite Windows still understanding the path
            }
            # Now that we know the path to the ISO, mount it:
            Mount-ISO($pathToISO)
            Write-Host # Empty line for separating function output from menu
        }
		2 {
            # FIXME: Maybe use 7-Zip for this? Right now implemented via copy-paste.
            $ISODrives = CheckFor-ISOs
            $wantPrompt = Print-ISODrives($ISODrives)
            # If we can find a mounted ISO, ask the user to simply enter the drive letter:
            if ($wantPrompt -eq $true) {
                $ISOToExtract = Read-Host "`nEnter the drive letter of the ISO you would like to extract"
                $ISOToExtract = $ISOToExtract.TrimEnd() # Strip out accidental spaces the user may add at the end
                $ISOToExtract = $ISOToExtract.Replace(":\", "") # Optionally strip out these extra characters if the user adds them
                $ISOToExtract = $ISOToExtract.TrimEnd() # Remove ending spaces because they will cause valid input to be rejected
                
                while([string]::IsNullOrEmpty($ISOToExtract) -or ($ISOToExtract -notin $ISODrives)) {
                    $ISOToExtract = Read-Host "You did not enter a drive letter with a mounted ISO. Please try again"
                    $ISOToExtract = $ISOToExtract.Replace(":\", "") # Optionally strip out these extra characters if the user adds them
                    $ISOToExtract = $ISOToExtract.TrimEnd() # Remove ending spaces because they will cause valid input to be rejected
                }
                $destinationDir = Get-DestinationDir
                # Now that we have a valid path, we can utilize it:
                # TODO: Create the folder if it doesn't exist
                # TODO: Determine if the user can write to the directory. If they are not allowed, or it is in-use, do not allow try to copy the files:
                $ISOToExtract = $ISOToExtract + ":\" # Add this back so we can use it as a path, the * will also grab all files and folders
                if (-not ($destinationDir.EndsWith("\"))) { $destinationDir = $destinationDir + "\"} # Add a slash to the end of the directory so the copy function below works
                Extract-ISOFiles $ISOToExtract $destinationDir # TODO: Only do this if we have write permissions to the directory
            }
            else {
                Write-Host "You need to mount an ISO before you can extract it.`n$errorProceed"
                $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            }
		}
        3 {
            $ISODrives = CheckFor-ISOs
            $wantPrompt = Print-ISODrives($ISODrives)
            # If we can find a mounted ISO, ask the user to simply enter the drive letter:
            if ($wantPrompt -eq $true) {
                $driveToDismount = Read-Host "`nEnter the drive letter of the ISO you would like to dismount"
                $driveToDismount = $driveToDismount.TrimEnd() # Strip out accidental spaces the user may add at the end
                $driveToDismount = $driveToDismount.Replace(":\", "") # Optionally strip out these extra characters if the user adds them
                $driveToDismount = $driveToDismount.TrimEnd() # Remove ending spaces because they will cause valid input to be rejected
                
                while([string]::IsNullOrEmpty($driveToDismount) -or ($driveToDismount -notin $ISODrives)) {
                    $driveToDismount = Read-Host "You did not enter a drive letter with a mounted ISO. Please try again"
                    $driveToDismount = $driveToDismount.Replace(":\", "") # Optionally strip out these extra characters if the user adds them
                    $driveToDismount = $driveToDismount.TrimEnd() # Remove ending spaces because they will cause valid input to be rejected
                }
                Write-Host # Empty line for separation between user input and terminal output
                Dismount-ISO($driveToDismount)
                Write-Host # Empty line for terminal output separation
            }
            else {
                Write-Host -NoNewLine "No drives on the system appear to contain mounted ISOs.`n$errorProceed"
                $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            }
        }
        4 {
            $pathToWIM = Read-Host "Please specify a path to your WIM or ESD file"
            $pathToWIM = ($pathToWIM -replace "`"", "") # Remove quotation marks in case the user adds them.
            $pathToWIM = $pathToWIM.TrimEnd() # Remove ending spaces because they will conflict with using the variable later despite Windows still understanding the path
            while (([string]::IsNullOrEmpty($pathToWIM)) -or (-not (Test-Path -Path $pathToWIM -PathType Leaf)) -or ((-not $pathToWIM.EndsWith(".wim") -and (-not $pathToWIM.EndsWith(".esd"))))) {
                $pathToWIM = Read-Host "The WIM/ESD file was not found. Please try again"
                $pathToWIM = ($pathToWIM -replace "`"", "")
                $pathToWIM = $pathToWIM.TrimEnd() # Remove ending spaces because they will conflict with using the variable later despite Windows still understanding the path
            }
            # Now that we've found the file, determine it's indexes:
            Write-Host $(Get-WindowsImage -ImagePath "$pathToWIM" | Select-Object -Property ImageIndex, ImageName | Out-String)
            # TODO: Maybe fix the spacing on this so it's a bit wider, which could be done by saving the indexes to one array and the names to another, then using a for loop
        }
    }
    #Clear-Host
}





Clear-Host
# Loop the script until the user quits:
do {
    Print-Menu
    $choice = Read-Host "Choice"
    # Strip out accidental space characters:
    $choice = ($choice -replace " ", "")
    try { $choice = [int]$choice }
    catch {} # Do nothing
    while (($choice -isnot [int]) -or ($choice -notin 1..$QUIT)) {
            $choice = Read-Host "You did not enter a valid choice. Please try again"
            $choice = ($choice -replace " ", "")
            try { $choice = [int]$choice }
            catch {} # Do nothing
    }
    Perform-Choice($choice)
} until ($choice -eq $QUIT)