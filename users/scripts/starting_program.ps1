# Exit if no args
If ($args.count -eq 0)
{
	Exit
}

# Set Environment Tab Starting Program and Dir
$server = [ADSI]"WinNT://$env:computername"
$user = $server.psbase.get_children().find($($args[0]))
$user.PSBase.InvokeSet("TerminalServicesInitialProgram", "$($args[1])")
$user.PSBase.InvokeSet("TerminalServicesWorkDirectory", "$($args[2])")
$user.setinfo()

# Other useful settings for future reference
#$user.PSBase.InvokeSet("MaxConnectionTime", 120)
#$user.PSBase.InvokeSet("MaxDisconnectionTime", 1)
#$user.PSBase.InvokeSet("MaxIdleTime", 30)
#$user.PSBase.InvokeSet("BrokenConnectionAction", 1)
#$user.PSBase.InvokeSet("ReconnectionAction", 1)
#$user.PSBase.InvokeSet("FullName", $fullname)
