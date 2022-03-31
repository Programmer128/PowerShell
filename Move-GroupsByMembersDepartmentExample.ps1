Param
(
    [string] $ResultFile,    
    [string] $DisabledUsersGroups  
)

##### FUNCTIONS #####
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
##### FUNCTIONS #####

$ResultFile = Create-File -CSV $ResultFile
#Write Results File Header line.
$HeaderLine = "Group" + "," + "DN" + "," +  "NumberMembers" + "," + "BDiv" + "," + "NumDiv" + "," + "BDept" + "," + "NumDept" + "," + "DiffDept" + "," + "AllDisabled"
Add-Content -Path $ResultFile -Value $HeaderLine

#File for storing names of groups where all members are disabled.
$DisabledUsersGroups = Create-File -CSV $DisabledUsersGroups

#Parent OU for all groups.
New-ADOrganizationalUnit -Name OrgGroups -DisplayName OrgGroups -Path "DC=xyz,DC=tex,DC=org" -Confirm:$false
$OrgGroupsPath = "OU=OrgGroups,DC=xyz,DC=tex,DC=org"

#Non-Department OUs arrays.
$NonDept = @('CallCenter', 'Audit', 'LKM', 'STWXY', 'LUB', 'SysAdmin', 'Testing', 'STEM')
$AppDept = @('Word', 'Teams', 'ERP', 'Windows', 'O365', 'ReportServices', 'PrinterSoftware', 'SCCM', 'vCenter')

#Create the parent Applications OU.
New-ADOrganizationalUnit -Name Applications -DisplayName Applications -Path $OrgGroupsPath -Confirm:$false
$AppsOUPath = "OU=Applications," + $OrgGroupsPath

#Move the non-department Groups OUs.
ForEach($OU in $NonDept)
{
    #Remove the accidental deletion protection property, move the OU to OrgGroups OU, and then reset the accidental deletion property.
    $OUName = "OU=" + $OU + ",OU=Security Groups,DC=xyz,DC=tex,DC=org"
    Set-ADOrganizationalUnit -Identity $OU -ProtectedFromAccidentalDeletion $false -Confirm:$false
    Move-ADObject -Identity $OUName -TargetPath $OrgGroupsPath -Confirm:$false 
    $NewOUName = "OU=" + $OU + "," + $OrgGroupsPath
    Set-ADOrganizationalUnit -Identity $NewOUName -ProtectedFromAccidentalDeletion $true -Confirm:$false    
}

#Move the Application groups OUs
ForEach($OU in $AppDept)
{
    #Remove the accidental deletion protection property, move the OU to OrgGroups OU, and then reset the accidental deletion property.
    $OUName = "OU=" + $OU + ",OU=Security Groups,DC=xyz,DC=tex,DC=org"
    Set-ADOrganizationalUnit -Identity $OU -ProtectedFromAccidentalDeletion $false -Confirm:$false
    Move-ADObject -Identity $OUName -TargetPath $AppsOUPath -Confirm:$false 
    $NewOUName = "OU=" + $OU + "," + $AppsOUPath
    Set-ADOrganizationalUnit -Identity $NewOUName -ProtectedFromAccidentalDeletion $true -Confirm:$false    
}

#Get all groups with no members.
$EmptyGroups = Get-ADGroup -Filter * -Properties sAMAccountName, distinguishedName, members -SearchBase "OU=Security Groups,DC=xyz,DC=tex,DC=org" | where { $_.Members.Count -eq 0 } | Select sAMAccountName, distinguishedName

#Create the EmptyGroups OU.
New-ADOrganizationalUnit -Name EmptyGroups -DisplayName EmptyGroups -Path $OrgGroupsPath -Confirm:$false
$EmptyGroupsOU = "OU=EmptyGroups," + $OrgGroupsPath

#Move the empty groups into the EmptyGroups OU
ForEach($E in $EmptyGroups)
{
    Move-ADObject -Identity $E.distinguishedName -TargetPath $EmptyGroupsOU -Confirm:$false
}

##### Get all groups with at least one member. #####
$Groups = Get-ADGroup -Filter * -Properties sAMAccountName, distinguishedName, Members -SearchBase "OU=Security Groups,DC=xyz,DC=tex,DC=org" | where { $_.Members.Count -gt 0 } | Select sAMAccountName, distinguishedName

#Hash table for storing groups and the primary divisions/departments of their members
$GroupsDivDept = @{}

ForEach($G in $Groups)
{
    $GroupName = $G.sAMAccountName
    $GroupDN = $G.distinguishedName
    #Distinguished name is logged to keep track of where group came from.
    $DN = $G.distinguishedName

    #For determining the number of members from different departments in a group.
    $DiffDepts = 0

    #Filter out distribution groups.
    If($GroupName -notlike "dis*" -and $GroupDN -notlike "*distributiongroups*")
    {
        #Get the count for the group members.
        $NumMembers = (Get-ADGroup -Identity $GroupName -Properties Member).Member.Count
        
        #If there are more than 999 users, this is a campus-wide group.
        If($NumMembers -gt 999)
        {            
            #Check if the CampusWide OU exists before the group to it.
            If(Get-ADOrganizationalUnit -Filter {distinguishedName -eq "OU=CampusWide,OU=OrgGroups,DC=xyz,DC=tex,DC=org"})
            {
                Move-ADObject -Identity $GroupDN -TargetPath "OU=CampusWide,OU=OrgGroups,DC=xyz,DC=tex,DC=org"
            }
            Else
            {
                #Create the CampusWide OU and then move the group to it.
                New-ADOrganizationalUnit -Name CampusWide -DisplayName CampusWide -Path $OrgGroupsPath -Confirm:$false
                Move-ADObject -Identity $GroupDN -TargetPath "OU=CampusWide,OU=OrgGroups,DC=xyz,DC=tex,DC=org"
            }
        }
        
        If($NumMembers -lt 1000)
        {                        
            #Hash table to keep track of the number of members are in which departments for the currently iterated group.
            $Depts = @{}
            #Hash table to keep track of the number of members are in which divisions for the currently iterated group.
            $Divisions = @{}
            #For determining if all group members are disabled.
            $AllDisabled = $false
           
            #Track disabled members to check if all are disabled.
            $Disabled = 0
    
            #Get the users in the group.
            $Members = Get-ADGroupMember -Identity $GroupName

            ForEach($U in $Members)
            {
                $SAM = $U.samaccountname

                #Get an ADObject type matching the sAMAccountName since we don't know yet if the name matches a user or a group.
                $AccountType = (Get-ADObject -Filter {sAMAccountName -eq $SAM}).ObjectClass

                #If the group member is a user data type, it will not throw an error when run through the Get-ADUser cmdlet.
                If($AccountType -eq "user")
                {  
                    #Get the departments for all group memebers
                    $MemberDept = Get-ADUser -Identity $SAM -Properties department, division, enabled, description, info | Select department, division, enabled, description, info
                    $UserDeptProp = $MemberDept.department   
                    $UserDiv = $MemberDept.division
                    $UserEnabled = $MemberDept.enabled         
                    $UserDesc = $MemberDept.description
                    $UserDept = $MemberDept.info
                                          
                    #Check if the member user is a student, not assigned to a department.
                    #The collection of students is considered a division/department in addition to the official divisions/departments.
                    If($UserDesc -eq "student".ToLower())
                    {
                        If($UserDept -eq $null -and $UserDeptProp -eq $null)
                        {
                            #If this group's user department hash table does not contain this user's department, add it.
                            If($Depts.ContainsKey($UserDesc) -eq $false)
                            {                        
                                $Depts.Add($UserDesc, 1)
                                #Increment the count number of different departments in the group.
                                $DiffDepts = $DiffDepts + 1
                            }
                            Else
                            {
                                #If this group's department hash table does containt this user's department already, increment the department key counter value by one.
                                $Depts.$UserDesc = $Depts.$UserDesc + 1                       
                            }
                        }
                        ElseIf($UserDept -ne $null) #Use the user account's Department property instead of Notes field if it has a value.
                        {
                            #If this group's user department hash table does not contain this user's department, add it.
                            If($Depts.ContainsKey($UserDept) -eq $false)
                            {                        
                                $Depts.Add($UserDept, 1)
                                #Increment the count number of different departments in the group.
                                $DiffDepts = $DiffDepts + 1
                            }
                            Else
                            {
                                #If this group's department hash table does contain this user's department already, increment the department key counter value by one.
                                $Depts.$UserDept = $Depts.$UserDept + 1                       
                            }
                        }
                        ElseIf($UserDeptProp -ne $null)
                        {
                            #If this group's user department hash table does not contain this user's department, add it.
                            If($Depts.ContainsKey($UserDeptProp) -eq $false)
                            {                        
                                $Depts.Add($UserDeptProp, 1)
                                #Increment the count number of different departments in the group.
                                $DiffDepts = $DiffDepts + 1
                            }
                            Else
                            {
                                #If this group's department hash table does contain this user's department already, increment the department key counter value by one.
                                $Depts.$UserDeptProp = $Depts.$UserDeptProp + 1                       
                            }
                        }

                        #Set the division for the group based on the student's properties.
                        If($UserDiv -ne $null)
                        {
                            $Divisions.Add($UserDiv, 1)
                        }                            
                        Else
                        {
                            #If this users division is already present, increment it by one.
                            $Divisions.$UserDiv = $Divisions.$UserDiv + 1
                        }                         
                        Else #If group's division hashtable does not contain "student", add it.
                        {
                            If($Divisions.ContainsKey($UserDesc) -eq $false)
                            {
                                $Divisions.Add($UserDesc, 1)
                            }
                            Else
                            {
                                #If this users division is already present, increment it by one.
                                $Divisions.$UserDesc = $Divisions.$UserDesc + 1
                            }
                        }
                    }                   

                    Else #Process all Faculty/Staff (non-students) member users.
                    {
                        #Only process if the user has a department defined to avoid errors.
                        If($UserDept -ne $null)
                        {
                            #If this group's user department hash table does not contain this user's department, add it.
                            If($Depts.ContainsKey($UserDept) -eq $false)
                            {                        
                                $Depts.Add($UserDept, 1)
                                #Increment the count number of different departments in the group.
                                $DiffDepts = $DiffDepts + 1
                            }
                            Else
                            {
                                #If this group's department hash table does containt this user's department already, increment the department key counter value by one.
                                $Depts.$UserDept = $Depts.$UserDept + 1                       
                            }
                        }
                        ElseIf($UserDeptProp -ne $null) #Use the user account's Department property instead of Notes field if it has a value.
                        {
                            #If this group's user department hash table does not contain this user's department, add it.
                            If($Depts.ContainsKey($UserDeptProp) -eq $false)
                            {                        
                                $Depts.Add($UserDeptProp, 1)
                                #Increment the count number of different departments in the group.
                                $DiffDepts = $DiffDepts + 1
                            }
                            Else
                            {
                                #If this group's department hash table does contain this user's department already, increment the department key counter value by one.
                                $Depts.$UserDept = $Depts.$UserDeptProp + 1                       
                            }
                        }

                        #Track divisions like departments above.
                        If($UserDiv -ne $null)
                        {
                            #If group's division hashtable does not contain this user's division, add it.
                            If($Divisions.ContainsKey($UserDiv) -eq $false)
                            {
                                $Divisions.Add($UserDiv, 1)
                            }
                            Else
                            {
                                #If this users division is already present, increment it by one.
                                $Divisions.$UserDiv = $Divisions.$UserDiv + 1
                            }
                        }
                    }

                    #Check if the user is disabled. Count of disabled users will be compared to total number of members later to mark groups with ony
                    #disabled users in it.
                    If($UserEnabled -eq $false)
                    {
                        $Disabled = $Disabled + 1
                    }                    
                }
                ElseIf($AccountType -eq 'computer')
                {                                   
                    #Set computer's department/division equal to 'computer'.
                    $UserDept = 'ComputerGroups'
                    $UserDiv = 'ComputerGroups'

                    #If this group's user department hash table does not contain this user's department, add it.
                    If($Depts.ContainsKey($UserDept) -eq $false)
                    {                        
                        $Depts.Add($UserDept, 1)
                        #Increment the count number of different departments in the group.
                        $DiffDepts = $DiffDepts + 1
                    }
                    Else
                    {
                        #If this group's department hash table does containt this user's department already, increment the department key counter value by one.
                        $Depts.$UserDept = $Depts.$UserDept + 1                       
                    }
                                       
                    #If group's division hashtable does not contain this user's division, add it.
                    If($Divisions.ContainsKey($UserDiv) -eq $false)
                    {
                        $Divisions.Add($UserDiv, 1)
                    }
                    Else
                    {
                        #If this users division is already present, increment it by one.
                        $Divisions.$UserDiv = $Divisions.$UserDiv + 1
                    }   
                }                 
            }
        }        
    }    
    Else
    {
        #This is the one move operation in the group enumeration section. 
        #Path for Distribution Groups OU. All Distribution groups go in the same OU.
        $DisOUPath = "OU=DistributionGroups,OU=OrgGroups,DC=xyz,DC=tex,DC=org"

        #Check if OU for distribution groups exists.
        If(Get-ADOrganizationalUnit -Filter {distinguishedName -eq $DisOUPath})
        {
            #Move the dstribution group to the DistributionGroups OU.
            Move-ADObject -Identity $GroupName -TargetPath $DisOUPath -Confirm:$false
        }
        Else
        {
            #Create the DistributionGroups OU, then move the distribution group to that OU
            New-ADOrganizationalUnit -Name DistributionGroups -DisplayName DistributionGroups -Path $OrgGroupsPath -Confirm:$false
            Move-ADObject -Identity $GroupName -TargetPath $DisOUPath -Confirm:$false
        }
    }
                
        
    #----------------- START Process Divisions and Departments for each group ----------------- 

    $BiggestDept = ""
    $BiggestDiv = ""
    $MaxDept = 0
    $MaxDiv = 0
        
    #Check if any user departments were found before iterating the hash table to avoid throwing null errors.
    If($Depts.Count -gt 0)
    {
        ForEach($Key in $Depts.Keys)
        {
            #If currently iterated department has more members than the current maximum members department, replace the maximum department name.
            If($Depts[$Key] -gt $MaxDept -or $Depts[$Key] -eq $MaxDept)
            {
                $BiggestDept = $Key
                $MaxDept = $Depts[$Key]                
            }            
        }      
    }

    #Check if any user divisions were found before iterating the hash table to avoid throwing null errors.
    If($Divisions.Count -gt 0)
    {
        ForEach($Key in $Divisions.Keys)
        {
            #If currently iterated division has more members than the current maximum members division, replace the maximum division.
            If($Divisions[$Key] -gt $MaxDiv -or $Divisions[$Key] -eq $MaxDiv)
            {
                $BiggestDiv = $Key
                $MaxDiv = $Divisions[$Key]
            } 
        }
    }
        
    #Mark Groups where all members were disabled.
    If($NumMembers -eq $Disabled)
    {
        $AllDisabled = $true

        Add-Content -Path $DisabledUsersGroups -Value $GroupName
    }       
        
    #Log information about each group before moving.
    $Line = $GroupName + "|" + $DN + "|" +  $NumMembers + "|" + $BiggestDiv + "|" + $MaxDiv + "|" + $BiggestDept + "|" + $MaxDept + "|" + $DiffDepts + "|" + $AllDisabled
        
    Add-Content -Path $ResultFile -Value $Line

    #Collect the group information into a PowerShell object.
    $GroupInfo = [ordered]@{'DN'=$DN;'NumMembers'=$NumMembers;'Div'=$BiggestDiv;'MaxDiv'=$MaxDiv;'Dept'=$BiggestDept;'MaxDept'=$MaxDept;'DiffDepts'=$DiffDepts}
    $GInfoObject = New-Object -TypeName PSObject -Property $GroupInfo

    #Add the group information to the Groups hash table. This information will dictate where the group goes in the new OU structure.
    $GroupsDivDept.Add($GroupName, $GInfoObject)   
}

#----------------- END Process Divisions and Departments for each group ----------------- 

#-------------------------- BEGIN AD GROUPS REORG --------------------------#

$DisabledOUPath = "OU=AllDisabledMembers" + $OrgGroupsPath

New-ADOrganizationalUnit -Name AllDisabledMembers -DisplayName AllDisabledMembers -Path $DisabledOUPath -Confirm:$false

ForEach($Key in $GroupsDivDept.Keys)
{    
    $V = $GroupsDivDept[$Key]

    $GroupDN = $V.DN

    #For division and department names, remove all spaces, and replace all non-alphanumeric characters with a "-" character.
    $Div = $V.Div.Replace(" ", "")
    $Div = $Div -replace "\W", "-
    "
    $Dept = $V.Dept.Replace(" ", "")
    $Dept = $Dept -replace "\W", "-"

    #Set the OU path for the Division.
    $DivPath = "OU=" + $Div + "," + $OrgGroupsPath
    
    If($Div -eq "Students")
    {
        #Check if the Division OU exists.
        If(Get-ADOrganizationalUnit -Filter {distinguishedName -eq $DivPath})
        {
            #Move the group to the Division OU
            Move-ADObject -Identity $GroupDN -TargetPath $DivPath -Confirm:$false
        }
        Else
        {
            #Create the Division OU and then move the group to it.
            New-ADOrganizationalUnit -Name $Div -DisplayName $Div -Path $OrgGroupsPath -Confirm:$false
            Move-ADObject -Identity $GroupDN -TargetPath $DivPath -Confirm:$false            
        }
    }
    ElseIf($Div -eq 'ComputerGroups')
    {
        #Check if the Division OU exists.
        If(Get-ADOrganizationalUnit -Filter {distinguishedName -eq $DivPath})
        {
            #Move the group to the Division OU
            Move-ADObject -Identity $GroupDN -TargetPath $DivPath -Confirm:$false
        }
        Else
        {
            #Create the Division OU and then move the group to it.
            New-ADOrganizationalUnit -Name $Div -DisplayName $Div -Path $OrgGroupsPath -Confirm:$false
            Move-ADObject -Identity $GroupDN -TargetPath $DivPath -Confirm:$false            
        }
    }        
    Else #Process non-student/computer groups.
    {
        #Check if group has only disabled users.
        If($AllDisabled -eq $true)
        {
            Move-ADObject -Identity $DN -TargetPath DisabledOUPath -Confirm:$false
        }

        #If there are more than three departments represented in the group, the group is moved to the Division level OU
        If($DiffDepts -gt 3)
        {
            #Check if the Division OU exists.
            If(Get-ADOrganizationalUnit -Filter {distinguishedName -eq $DivPath})
            {
                #Move the group to the Division OU
                Move-ADObject -Identity $GroupDN -TargetPath $DivPath -Confirm:$false
            }
            Else
            {
                #Create the Division OU and then move the group to it.
                New-ADOrganizationalUnit -Name $Div -DisplayName $Div -Path $OrgGroupsPath -Confirm:$false
                Move-ADObject -Identity $GroupDN -TargetPath $DivPath -Confirm:$false            
            }
        }
        Else
        {
            #Set the Department OU path.
            $DeptPath = "OU=" + $Dept + ",OU=" + $Div + "," + $OrgGroupsPath

            #Check if the Division OU exists.
            If(Get-ADOrganizationalUnit -Filter {distinguishedName -eq $DivPath})
            {
                #Check if the Department OU path exists.
                If(Get-ADOrganizationalUnit -Filter {distinguishedName -eq $DeptPath})
                {
                    #Move the group to the Department OU
                    Move-ADObject -Identity $GroupDN -TargetPath $DeptPath -Confirm:$false
                }
                Else
                {
                    #Create the Department OU and then move the group to it.
                    New-ADOrganizationalUnit -Name $Dept -DisplayName $Dept -Path $DivPath -Confirm:$false
                    Move-ADObject -Identity $GroupDN -TargetPath $DeptPath -Confirm:$false       
                }
            }
            Else
            {
                #Create the Division OU and then move the group to it.
                New-ADOrganizationalUnit -Name $Div -DisplayName $Div -Path $OrgGroupsPath -Confirm:$false

                #Check if the Department OU path exists.
                If(Get-ADOrganizationalUnit -Filter {distinguishedName -eq $DeptPath})
                {
                    #Move the group to the Department OU
                    Move-ADObject -Identity $GroupDN -TargetPath $DeptPath -Confirm:$false
                }
                Else
                {
                    #Create the Department OU and then move the group to it.
                    New-ADOrganizationalUnit -Name $Dept -DisplayName $Dept -Path $DivPath -Confirm:$false
                    Move-ADObject -Identity $GroupDN -TargetPath $DeptPath -Confirm:$false       
                }
            }
        }
    }
}