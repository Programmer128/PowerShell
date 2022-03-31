Param
(
    [string] $ShareGroupFile,
    [string] $ResultsFile  
)

#------------------------ BEGIN FUNCTIONS ----------------------------------

#This function is defined in the PowerShell profile.
Function Create-File($CSV)
{
    If(!(Test-Path $CSV))
    {
        New-Item -Path $CSV -ItemType File
    }
    Else
    {
        Remove-Item -Path $CSV
        New-Item -Path $CSV -ItemType File
    }
}

#The previous Match-ShareGroups.ps1 file creates the input file being processed in this script.
$Groups = Import-Csv -Path $ShareGroupFile | Select -ExpandProperty Group -Unique
$DataLines = Import-Csv -Path $ShareGroupFile
$ResultsFile = Create-File -CSV $ResultsFile

#Create Hash Table to store all group/share associations as arrays.
$SGAssociations = @{}

#Iterate each group in the Groups file.
ForEach($G in $Groups)
{      
    #Array to hold a list of PCustomObjects representing the shares associated with the currently iterated group.
    [System.Collections.ArrayList]$ShareArray = @()
    
    #Iterate each Share/Group line in the Shares/Groups file.
    ForEach($SG in $DataLines)
    {    
        $SGroup = $SG.Group
             
        If($G -eq $SGroup)
        { 
                      
            #Add the share in the current line to the current Group array.
            $ShareObject = [PSObject]@{
                SharePath = $SG.SharePath
                Match = $SG.ShareMatched}             
            #Add the current ShareObject to the Share array list.
            #The [void] return type is to suppress the console output of the arraylist index of each addition.
            [void]$ShareArray.Add($ShareObject)                         
        }  
    }         
    
    If($ShareArray.Count -gt 0)
    {           
        #Add the array list of associated shares as a value to the current group key.
        $SGAssociations.Add($G, $ShareArray)               
    }   
}

ForEach($Key in $SGAssociations.Keys)
{
    #Clear the Description and Notes variables.
    $Description = ""
    $Notes = ""
        
    [System.Collections.ArrayList]$V = $SGAssociations[$Key]
    
    ForEach($ValueArray in $V)
    {  
        #If this is the first share for this group, add it to the description.
        If($Description -eq "")
        {            
            $Line1 = $ValueArray.SharePath
            $Description = $Line1  
            $Description = $Line1
        }
        Else
        {
            #The info field for groups has 1024 character limit. There are a few groups with a large number of shares assigned.
            $Line2 = $ValueArray.SharePath + "`r`n"
            $NotesCheck += $Line2
            
            If($NotesCheck.Length -lt 1024)
            {
                $Notes += $Line2                
            }
        }
    }
    
    Add-content -path $ResultsFile -Value "K: $Key"
    Add-content -path $ResultsFile -Value "Desc: $Description"
    Add-content -path $ResultsFile -Value "Notes: $Notes"   
    Add-content -path $ResultsFile -Value " "
}