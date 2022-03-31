# PowerShell
PowerShell Scripts for Active Directory or File Systems

The Get-SharePermissions.ps1 script iterates through a server's shared folders and their subfolders and writes ACL information to file. A PSObject is used to keep track of the share path/group name/permissions information.

The Set-GroupDescriptionsFromFile.ps1 reads a CVS file with data on server shares ACLs, and always writes the UNC path of the first share found in the file to which a group has access for writing to the Active Directory group's description attribute when a 2nd script is run. If there are other shares the group has access to then those are written, one UNC path per line, to the file. Since the notes attribute has a 1024 character limit, the script keeps track of the number of characters written to the notes attribute and stops writing group share access information to file if an UNC path would exceed that character limit for a group's Active Directory notes attribute.
A separate script reads this resulting file and writes the data to all the groups' description attributes. 
