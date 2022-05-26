$QUIT = "8"

function Print-Menu() {
    Write-Host "What would you like to do?"
    Write-Host "1) Mount WIM Image"
    Write-Host "2) Unmount WIM Image"
    Write-Host # Empty line for separation between the mounting and editing options
    Write-Host "3) Find Indexes within ESD/WIM Image" # Index means an individual OS, such as Windows Pro
    Write-Host "4) Convert ESD to WIM Image/Export Index of ESD/WIM Image"
    Write-Host "5) Find Indexes within ESD/WIM Image"
    Write-Host "6) Import Application Association XML File into WIM Image"
    Write-Host "7) Build Custom ISO"
    Write-Host "$QUIT) Exit"
    Write-Host # Empty line for separation between menu and user input
}


function Perform-Choice([int]$userChoice) {
    Clear-Host
    Write-Host "We made it!"
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
} until (
    $choice -eq $QUIT
)