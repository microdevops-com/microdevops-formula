# Exit if no args
If ($args.count -eq 0)
{
	Exit
}

# Add user to Administrators (found by SID) group
$objSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
$objGroup = $objSID.Translate( [System.Security.Principal.NTAccount])
$groupName = $objGroup.Value -replace "BUILTIN\\", ""
$group = [ADSI]"WinNT://$env:computername/$groupName,group"
$group.Add("WinNT://$env:computername/$args,user")

# If we are on Domain Controller
$computer=Get-WMIObject win32_computersystem
If (($computer).domainrole -eq 5)
{
	# Get new user SID to find domain part
	$objUser = New-Object System.Security.Principal.NTAccount($args)
	$userSID = $objUser.Translate([System.Security.Principal.SecurityIdentifier])

	# Get domain SID by clearing last digits
	$domSID = $userSID.Value -replace "\d*$", ""

	# Get Domain Admins object by domain-SID-512
	$domAdm = New-Object System.Security.Principal.SecurityIdentifier($domSID + "512")

	# Get Domain Admins group local name by its SID
	$domAdmNameFull = $domAdm.Translate( [System.Security.Principal.NTAccount])
	$domAdmNameShort = $domAdmNameFull.Value -replace "^.*\\", ""
        
	$D = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
	$Domain = [ADSI]"LDAP://$D"
	$DN = $Domain.distinguishedName
	$DomAdmins = [ADSI]"LDAP://cn=$domAdmNameShort,cn=Users,$DN"
	$DomUser = [ADSI]"LDAP://cn=$args,cn=Users,$DN"
	
	If ($DomAdmins.IsMember($DomUser.ADsPath) -eq $False)
	{
		$DomAdmins.Add($DomUser.ADsPath)
	}
}

# Set user password never expires
$user = [ADSI]"WinNT://$env:computername/$args"
$user.UserFlags.value = $user.UserFlags.value -bor 0x10000
$user.CommitChanges()
