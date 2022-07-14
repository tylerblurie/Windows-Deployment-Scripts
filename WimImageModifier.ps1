$QUIT = 10 # Used to exit the program
$INDEX_HELP_CHAR = "?"
$INDEX_HELP_PROMPT = "$INDEX_HELP_CHAR to view indexes"
$errorProceed = "Press any key to continue..."

function Print-Menu() {
    Write-Host "What would you like to do?`n"
    Write-Host "1) Mount ISO Image"
	Write-Host "2) Extract ISO Image"
    Write-Host "3) Dismount ISO Image"
    Write-Host "4) Find Indexes within ESD/WIM Image" # Index means an individual OS, such as Windows Pro
    Write-Host "5) Mount WIM Image"
    Write-Host "6) Unmount WIM Image"
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

function Get-DestinationDir([string]$prompt) {
    $destinationDir = Read-Host $prompt #"Enter the destination you'd like to extract the files to" # TODO: Customize this prompt so this function can be used for other things besides just extracting the files
    $destinationDir = ($destinationDir -replace "`"", "") # Remove quotation marks in case the user adds them.
    $destinationDir = $destinationDir.TrimEnd() # Remove ending spaces because they will conflict with using the variable later despite Windows still understanding the path
    $canProceed = $false
    while($canProceed -eq $false) {
        while ([string]::IsNullOrEmpty($destinationDir)) {
            $destinationDir = Read-Host "Invalid file or folder path. Please enter a different path"
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
                $destinationDir = Read-Host "Invalid file or folder path. Please enter a different path"
                $destinationDir = ($destinationDir -replace "`"", "")
                $destinationDir = $destinationDir.TrimEnd() # Remove ending spaces because they will conflict with using the variable later despite Windows still understanding the path
            }
        }
        if (($destinationDir) -and $(Test-Path -PathType Container $destinationDir) -eq $true) { $canProceed = $true }
    }
    return $destinationDir
}

function Get-MountedWIMDestinationDir() {
    $destinationDir = Read-Host "Enter the path that contains the files of the WIM image you would like to unmount"
    $destinationDir = ($destinationDir -replace "`"", "") # Remove quotation marks in case the user adds them.
    $destinationDir = $destinationDir.TrimEnd() # Remove ending spaces because they will conflict with using the variable later despite Windows still understanding the path
    $canProceed = $false
    while($canProceed -eq $false) {
        while ([string]::IsNullOrEmpty($destinationDir)) {
            $destinationDir = Read-Host "Invalid folder name. Please enter a different name"
            $destinationDir = ($destinationDir -replace "`"", "")
            $destinationDir = $destinationDir.TrimEnd() # Remove ending spaces because they will conflict with using the variable later despite Windows still understanding the path
        }
        if ($destinationDir -notin $($(Get-WindowsImage -Mounted).Path)) {
            $destinationDir = Read-Host "This path does not appear to contain files from a mounted WIM image. Please try again"
            $destinationDir = ($destinationDir -replace "`"", "")
            $destinationDir = $destinationDir.TrimEnd() # Remove ending spaces because they will conflict with using the variable later despite Windows still understanding the path
        }
        if (($destinationDir) -and $($destinationDir -in $(Get-WindowsImage -Mounted).Path)) { $canProceed = $true }
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
        copy-Item $file.fullname ($destinationPath + $relativepath) -PassThru | Where-Object { -not $_.PSIsContainer } | Set-ItemProperty -Name IsReadOnly -Value $false # Remove Read-Only attribute so we can modify
    }
    Write-Progress -Completed
}

function Get-WIMIndexes([string]$pathToWIM)
{
    $indexes = (Get-WindowsImage -ImagePath "$pathToWIM").ImageIndex
    $indexArray = @()
    foreach ($index in $indexes) {
        $indexArray += $index
    }
    return $indexArray
}

function Get-WIMIndexNames([string]$pathToWIM)
{
    $indexNames = (Get-WindowsImage -ImagePath "$pathToWIM").ImageName
    $nameArray = @()
    foreach ($name in $indexNames) {
        $nameArray += $name
    }
    return $nameArray
}

function Print-WIMIndexes([string]$pathToWIM)
{
    $indexArray = Get-WIMIndexes($pathToWIM)
    $nameArray = Get-WIMIndexNames($pathToWIM)
    Write-Host "Index:`t`t`tOperating System:"
    Write-Host "------`t`t`t-----------------------------------------------------------"

    for ($i = 0; $i -lt $indexArray.length; $i++) {
        Write-Host $indexArray[$i]"`t`t`t"$nameArray[$i]
    }
}

function Get-WIMPath() {
    $pathToWIM = Read-Host "Please specify a path to your WIM or ESD file"
    $pathToWIM = ($pathToWIM -replace "`"", "") # Remove quotation marks in case the user adds them.
    $pathToWIM = $pathToWIM.TrimEnd() # Remove ending spaces because they will conflict with using the variable later despite Windows still understanding the path
    while (([string]::IsNullOrEmpty($pathToWIM)) -or (-not (Test-Path -Path $pathToWIM -PathType Leaf)) -or ((-not $pathToWIM.EndsWith(".wim") -and (-not $pathToWIM.EndsWith(".esd"))))) {
        $pathToWIM = Read-Host "The WIM/ESD file was not found. Please try again"
        $pathToWIM = ($pathToWIM -replace "`"", "")
        $pathToWIM = $pathToWIM.TrimEnd() # Remove ending spaces because they will conflict with using the variable later despite Windows still understanding the path
    }
    return $pathToWIM
}


# This function is currently unused, but left in the code in case I later decide to space out (from left to right) the options for unmounting a WIM image.
function Get-MountedWIMImagePaths()
{
    $paths = $(Get-WindowsImage -Mounted).Path
    $pathArray = @()
    foreach ($path in $paths)
    {
        $pathArray += $path
    }
    return $pathArray
}

# This function is currently unused, but left in the code in case I later decide to space out (from left to right) the options for unmounting a WIM image.
function Get-MountedWIMImages()
{
    $images = $(Get-WindowsImage -Mounted).name
    $imageArray = @()
    foreach ($image in $images)
    {
        $imageArray += $image
    }
    return $imageArray
}

function Select-WIMIndex([string]$prompt, [string]$pathToWIM, [bool]$wantMultiIndexes=$false)
{
    if($wantMultiIndexes)
    {
        $plural = "(es)"
    } else {
        $plural = ""
    }
    Write-Host "`nDetecting operating systems...`n"
    $indexArray = Get-WIMIndexes($pathToWIM)
    $indexes = Read-Host $prompt
    $indexes = $indexes.Replace(" ", "") # Remove spaces
    if($wantMultiIndexes -eq $false) { $indexes = $indexes.Replace(",", "") } # Strip out commas early so we force the user to choose only one index if necessary.
    if($indexes.Contains(","))
    {
        $indexList = $indexes.Split(",") # Store all the indexes we want to convert
    }
    else {
        $indexList = $indexes
    }
    $allIndexesVaid = $true
    foreach($index in $indexList)
    {
        if($indexArray -notcontains $index) { $allIndexesVaid = $false }
    }
    while ($allIndexesVaid -eq $false)
    {
        if ($indexes -eq $INDEX_HELP_CHAR)
        {
            Write-Host "Fetching indexes..."
            Write-Host # Blank line
            Print-WIMIndexes($pathToWIM)
            Write-Host # Blank line
            $indexes = Read-Host $prompt
            $indexes = $indexes.Replace(" ", "") # Remove spaces
            if($wantMultiIndexes -eq $false) { $indexes = $indexes.Replace(",", "") } # Strip out commas early so we force the user to choose only one index if necessary.
            if($indexes.Contains(","))
            {
                $indexList = $indexes.Split(",") # Store all the indexes we want to convert
            }
            else {
                $indexList = $indexes
            }
            $allIndexesVaid = $true
            foreach($index in $indexList)
            {
                if($indexArray -notcontains $index) { $allIndexesVaid = $false }
            }
        }
        else
        {
            $indexes = Read-Host "Invalid index$plural. Please enter index$plural between (1-$($indexArray.Length)) [$INDEX_HELP_PROMPT]"
            $indexes = $indexes.Replace(" ", "") # Remove spaces
            if($wantMultiIndexes -eq $false) { $indexes = $indexes.Replace(",", "") } # Strip out commas early so we force the user to choose only one index if necessary.
            if($indexes.Contains(","))
            {
                $indexList = $indexes.Split(",") # Store all the indexes we want to convert
            }
            else {
                $indexList = $indexes
            }
            $allIndexesVaid = $true
            foreach($index in $indexList)
            {
                if($indexArray -notcontains $index) { $allIndexesVaid = $false }
            }
        }

    }
    return $indexList
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
                $destinationDir = Get-DestinationDir "Enter the destination you'd like to extract the files to"
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
            $pathToWIM = Get-WIMPath
            # Now that we've found the file, determine it's indexes:
            Write-Host "`nDetecting operating systems...`n"
            Print-WIMIndexes($pathToWIM)
            Write-Host
        }
        5 {
            $pathToWIM = Get-WIMPath
            $index = Select-WIMIndex "Enter the index of the operating system you'd like to mount ($INDEX_HELP_PROMPT)" $pathToWIM
            $destinationDir = Get-DestinationDir "Enter the destination you'd like to mount the files to"
            Dism.exe /Mount-Image /ImageFile:"$pathToWIM" /Index:$index /MountDir:"$destinationDir" /Optimize # TODO: Ensure write permissions
            Write-Host # Blank line in output
        }
        6 {
            $mountedImages = $(Get-WindowsImage -Mounted | Select-Object -Property Path, ImagePath, ImageIndex | Out-String)
            if (-not [string]::IsNullOrEmpty($mountedImages))
            {
                Write-Host "The following paths contain files pertaining to the following WIM images:"
                Write-Host $mountedImages
                $destinationDir = Get-MountedWIMDestinationDir
                $originalWIM = $(Get-WindowsImage -Mounted | Where-Object -Property Path -EQ $destinationDir).ImagePath # Take note of the original WIM to remind the user where it is
                $wantCommit = "" # Initialize null string for commit check
                while ($wantCommit -notin @("y", "n"))
                {
                    $wantCommit = Read-Host "Do you want to commit changes you've made to the WIM file (y/n)?"
                    $wantCommit = $wantCommit.Trim()
                }
                if ($wantCommit -eq "y") { $saveChangesArg = "Commit" }
                elseif ($wantCommit -eq "n") { $saveChangesArg = "Discard" }
                Write-Host "`nUnmounting WIM image. Please wait...`n"
                # If the user has an Explorer window open to the directory, we must close and re-open it so that the files can successfully unmount:
                $shell = New-Object -ComObject Shell.Application
                $window = $shell.Windows() | Where-Object { $_.LocationURL -like "$(([uri]$destinationDir).AbsoluteUri)*" }
                $wantReopen = $false
                if (-not [string]::IsNullOrEmpty($window))
                {
                    Write-Host "All Explorer windows in $destinationDir must be closed to proceed. Closing Explorer windows..."
                    $wantReopen = $true
                }
                $window | ForEach-Object { $_.Quit() }
                # All code after will be executed after window was closed
                Dism.exe /Unmount-Image /MountDir:$destinationDir /$saveChangesArg
                if ($wantReopen -eq $true)
                {
                    Write-Host "Reopening closed Explorer window..."
                    C:\Windows\explorer.exe $destinationDir
                }
                Write-Host "`nSuccessfully unmounted $originalWIM`n"
            }
            else
            {
                Write-Host "There are currently no WIM images to unmount.`n"
            }
            # TODO: Fix spacing on the output menu, and use numbers for convenience instead of making the user type the path
        }
        7 {
            $pathToWIM = Get-WIMPath
            $indexes = Select-WIMIndex "Enter the index(es) of the operating systems you'd like to export separated by commas (e.g., 1, 2, 3) [$INDEX_HELP_PROMPT]" $pathToWIM $true
            $destinationDir = Get-DestinationDir "Enter the destination folder you'd like to output the new WIM file to"
            foreach($index in $indexes)
            {
                $currentOS = $((Get-WindowsImage -ImagePath "$pathToWIM" -Index $index).ImageName)
                Write-Host "`nExporting OS: $currentOS"
                Dism /Export-Image /SourceImageFile:$pathToWIM /SourceIndex:$index /DestinationImageFile:$destinationDir\install.wim /Compress:max /CheckIntegrity
                Write-Host "`nFinished exporting $currentOS"
            }
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