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
