$QUIT = 10 # Used to exit the program
$mountDrive = "" # Drive storing the ISO file the user is modifying

function Print-Menu() {
    Write-Host "What would you like to do?`n"
    Write-Host "1) Mount ISO Image"
    Write-Host "2) Unmount ISO Image"
    Write-Host "3) Mount WIM Image"
    Write-Host "4) Unmount WIM Image"
    Write-Host # Empty line for separation between the mounting and editing options
    Write-Host "5) Find Indexes within ESD/WIM Image" # Index means an individual OS, such as Windows Pro
    Write-Host "6) Convert ESD to WIM Image/Export Index of ESD/WIM Image"
    Write-Host "7) Find Indexes within ESD/WIM Image"
    Write-Host "8) Import Application Association XML File into WIM Image"
    Write-Host "9) Build Custom ISO"
    Write-Host "$QUIT) Exit"
    Write-Host # Empty line for separation between menu and user input
}


function Perform-Choice([int]$userChoice) {
    switch ($choice) {
        1 {
            $pathToISO = Read-Host "Please specify a path to your ISO image"
            $pathToISO = ($pathToISO -replace "`"", "") # Remove quotation marks in case the user adds them.
            $pathToISO = $pathToISO.TrimEnd() # Remove ending spaces because they will conflict with using the variable later despite Windows still understanding the path
            while ((-not (Test-Path $pathToISO)) -or (-not $pathToISO.EndsWith(".iso"))) {
                $pathToISO = Read-Host "The ISO was not found. Please try again"
                $pathToISO = ($pathToISO -replace "`"", "")
                $pathToISO = $pathToISO.TrimEnd() # Remove ending spaces because they will conflict with using the variable later despite Windows still understanding the path
            }
            # Now that we know the path to the ISO, mount it:
            Write-Host "`nMounting ISO...`n"
            $mountResult = Mount-DiskImage -ImagePath "$pathToISO"
            $mountDrive = ($mountResult | Get-Volume).DriveLetter + ":\" # We need to remember the drive letter so we can use it when modifying the WIM file.
            $mountDriveFriendlyName = ($mountResult | Get-Volume).FileSystemLabel
        }
    }
    #Clear-Host
    Write-Host "Successfully mounted $pathToISO on $mountDrive ($mountDriveFriendlyName)"
    Write-Host # Empty line for separating function output from menu
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