Param
(
    [string] $ShareToCheck,
    [string] $ParentFolder
)

#Function to get the sAMAccountName without the domain prefix and slash.
function Get-RemoveDomainFromName
{
    Param
    (
        [PSObject] $FIdentityProperty
    )

    #Get the sAMAccount name from the NTUser object stored in the Identity property of the PowerShell object.  
    $DomainNameInitial = $FIdentityProperty.ToString()
    #Remove the domain name prefix and "\" character from the account name.
    $DomainNameFinal  = $DomainNameInitial.Substring($DomainNameInitial.IndexOf('\') + 1)
    
    return $DomainNameFinal
}

#Function checks if a user account is an employee of External Company based on its company attribute.
function Get-UserIsExtCompany
{
    Param
    (
        [string] $AccountName,        
        [bool] $IsSystemAccount
    )    

    #System accounts (built-in accounts) have to be treated differently than users. These are skipped.
    #This does skip the Everyone account.
    If($IsSystemAccount)
    {
        return $false
    }
    else
    {
        #Get the AD user attribute that identifies which school an account is associated with.
        $UserSchoolCheck = Get-ADUser $AccountName -Properties company, enabled | Select company, enabled

        #Return true if the account is not associated with ExtCompany, and the account is not disabled.
        #These active non-ExtCompany accounts will be written to the report file.
        If($UserSchoolCheck.company -ne "External Company" -and $UserSchoolCheck.Enabled -ne $false)
        {
            return $true        
        }
        else
        {            
            return $false
        }
    }     
}

#Set up the parent report folder name.
function Create-DateFolder
{
    $Today = Get-Date

    $Month = $Today.Month
    $Day = $Today.Day.ToString()
    $Year = $Today.Year.ToString()

    #Convert the month number to the month name.
    $MonthName = (Get-Culture).DateTimeFormat.GetMonthName($Month)
    #Get the first 3 letters of the month name.
    $MonthName = $MonthName.Substring(0, 3)

    #Create parent report folder name. Ex: Aug272020 for a folder created on August 27, 2020.
    $DateFolder = $MonthName + $Day + $Year
    return $DateFolder
}

#Write user permission information to the report file if it is not an ExtCompany employee
function Write-UserToFile
{
    Param
    (
        [PSObject] $FileRightsObject,
        [string] $NameWithoutDomain,
        [string] $ReportFile,   
        [bool] $IsSystemAccount
    )      
        
    #Call the Get-UserInfo function defined above the main script body to determine if this is a InternalCompany account.
    $InternalCompanyUser = Get-UserIsExtCompany -AccountName $NameWithoutDomain -IsSystemAccount $IsSystemAccount

    #If the account does not belong to an ExtCompany employee, write its Access Control Entry information to the report file.
    If($InternalCompanyUser)
    {        
        $CSVLine = $F.FolderName + "," + $F.Identity + "," + $F.Permissions   
        Add-Content -Path $ReportFile $CSVLine             
    }                
}

#Write ACL information for groups to the file.
function Process-Group
{
    Param
    (
        [string] $AccountName,
        [hashtable] $Properties,
        [string] $ReportFile
    )

    $GroupUsers = Get-ADGroupMember -Identity $AccountName

    ForEach($user in $GroupUsers)
    {
        #Take the $Properties passed in from the parent group and restructure the hash table to include the current member. 
        #This is the only property that changes in the iteration of group members. All group members will have the permissions properties
        #of the original group passed into this function. The ACE of the original group is the ACE of this current group member by 
        #the Principle of Transitivity.
        $Properties = [ordered]@{'FolderName'=$Properties.FolderName;'Identity'=$user.sAMAccountName;'Permissions'=$Properties.Permissions;'Inherited'=$Properties.Inherited}

        #Create a PowerShell object to hold specific properties we need to determine between user/group, and ExtCompany/Non-ExtCompany accounts.
        $F = New-Object -TypeName PSObject -Property $Properties            
            
        #Get the sAMAccount name from the NTUser object stored in the Identity property of the PowerShell object.  
        $DomainNameInitial = $F.Identity.ToString()
          
        $DomainNameFinal  = Get-RemoveDomainFromName($F.Identity)
        #Get an ADObject type matching the sAMAccountName since we don't know yet if the name matches either a user or a group.
        $AccountType = (Get-ADObject -Filter {sAMAccountName -eq $DomainNameFinal})

        #If the objectClass of the AD object is "user", then this is a user account. Write to file.                       
        If($($AccountType.ObjectClass) -eq "user")
        {            
            #Write this non-ExtCompany user's permission info to the report file.
            Write-UserToFile -FileRightsObject $F -NameWithoutDomain $DomainNameFinal -ReportFile $ReportFile            
        }
        ElseIf($($AccountType.ObjectClass) -eq "group")
        {                        
            #Iterate again through this specific group.
            Process-Group -AccountName $DomainNameFinal -Properties $Properties -ReportFile $ReportFile
        }      
        Else
        {              
            #Write system account's permission info to the report file.
            Write-UserToFile -FileRightsObject $F -NameWithoutDomain $DomainNameFinal -ReportFile $ReportFile -IsSystemAccount $true
        }   
    }

    return
}

#--------- END Function Statements ---------------------------------#

$FolderPathToCheck = $ShareToCheck

#Set up destination folder variable for report.
$DateFolder = Create-DateFolder

$DestinationFolder = $ParentFolder + "\" + $DateFolder
#Set up report file variable.
$ReportFile = $DestinationFolder + "\" + $DateFolder + ".csv" 

#Check if the destination report folder exists. If not, create the folder and the report file.
If(!(Test-Path $DestinationFolder))
{
    #Create the destination folder for the report.
    New-Item -Path $ParentFolder -Name $DateFolder -ItemType Directory

    #Creating the report file is necessary since the destination folder did not exist.    
    New-Item -Path $ReportFile -ItemType File -Force
}
else
{
    #The folder exists, so we only need to check if the report file exists.
    If(!(Test-Path $ReportFile))
    {
        New-Item $ReportFile -ItemType File -Force
    }
}

#Folder structure to check
$FolderPath = Get-ChildItem -Directory -Path $ShareToCheck -Recurse -Force

ForEach ($Folder in $FolderPath) 
{
    $Acl = Get-Acl -Path $Folder.FullName        

    #Enumerate the System.Security.AccessControl.FileSystemAccessRule objects in the $Acl object.
    ForEach ($Access in $Acl.Access) 
    {
        #Create a Hash Table containing the required properties from the FileSystemAccessRule object representing
        #and individual ACE in an ACL.
        $Properties = [ordered]@{'FolderName'=$Folder.FullName;'Identity'=$Access.IdentityReference;'Permissions'=$Access.FileSystemRights;'Inherited'=$Access.IsInherited}
        #$FileRights = New-Object -TypeName PSObject -Property $Properties

        #Create a PowerShell object to hold specific properties we need to determine between user/group, and ExtCompany/Non-ExtCompany accounts.
        $F = New-Object -TypeName PSObject -Property $Properties            
            
        #Get the sAMAccount name from the NTUser object stored in the Identity property of the PowerShell object.  
        $DomainNameInitial = $F.Identity.ToString()
          
        $DomainNameFinal  = Get-RemoveDomainFromName($F.Identity)
                    
        #Get an ADObject type matching the sAMAccountName since we don't know yet if the name matches a user or a group.
        $AccountType = (Get-ADObject -Filter {sAMAccountName -eq $DomainNameFinal})
            
        #Check if the ADObject object returned above is a user.        
        If($($AccountType.objectClass) -eq "user")
        {                        
            #Write this non-ExtCompany user's permission info to the report file.
            Write-UserToFile -FileRightsObject $F -NameWithoutDomain $DomainNameFinal -ReportFile $ReportFile
        }
        ElseIf($($AccountType.ObjectClass) -eq "group")
        {                 
            #Iterate again through this specific group.
            Process-Group -AccountName $DomainNameFinal -Properties $Properties -ReportFile $ReportFile
        }
        Else
        {                
            #Write account's permission info to the report file if it is not a system account.
            Write-UserToFile -FileRightsObject $F -NameWithoutDomain $DomainNameFinal -ReportFile $ReportFile -IsSystemAccount $true
        }   
    }
}
