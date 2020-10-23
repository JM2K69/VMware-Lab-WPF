#########################################################################
#                        Add shared_assemblies                          #
#########################################################################

[Void][System.Reflection.Assembly]::LoadWithPartialName('presentationframework') 
foreach ($item in $(gci .\assembly\ -Filter *.dll).name) {
    [Void][System.Reflection.Assembly]::LoadFrom("assembly\$item")
}
Add-Type -AssemblyName System.Windows.Forms | Out-Null
Function New-Log {
    param(
    [Parameter(Mandatory=$true)]
    [String]$message
    )
	$logMessage = [System.Text.Encoding]::UTF8
    $timeStamp = Get-Date -Format "MM-dd-yyyy_HH:mm:ss"
    $logMessage = "[$timeStamp] $message"
    $logMessage | Out-File -Append -LiteralPath $Global:pathLog 
}
#########################################################################
#                        Load Main Panel                                #
#########################################################################
$verboseLogFile = "VMwareLab.log"
$Global:pathLog = "$env:USERPROFILE\desktop\$verboseLogFile" 

$Global:pathPanel= split-path -parent $MyInvocation.MyCommand.Definition
function LoadXaml ($filename){
    $XamlLoader=(New-Object System.Xml.XmlDocument)
    $XamlLoader.Load($filename)
    return $XamlLoader
}
$XamlMainWindow=LoadXaml("$Global:pathPanel\main.xaml")
$reader = (New-Object System.Xml.XmlNodeReader $XamlMainWindow)
$Form = [Windows.Markup.XamlReader]::Load($reader)

$XamlMainWindow.SelectNodes("//*[@Name]") | %{
    try {Set-Variable -Name "$("WPF_"+$_.Name)" -Value $Form.FindName($_.Name) -ErrorAction Stop}
    catch{throw}
    }

Function Get-FormVariables{
if ($global:ReadmeDisplay -ne $true){Write-host "If you need to reference this display again, run Get-FormVariables" -ForegroundColor Yellow;$global:ReadmeDisplay=$true}
write-host "Found the following interactable elements from our form" -ForegroundColor Cyan
get-variable *WPF*
}
#Get-FormVariables

Import-Module "$Global:pathPanel\vmxtoolkit\4.5.3.1\vmxtoolkit.psm1" -Force
#########################################################################
#                           Initialization                              #
#########################################################################
if ($PSVersionTable.PSVersion -lt [version]"6.0.0") {
    Write-Verbose "this will check if we are on 6"
}
if ($env:windir) {
    $OS_Version = Get-Command "$env:windir\system32\ntdll.dll"
    $OS_Version = "Windows $($OS_Version.Version)"
    $Global:vmxtoolkit_type = "win_x86_64"
    write-verbose "getting VMware Path from Registry"
    if (!(Test-Path "HKCR:\")) { $NewPSDrive = New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT }
    if (!($VMware_Path = Get-ItemProperty HKCR:\Applications\vmware.exe\shell\open\command -ErrorAction SilentlyContinue)) {
        Write-Error "VMware Binaries not found from registry"
        Break
    }

    $preferences_file = "$env:AppData\VMware\preferences.ini"
    $VMX_BasePath = '\Documents\Virtual Machines\'	
    $VMware_Path = Split-Path $VMware_Path.'(default)' -Parent
    $VMware_Path = $VMware_Path -replace '"', ''
    $Global:vmwarepath = $VMware_Path
    $Global:vmware = "$VMware_Path\vmware.exe"
    $Global:vmrun = "$VMware_Path\vmrun.exe"
    $Global:vmware_vdiskmanager = Join-Path $VMware_Path 'vmware-vdiskmanager.exe'
    $Global:VMware_OVFTool = Join-Path $Global:vmwarepath 'OVFTool\ovftool.exe'
    $GLobal:VMware_packer = Join-Path $Global:vmwarepath '7za.exe'
    $VMwarefileinfo = Get-ChildItem $Global:vmware
    $Global:vmxinventory = "$env:appdata\vmware\inventory.vmls"
    $Global:vmwareversion = New-Object System.Version($VMwarefileinfo.VersionInfo.ProductMajorPart, $VMwarefileinfo.VersionInfo.ProductMinorPart, $VMwarefileinfo.VersionInfo.ProductBuildPart, $VMwarefileinfo.VersionInfo.ProductVersion.Split("-")[1])
    $webrequestor = ".Net"
    $Global:mkisofs = "$Global:vmwarepath/mkisofs.exe"
}
elseif ($OS = uname) {
    Write-Host "found OS $OS"
    Switch ($OS) {
        "Darwin" {
            $Global:vmxtoolkit_type = "OSX"
            $OS_Version = (sw_vers)
            $OS_Version = $OS_Version -join " "
            $VMX_BasePath = 'Documents/Virtual Machines.localized'
            # $VMware_Path = "/Applications/VMware Fusion.app"
            $VMware_Path = mdfind -onlyin /Applications "VMware Fusion"                
            $Global:vmwarepath = $VMware_Path
            [version]$Fusion_Version = defaults read $VMware_Path/Contents/Info.plist CFBundleShortVersionString
            $VMware_BIN_Path = Join-Path $VMware_Path  '/Contents/Library'
            $preferences_file = "$HOME/Library/Preferences/VMware Fusion/preferences"
            try {
                $webrequestor = (get-command curl).Path
            }
            catch {
                Write-Warning "curl not found"
                exit
            }
            try {
                $GLobal:VMware_packer = (get-command 7za -ErrorAction Stop).Path 
            }
            catch {
                Write-Warning "7za not found, pleas install p7zip full"
                Break
            }

            $Global:VMware_vdiskmanager = Join-Path $VMware_BIN_Path 'vmware-vdiskmanager'
            $Global:vmrun = Join-Path $VMware_BIN_Path "vmrun"
            switch ($Fusion_Version.Major) {
                "10" {
                    $Global:VMware_OVFTool = "/Applications/VMware Fusion.app/Contents/Library/VMware OVF Tool/ovftool"
                    [version]$Global:vmwareversion = "14.0.0.0"
                }
					
                default {
                    $Global:VMware_OVFTool = Join-Path $VMware_Path 'ovftool'
                    [version]$Global:vmwareversion = "12.0.0.0"
                }
            }

        }
        'Linux' {
            $Global:vmxtoolkit_type = "LINUX"
            $OS_Version = (uname -o)
            #$OS_Version = $OS_Version -join " "
            $preferences_file = "$HOME/.vmware/preferences"
            $VMX_BasePath = '/var/lib/vmware/Shared VMs'
            try {
                $webrequestor = (get-command curl).Path
            }
            catch {
                Write-Warning "curl not found"
                exit
            }
            try {
                $VMware_Path = Split-Path -Parent (get-command vmware).Path
            }
            catch {
                Write-Warning "VMware Path not found"
                exit
            }

            $Global:vmwarepath = $VMware_Path
            $VMware_BIN_Path = $VMware_Path  
            try {
                $Global:VMware_vdiskmanager = (get-command vmware-vdiskmanager).Path
            }
            catch {
                Write-Warning "vmware-vdiskmanager not found"
                break
            }
            try {
                $GLobal:VMware_packer = (get-command 7za).Path
            }
            catch {
                Write-Warning "7za not found, pleas install p7zip full"
            }
				
            try {
                $Global:vmrun = (Get-Command vmrun).Path
            }	
            catch {
                Write-Warning "vmrun not found"
                break
            }
            try {
                $Global:VMware_OVFTool = (Get-Command ovftool).Path
            }
            catch {
                Write-Warning "ovftool not found"
                break
            }
            try {
                $Global:mkisofs = (Get-Command mkisofs).Path
            }
            catch {
                Write-Warning "mkisofs not found"
                break
            }
            $Vmware_Base_Version = (vmware -v)
            $Vmware_Base_Version = $Vmware_Base_Version -replace "VMware Workstation "
            [version]$Global:vmwareversion = ($Vmware_Base_Version.Split(' '))[0]
        }
        default {
            Write-host "Sorry, rome was not build in one day"
            exit
        }
			
			
			
        'default' {
            write-host "unknown linux OS"
            break
        }
    }
}
else {
    write-host "error detecting OS"
}

if (Test-Path $preferences_file) {
        Write-Verbose "Found VMware Preferences file"
        Write-Verbose "trying to get vmx path from preferences"
        $defaultVMPath = get-content $preferences_file | Select-String prefvmx.defaultVMPath
        if ($defaultVMPath) {
            $defaultVMPath = $defaultVMPath -replace "`""
            $defaultVMPath = ($defaultVMPath -split "=")[-1]
            $defaultVMPath = $defaultVMPath.TrimStart(" ")
            Write-Verbose "default vmpath from preferences is $defaultVMPath"
            $VMX_default_Path = $defaultVMPath
            $defaultselection = "preferences"
        }
        else {
            Write-Verbose "no defaultVMPath in prefernces"
        }
    }

if (!$VMX_Path) {
    if (!$VMX_default_Path) {
        Write-Verbose "trying to use default vmxdir in homedirectory" 
        try {
            $defaultselection = "homedir"
            $Global:vmxdir = Join-Path $HOME $VMX_BasePath
        }
        catch {
            Write-Warning "could not evaluate default Virtula machines home, using $PSScriptRoot"
            $Global:vmxdir = $PSScriptRoot
            $defaultselection = "ScriptRoot"
            Write-Verbose "using psscriptroot as vmxdir"
        }
		
    }
    else {
        if (Test-Path $VMX_default_Path) {
            $Global:vmxdir = $VMX_default_Path	
        }
        else {
            $Global:vmxdir = $PSScriptRoot
        }
		
    }
}
else {
    $Global:vmxdir = $VMX_Path
}

#### some vmx api error handlers :-) false positives from experience
$Global:VMrunErrorCondition = @(
    "Waiting for Command execution Available",
    "Error",
    "Unable to connect to host.",
    "Error: Unable to connect to host.",
    "Error: The operation is not supported for the specified parameters",
    "Unable to connect to host. Error: The operation is not supported for the specified parameters",
    "Error: The operation is not supported for the specified parameters",
    "Error: vmrun was unable to start. Please make sure that vmrun is installed correctly and that you have enough resources available on your system.",
    "Error: The specified guest user must be logged in interactively to perform this operation",
    "Error: A file was not found",
    "Error: VMware Tools are not running in the guest",
    "Error: The VMware Tools are not running in the virtual machine" )
if (!$GLobal:VMware_packer) {
    Write-Warning "Please install 7za/p7zip, otherwise labbtools can not expand OS Masters"
}
New-Log -message "-----------------------------------------------"
New-Log -message "initializing search VMware workstation config"
New-Log -message "------------------------------------------------"

if ($OS_Version) {

New-Log -message " ==>$OS_Version"
}
else	{
    write-host "error Detecting OS"
    Break
}
New-Log -message " ==>running vmxtoolkit for $Global:vmxtoolkit_type"
New-Log -message " ==>vmrun is $Global:vmrun"
New-Log -message " ==>vmwarepath is $Global:vmwarepath"
if ($VMX_Path) {
    New-Log -message " ==>using virtual machine directory from module load $Global:vmxdir"
}
else {
    New-Log -message " ==>using virtual machine directory from $defaultselection`: $Global:vmxdir"
}	
New-Log -message " ==>running VMware Version Mode $Global:vmwareversion"
New-Log -message " ==>OVFtool is $Global:VMware_OVFTool"
New-Log -message " ==>Packertool is $GLobal:VMware_packer"
New-Log -message " ==>vdisk manager is $Global:vmware_vdiskmanager"
New-Log -message " ==>webrequest tool is $webrequestor"
New-Log -message " ==>isotool is $Global:mkisofs"

New-Log -message "-----------------------------------------------"
New-Log -message "VMware workstation config finish successfully  "
New-Log -message "------------------------------------------------"
#########################################################################
#                              Variables                                #
#########################################################################

#Default Param
$VMNET = @('VMnet2','VMnet3','VMnet4','VMnet5','VMnet6','VMnet7','VMnet8','VMnet9','VMnet10','VMnet11','VMnet12','VMnet13','VMnet14','VMnet15','VMnet16','VMnet17','VMnet18','VMnet19')
$VCSAType = @('Config','Full')
$ESXISize = @('XL','TXL','XXL')

$DESXI_param = @{
    VMnet = "VMnet2"
    Masterpath =  'D:\Lab' 
    BuildDomain = "vmware.local"
    Gateway = "10.0.0.254"
    DNS1 = "10.0.0.1"
    DNS2 = "10.0.0.2"
    subnet = "10.0.0"
    Nodeprefix = "NestedESX"
    Mastername = "ESXIMaster7"
    Size = "XXL"
    Nodes = 3
}

$DVCSA_param = @{
    VMnet = "VMnet2"
    Mastername ="VCSAMaster7"
    Masterpath = "D:\Lab"
    Builddir = "D:\Lab\Linked"
    BuildDomain = "vmware.local"
    subnet = "10.0.0"
    Password = "VMware123!"
    SSO_Domain = "vsphere.local"
    DNS1 = "1.1.1.1"
    Nodeprefix = "VCSA"
    DefaultGateway = "10.0.0.254"
    Type ="Full"
}

#########################################################################
#                         End  Variables                                #
#########################################################################


#########################################################################
#                              Functions                                #
#########################################################################
ForEach ($Item in $VMNET)
{
    $Data = New-Object PSObject
    $Data = $Data | Add-Member NoteProperty Data $Item.$Type -passthru	
    $WPF_WRKVMNET.Items.Add($item) > $null						

}
ForEach ($Item in $VCSAType)
{
    $Data = New-Object PSObject
    $Data = $Data | Add-Member NoteProperty Data $Item.$Type -passthru	
    $WPF_TypeVCSA.Items.Add($item) > $null						

}
ForEach ($Item in $ESXISize)
{
    $Data = New-Object PSObject
    $Data = $Data | Add-Member NoteProperty Data $Item.$Type -passthru	
    $WPF_VM_Size.Items.Add($item) > $null						

}
$WPF_TypeVCSA.Add_SelectionChanged({

    if ($WPF_TypeVCSA.SelectedItem -eq "Full"){
        New-Log -message "==> VCSA deployment is set to full automated"
        $Script:VCSAType = "Full"
    }
    if ($WPF_TypeVCSA.SelectedItem -eq "Config"){
        New-Log -message "==> VCSA deployment is set to deploy only  the you need to configure manually"
        $Script:VCSAType = "ConfigOnly"

    }
})
$WPF_VM_Size.Add_SelectionChanged({


   if ($WPF_VM_Size.SelectedItem -eq "TXL"){

    $WPF_ESXICPUV.Content   = '4'
    $WPF_ESXIRAMV.Content   = '6 GB' 
    New-Log -message "==> ESXI size change 4 vCPU and 6GB RAM"

}

if ($WPF_VM_Size.SelectedItem -eq "XL"){

    $WPF_ESXICPUV.Content   = '2'
    $WPF_ESXIRAMV.Content   = '4 GB'
    New-Log -message "==> ESXI size change 2 vCPU and 4GB RAM"


   }
   if ($WPF_VM_Size.SelectedItem -eq "XXL"){

    $WPF_ESXICPUV.Content   = '4'
    $WPF_ESXIRAMV.Content   = '8 GB' 
    New-Log -message "==> ESXI size change 4 vCPU and 8GB RAM"

   }
})

#########################################################################
#                         End  Functions                                #
#########################################################################
$WPF_NESXI_N.Text = $DESXI_param.Nodeprefix
$WPF_NB_ESXI.Value =  $DESXI_param.Nodes
$WPF_Network_V.Text = $DESXI_param.subnet
$WPF_Gateway.Text = $DESXI_param.Gateway
$WPF_Network_Mask.Text = "255.255.255.0"
$WPF_DNS_Server.Text = $DESXI_param.DNS1
$WPF_Site_Name.Text = $DVCSA_param.BuildDomain
$WPF_Domain_Name.Text = $DVCSA_param.SSO_Domain
$WPF_Passwd_R.Password = $DVCSA_param.Password
$WPF_Passwd_VCSA.Password = $DVCSA_param.Password
$WPF_IPAddress.Text = $DESXI_param.subnet + ".80"
$WPF_NB_Disk.Value = 0
$WPF_NB_Disk.IsReadOnly = $True
$WPF_NTP.IsEnabled = $false

$WPF_Cancel.Add_Click({

    Exit

})

$WPF_Theme.Add_Click({
   $Theme1 = [ControlzEx.Theming.ThemeManager]::Current.DetectTheme($form)
    $my_theme = ($Theme1.BaseColorScheme)
	If($my_theme -eq "Light")
		{
            [ControlzEx.Theming.ThemeManager]::Current.ChangeThemeBaseColor($form,"Dark")
            $WPF_Theme.ToolTip = "Theme Dark"

		}
	ElseIf($my_theme -eq "Dark")
		{					
            [ControlzEx.Theming.ThemeManager]::Current.ChangeThemeBaseColor($form,"Light")
            $WPF_Theme.ToolTip = "Theme Light"
		}		
})

$WPF_BaseColor.Add_Click({

    $Script:Colors=@()
    $Accent = [ControlzEx.Theming.ThemeManager]::Current.ColorSchemes
    foreach ($item in $Accent)
    {
        $Script:Colors += $item
    }

    $Value = $Script:Colors[$(Get-Random -Minimum 0 -Maximum 23)]
    [ControlzEx.Theming.ThemeManager]::Current.ChangeThemeColorScheme($form ,$Value)
    $WPF_BaseColor.ToolTip = "BaseColor : $Value"

})

$WPF_Info.Add_Click({

    $WPF_CInfo.IsOpen = $true

})
$WPF_Settings.Add_Click({

    #$WPF_CSettings.IsOpen = $true

})
$WPF_Workstation_versionV.Content = $Global:vmwareversion
$WPF_OS_TypeV.Content = $OS_Version
$WPF_WRKVMNET.SelectedIndex = 0
$WPF_TypeVCSA.SelectedIndex = 1
$WPF_VM_Size.SelectedIndex = 1

$WPF_Wizard.Add_Click({

    $WPF_WWizard.IsOpen = $true

})

$WPF_Create_M.Add_Click({

New-Log -message "-----------------------------------------------"
New-Log -message " Create Master For ESXi and VCSA                "
New-Log -message "------------------------------------------------"

    $Lab_ESXI_param = @{
        VMnet = $WPF_WRKVMNET.SelectedItem
        Masterpath =  $WPF_Folder.Content
        BuildDomain = $WPF_Site_Name.Text
        Gateway = $WPF_Gateway.Text
        DNS1 = $WPF_DNS_Server.Text
        DNS2 = $WPF_DNS_Server.Text
        subnet = $WPF_Network_V.Text
        Nodeprefix = $WPF_NESXI_N.Text
        Mastername = $Script:Mastername_ESXI
        Size = $WPF_VM_Size.SelectedItem
        Nodes = $WPF_NB_ESXI.Value
    }
    
    $Lab_VCSA_param = @{
        VMnet = $WPF_WRKVMNET.SelectedItem
        Mastername = $Script:Mastername_VCSA
        Masterpath = $WPF_Folder.Content
        Builddir = $WPF_Folder.Content + "\Linked"
        BuildDomain = $WPF_Site_Name.Text
        subnet = $WPF_Network_V.Text
        Password = $WPF_Passwd_R.Password
        SSO_Domain = $WPF_Domain_Name.Text
        DNS1 = "1.1.1.1"
        Nodeprefix = "VCSA"
        DefaultGateway = $WPF_Gateway.Text
        Type = $Script:VCSAType
    }

    $Filter = "OVA files (*.OVA)|*.OVA"
    $OpenFileDialog = New-Object -TypeName System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.CheckPathExists = $true
    $OpenFileDialog.CheckFileExists = $true
    $OpenFileDialog.Title = "Choose Nested ESXi Appliance Template ova file"
    $OpenFileDialog.Filter = $Filter 
    $OpenFileDialog.ShowHelp = $True
    [void]$OpenFileDialog.ShowDialog()
    $FileESXI = $OpenFileDialog.FileName

    New-Log -message "==> You Choose the filename $FileESXI for your ESXI appliance  "
   
    $Filter = "OVA files (*.OVA)|*.OVA"
    $OpenFileDialog = New-Object -TypeName System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.CheckPathExists = $true
    $OpenFileDialog.CheckFileExists = $true
    $OpenFileDialog.Title = "Choose VMware vCenter Server Appliance Ova"
    $OpenFileDialog.Filter = $Filter 
    $OpenFileDialog.ShowHelp = $True
    [void]$OpenFileDialog.ShowDialog()
    $OpenFileDialog.FileName
    $FileVCSA = $OpenFileDialog.FileName

    New-Log -message "==> You Choose the filename $FileESXI for your VCSA appliance  "


    $ParamList = @{

        ESXI_param = $Lab_ESXI_param      
        VCSA_param = $Lab_VCSA_param
        filenameESXI = $FileESXI
        filenameVCSA = $FileVCSA
        PathPanel =   $Global:pathPanel      
}          

    $runspace = [runspacefactory]::CreateRunspace()
    $powershell = [powershell]::Create()
    $powershell.runspace = $runspace
    $runspace.Open()

    [void]$powershell.AddScript({

        Param ($ESXI_param, $VCSA_param, $filenameESXI, $filenameVCSA, $PathPanel)
            function New-LABMaster{
                param(
                    $import,
                    [Parameter(Mandatory=$true)]
                    [ValidateSet('ESXIMaster6.7','ESXIMaster7','VCSAMaster6.7','VCSAMaster7','TrueNasCore')]
                    [String]$Mastername,
                    [Parameter(Mandatory=$true)]
                    $Masterpath  
            
                )
                begin
                {
                        try
                           {
                            $MasterVMX = get-VMx -path $Masterpath | Where-Object {$_.VMXName -match "$Mastername"}
                           }
                        catch{     }
            
                    if( $null -eq $MasterVMX)
                    {
                   $Import= Import-VMXOVATemplate -OVA $import -name $Mastername -acceptAllEulas -AllowExtraConfig -quiet -destination $MasterPath -Verbose
            
                     $MasterVMX = get-VMx -path $Masterpath | Where-Object {$_.VMXName -match "$Mastername"}
            
                    }
            
                }
            
                Process
                {
                if (!$MasterVMX.Template) 
                    {
                    $template = $MasterVMX | Set-VMXTemplate
                    }
                $Basesnap = $MasterVMX | Get-VMXSnapshot -WarningAction SilentlyContinue| Where-Object Snapshot -Match "Base" 
            
                if (!$Basesnap) 
                    {
                    $Basesnap = $MasterVMX | New-VMXSnapshot -SnapshotName "Base"
                    }
            
                }
            
                end{}
            
            
            }
            function New-LabVCSA {
                [CmdletBinding()]
                Param(
                [Parameter(Mandatory=$true)]
                [ValidateSet('VCSAMaster6.5','VCSAMaster7')]
                [String]$Mastername,
                [Parameter(Mandatory=$true)]
                [ValidateSet('Full','ConfigOnly')]
                [String]$Type,
                [Parameter(Mandatory = $false)][switch]$Defaults,
                [Parameter(Mandatory=$false)]
                [ValidateSet('VMnet2','VMnet3','VMnet4','VMnet5','VMnet6','VMnet7','VMnet8','VMnet9','VMnet10','VMnet11','VMnet12','VMnet13','VMnet14','VMnet15','VMnet16','VMnet17','VMnet18','VMnet19')]
                $VMnet,
                $Masterpath,
                $Builddir ,
                $BuildDomain,
                [System.Version]$subnet ,
                $Password,
                $SSO_Domain,
                $DefaultGateway,
                $DNS1,
                $Nodeprefix
            
            
                )
                if (!$DNS2)
                    {
                    $DNS2 = $DNS1
                    }
                if (!$Masterpath) {$Masterpath = $Builddir}
            
                $Startnode = 1
                $Nodes = 1
            
            
                $Builddir = $PSScriptRoot
                try
                {
                $MasterVMX = get-VMx -path $Masterpath | Where-Object {$_.VMXName -match "$Mastername"}
                }
                catch{}
            
            
                foreach ($Node in $Startnode..(($Startnode-1)+$Nodes))
                    {
                    $ipoffset = 79+$Node
                    If (!(get-VMx -path $Nodeprefix$node -WarningAction SilentlyContinue))
                        {
                        $NodeClone = $MasterVMX | Get-VMXSnapshot | Where-Object Snapshot -Match "Base" | New-VMXlinkedClone -CloneName $Nodeprefix$node -Clonepath "D:\Lab\Linked" 
                        foreach ($nic in 0..0)
                            {
                            $Netadater0 = $NodeClone | Set-VMXVnet -Adapter $nic -vnet $VMnet -WarningAction SilentlyContinue
                            }
                        
                            switch ($Type) {
                                'full' { 			
                                        [string]$ip="$($subnet.ToString()).$($ipoffset.ToString())"
                                        $config = Get-VMXConfig -config $NodeClone.config
                                        $config += "guestinfo.cis.deployment.node.type = `"embedded`""
                                        $config += "guestinfo.cis.appliance.net.addr.family = `"ipv4`""
                                        $config += "guestinfo.cis.appliance.net.mode = `"static`""
                                        $config += "guestinfo.cis.appliance.net.addr = `"$ip`""
                                        $config += "guestinfo.cis.appliance.net.pnid = `"$ip`""
                                        $config += "guestinfo.cis.appliance.net.prefix = `"24`""
                                        $config += "guestinfo.cis.appliance.net.gateway = `"$DefaultGateway`""
                                        $config += "guestinfo.cis.appliance.net.dns.servers = `"$DNS1,$DNS2`""
                                        $config += "guestinfo.cis.appliance.root.passwd = `"$Password`""
                                        $config += "guestinfo.cis.appliance.ssh.enabled = `"true`""
                                        $config += "guestinfo.cis.deployment.autoconfig = `"true`""
                                       # $config += "guestinfo.cis.appliance.ntp.servers = `"0.fr.pool.ntp.org`""
                                        $config += "guestinfo.cis.vmdir.password = `"$Password`""
                                        $config += "guestinfo.cis.vmdir.domain-name = `"$SSO_Domain`""
                                        $config += "guestinfo.cis.vmdir.site-name = `"$BuildDomain`""
                                        $config += "guestinfo.cis.ceip.enabled = `"False`""
                                        $config | Set-Content -Path $NodeClone.config
                                        $Displayname = $NodeClone | Set-VMXDisplayName -DisplayName $NodeClone.CloneName
                                        $MainMem = $NodeClone | Set-VMXMainMemory -usefile:$false
                                        $Annotation = $Nodeclone | Set-VMXAnnotation -Line1 "Login Credentials" -Line2 "Administrator@$BuildDomain.$SSO_Domain" -Line3 "Password" -Line4 "$Password"
                                    }
                                'ConfigOnly'{
                                        [string]$ip="$($subnet.ToString()).$($ipoffset.ToString())"
                                        $config = Get-VMXConfig -config $NodeClone.config
                                        $config += "guestinfo.cis.deployment.node.type = `"embedded`""
                                        $config += "guestinfo.cis.deployment.autoconfig = `"False`""
                                        $config += "guestinfo.cis.appliance.net.addr.family = `"ipv4`""
                                        $config += "guestinfo.cis.appliance.net.addr = `"$ip`""
                                        $config += "guestinfo.cis.appliance.net.pnid = `"$ip`""
                                        $config += "guestinfo.cis.appliance.net.prefix = `"24`""
                                        $config += "guestinfo.cis.appliance.net.mode = `"static`""
                                        $config += "guestinfo.cis.appliance.net.dns.servers = `"$DNS1,$DNS2`""
                                        $config += "guestinfo.cis.appliance.net.gateway = `"$DefaultGateway`""
                                        $config += "guestinfo.cis.appliance.root.passwd = `"$Password`""
                                        $config += "guestinfo.cis.appliance.ssh.enabled = `"true`""
                                        $config += "guestinfo.cis.ceip.enabled = `"false`""
                                        $config | Set-Content -Path $NodeClone.config
                                        $Displayname = $NodeClone | Set-VMXDisplayName -DisplayName $NodeClone.CloneName
                                        $MainMem = $NodeClone | Set-VMXMainMemory -usefile:$false
                                        $Annotation = $Nodeclone | Set-VMXAnnotation -Line1 "Login Credentials" -Line2 "Administrator@$BuildDomain.$SSO_Domain" -Line3 "Password" -Line4 "$Password"
            
            
            
            
                                }    
                                Default {}
                            }
            
                        #$NodeClone | start-VMx | Out-Null
                        }
                    else
                        {
                        Write-Warning "Node $Nodeprefix$node already exists"
                        }
                }
                Write-host
            
            }
            function New-LabScenario {
                [CmdletBinding()]
                param (
                    [Parameter(Mandatory=$true)]
                    [ValidateSet('LabVM67','LabVM7')]
                    [String]$ScenarioName,
                    [Parameter(Mandatory=$true)]
                    $Builddir
            
                )
                    
                    $VMLAB = get-VMX -Path $Builddir
            
                    foreach ($item in $VMLAB) {
                
                        switch ($ScenarioName) {
                            'LabVM67' { $Number = 2 }
                            'LabVM7' { $Number = 1 }
            
                            Default {}
                        }
            
                   Set-VMXScenario -VMXName $item.VMXName -config $item.Config -path $Builddir -Scenario $Number -Scenarioname $ScenarioName
            
                }
                
            }
            function Start-LabVM {
                [CmdletBinding()]
                param (
                    [Parameter(Mandatory=$true)]
                    [ValidateSet('LabVM67','LabVM7')]
                    [String]$ScenarioName,
                    [Parameter(Mandatory=$true)]
                    $Builddir
            
                )
                
            
                  get-VMX -Path $Builddir| Where-Object scenario -Match $ScenarioName | start-vmx
            
                
            }
            
             Import-Module "$PathPanel\VMxtoolkit\4.5.3.1\VMxtoolkit.psm1" -Force
             if ($PSVersionTable.PSVersion -lt [version]"6.0.0") {
                Write-Verbose "this will check if we are on 6"
            }
            #write-Host "trying to get os type ... "
            if ($env:windir) {
                $OS_Version = Get-Command "$env:windir\system32\ntdll.dll"
                $OS_Version = "Product Name: Windows $($OS_Version.Version)"
                $Global:vmxtoolkit_type = "win_x86_64"
                write-verbose "getting VMware Path from Registry"
                if (!(Test-Path "HKCR:\")) { $NewPSDrive = New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT }
                if (!($VMware_Path = Get-ItemProperty HKCR:\Applications\vmware.exe\shell\open\command -ErrorAction SilentlyContinue)) {
                    Write-Error "VMware Binaries not found from registry"
                    Break
                }
            
                $preferences_file = "$env:AppData\VMware\preferences.ini"
                $VMX_BasePath = '\Documents\Virtual Machines\'	
                $VMware_Path = Split-Path $VMware_Path.'(default)' -Parent
                $VMware_Path = $VMware_Path -replace '"', ''
                $Global:vmwarepath = $VMware_Path
                $Global:vmware = "$VMware_Path\vmware.exe"
                $Global:vmrun = "$VMware_Path\vmrun.exe"
                $Global:vmware_vdiskmanager = Join-Path $VMware_Path 'vmware-vdiskmanager.exe'
                $Global:VMware_OVFTool = Join-Path $Global:vmwarepath 'OVFTool\ovftool.exe'
                $GLobal:VMware_packer = Join-Path $Global:vmwarepath '7za.exe'
                $VMwarefileinfo = Get-ChildItem $Global:vmware
                $Global:vmxinventory = "$env:appdata\vmware\inventory.vmls"
                $Global:vmwareversion = New-Object System.Version($VMwarefileinfo.VersionInfo.ProductMajorPart, $VMwarefileinfo.VersionInfo.ProductMinorPart, $VMwarefileinfo.VersionInfo.ProductBuildPart, $VMwarefileinfo.VersionInfo.ProductVersion.Split("-")[1])
                $webrequestor = ".Net"
                $Global:mkisofs = "$Global:vmwarepath/mkisofs.exe"
            }
            elseif ($OS = uname) {
                Write-Host "found OS $OS"
                Switch ($OS) {
                    "Darwin" {
                        $Global:vmxtoolkit_type = "OSX"
                        $OS_Version = (sw_vers)
                        $OS_Version = $OS_Version -join " "
                        $VMX_BasePath = 'Documents/Virtual Machines.localized'
                        # $VMware_Path = "/Applications/VMware Fusion.app"
                        $VMware_Path = mdfind -onlyin /Applications "VMware Fusion"                
                        $Global:vmwarepath = $VMware_Path
                        [version]$Fusion_Version = defaults read $VMware_Path/Contents/Info.plist CFBundleShortVersionString
                        $VMware_BIN_Path = Join-Path $VMware_Path  '/Contents/Library'
                        $preferences_file = "$HOME/Library/Preferences/VMware Fusion/preferences"
                        try {
                            $webrequestor = (get-command curl).Path
                        }
                        catch {
                            Write-Warning "curl not found"
                            exit
                        }
                        try {
                            $GLobal:VMware_packer = (get-command 7za -ErrorAction Stop).Path 
                        }
                        catch {
                            Write-Warning "7za not found, pleas install p7zip full"
                            Break
                        }
            
                        $Global:VMware_vdiskmanager = Join-Path $VMware_BIN_Path 'vmware-vdiskmanager'
                        $Global:vmrun = Join-Path $VMware_BIN_Path "vmrun"
                        switch ($Fusion_Version.Major) {
                            "10" {
                                $Global:VMware_OVFTool = "/Applications/VMware Fusion.app/Contents/Library/VMware OVF Tool/ovftool"
                                [version]$Global:vmwareversion = "14.0.0.0"
                            }
                                
                            default {
                                $Global:VMware_OVFTool = Join-Path $VMware_Path 'ovftool'
                                [version]$Global:vmwareversion = "12.0.0.0"
                            }
                        }
            
                    }
                    'Linux' {
                        $Global:vmxtoolkit_type = "LINUX"
                        $OS_Version = (uname -o)
                        #$OS_Version = $OS_Version -join " "
                        $preferences_file = "$HOME/.vmware/preferences"
                        $VMX_BasePath = '/var/lib/vmware/Shared VMs'
                        try {
                            $webrequestor = (get-command curl).Path
                        }
                        catch {
                            Write-Warning "curl not found"
                            exit
                        }
                        try {
                            $VMware_Path = Split-Path -Parent (get-command vmware).Path
                        }
                        catch {
                            Write-Warning "VMware Path not found"
                            exit
                        }
            
                        $Global:vmwarepath = $VMware_Path
                        $VMware_BIN_Path = $VMware_Path  
                        try {
                            $Global:VMware_vdiskmanager = (get-command vmware-vdiskmanager).Path
                        }
                        catch {
                            Write-Warning "vmware-vdiskmanager not found"
                            break
                        }
                        try {
                            $GLobal:VMware_packer = (get-command 7za).Path
                        }
                        catch {
                            Write-Warning "7za not found, pleas install p7zip full"
                        }
                            
                        try {
                            $Global:vmrun = (Get-Command vmrun).Path
                        }	
                        catch {
                            Write-Warning "vmrun not found"
                            break
                        }
                        try {
                            $Global:VMware_OVFTool = (Get-Command ovftool).Path
                        }
                        catch {
                            Write-Warning "ovftool not found"
                            break
                        }
                        try {
                            $Global:mkisofs = (Get-Command mkisofs).Path
                        }
                        catch {
                            Write-Warning "mkisofs not found"
                            break
                        }
                        $Vmware_Base_Version = (vmware -v)
                        $Vmware_Base_Version = $Vmware_Base_Version -replace "VMware Workstation "
                        [version]$Global:vmwareversion = ($Vmware_Base_Version.Split(' '))[0]
                    }
                    default {
                        Write-host "Sorry, rome was not build in one day"
                        exit
                    }
                        
                        
                        
                    'default' {
                        write-host "unknown linux OS"
                        break
                    }
                }
            }
            else {
                write-host "error detecting OS"
            }
            
            if (Test-Path $preferences_file) {
                    Write-Verbose "Found VMware Preferences file"
                    Write-Verbose "trying to get vmx path from preferences"
                    $defaultVMPath = get-content $preferences_file | Select-String prefvmx.defaultVMPath
                    if ($defaultVMPath) {
                        $defaultVMPath = $defaultVMPath -replace "`""
                        $defaultVMPath = ($defaultVMPath -split "=")[-1]
                        $defaultVMPath = $defaultVMPath.TrimStart(" ")
                        Write-Verbose "default vmpath from preferences is $defaultVMPath"
                        $VMX_default_Path = $defaultVMPath
                        $defaultselection = "preferences"
                    }
                    else {
                        Write-Verbose "no defaultVMPath in prefernces"
                    }
                }
            
            if (!$VMX_Path) {
                if (!$VMX_default_Path) {
                    Write-Verbose "trying to use default vmxdir in homedirectory" 
                    try {
                        $defaultselection = "homedir"
                        $Global:vmxdir = Join-Path $HOME $VMX_BasePath
                    }
                    catch {
                        Write-Warning "could not evaluate default Virtula machines home, using $PSScriptRoot"
                        $Global:vmxdir = $PSScriptRoot
                        $defaultselection = "ScriptRoot"
                        Write-Verbose "using psscriptroot as vmxdir"
                    }
                    
                }
                else {
                    if (Test-Path $VMX_default_Path) {
                        $Global:vmxdir = $VMX_default_Path	
                    }
                    else {
                        $Global:vmxdir = $PSScriptRoot
                    }
                    
                }
            }
            else {
                $Global:vmxdir = $VMX_Path
            }
            
            #### some vmx api error handlers :-) false positives from experience
            $Global:VMrunErrorCondition = @(
                "Waiting for Command execution Available",
                "Error",
                "Unable to connect to host.",
                "Error: Unable to connect to host.",
                "Error: The operation is not supported for the specified parameters",
                "Unable to connect to host. Error: The operation is not supported for the specified parameters",
                "Error: The operation is not supported for the specified parameters",
                "Error: vmrun was unable to start. Please make sure that vmrun is installed correctly and that you have enough resources available on your system.",
                "Error: The specified guest user must be logged in interactively to perform this operation",
                "Error: A file was not found",
                "Error: VMware Tools are not running in the guest",
                "Error: The VMware Tools are not running in the virtual machine" )
            if (!$GLobal:VMware_packer) {
            }
            if ($OS_Version) {
            }
            else	{
                Break
            }
            $path = $VCSA_param.Masterpath + "\Masters"

            New-LABMaster -import $filenameESXI -Mastername $ESXI_param.Mastername -Masterpath $path
            New-LABMaster -import $filenameVCSA -Mastername $VCSA_param.Mastername -Masterpath $path

            function New-LabESXI {  
                [CmdletBinding()]
                param (
                    [Parameter(Mandatory=$true)]
                    [ValidateSet('ESXIMaster6.7','ESXIMaster7')]
                    [String]$Mastername,
                    [ValidateRange(3,14)]
                    [int]$Disks ,
                    [ValidateRange(1,6)][int]
                    $Startnode = 1,
                    <# Size for openstack compute nodes
                    'XS'  = 1vCPU, 512MB
                    'S'   = 1vCPU, 768MB
                    'M'   = 1vCPU, 1024MB
                    'L'   = 2vCPU, 2048MB
                    'XL'  = 2vCPU, 4096MB
                    'TXL' = 4vCPU, 6144MB
                    'XXL' = 4vCPU, 8192MB
                    #>
                    [ValidateSet('XS', 'S', 'M', 'L', 'XL','TXL','XXL')]
                    $Size = "TXL",
                    [ValidateRange(1,6)]
                    [int]$Nodes = 1,
                    [Parameter(Mandatory = $false)][switch]$Defaults,
                    [Parameter(Mandatory=$false)]
                    [ValidateSet('VMnet2','VMnet3','VMnet4','VMnet5','VMnet6','VMnet7','VMnet8','VMnet9','VMnet10','VMnet11','VMnet12','VMnet13','VMnet14','VMnet15','VMnet16','VMnet17','VMnet18','VMnet19')]
                    $VMnet,
                    $Masterpath, 
                    $BuildDomain ,
                    $Gateway ,
                    $DNS1 ,
                    $DNS2 ,
                    [System.Version]$subnet,
                    $Nodeprefix
            
            
            
                )
                
                begin {
            
                                try
                                {
                                $MasterVMX = get-vmx -path $Masterpath | Where-Object {$_.VMXName -match "$Mastername"}
                                }
                        catch{}
                }
                
                process 
                {
            
                if (!$MasterVMX.Template) 
                    {
                    $template = $MasterVMX | Set-VMXTemplate
                    }
                $Basesnap = $MasterVMX | Get-VMXSnapshot -WarningAction SilentlyContinue| Where-Object Snapshot -Match "Base" 
            
                if (!$Basesnap) 
                    {
                    $Basesnap = $MasterVMX | New-VMXSnapshot -SnapshotName "Base"
                    }
            
                foreach ($Node in $Startnode..(($Startnode-1)+$Nodes))
                    {
                    $ipoffset = 80+$Node
                    If (!(get-VMx -path $Nodeprefix$node -WarningAction SilentlyContinue))
                        {
                        $NodeClone = $MasterVMX | Get-VMXSnapshot | where Snapshot -Match "Base" | New-VMXlinkedClone -CloneName $Nodeprefix$node -Clonepath "$Masterpath\Linked" 
                       
                        foreach ($nic in 0..1)
                            {
                            $Netadater0 = $NodeClone | Set-VMXVnet -Adapter $nic -vnet $VMnet -WarningAction SilentlyContinue
                            }
                        [string]$ip="$($subnet.ToString()).$($ipoffset.ToString())"
                        $config = Get-VMXConfig -config $NodeClone.config
                        $config += "guestinfo.hostname = `"$($NodeClone.CloneName).$BuildDomain`""
                        $config += "guestinfo.ipaddress = `"$ip`""
                        $config += "guestinfo.netmask = `"255.255.255.0`""
                        $config += "guestinfo.gateway = `"$Gateway`""
                        $config += "guestinfo.dns = `"$DNS1`""
                        $config += "guestinfo.domain = `"$Nodeprefix$Node.$BuildDomain`""
                        $config += "guestinfo.ntp = `"$DNS1`""
                        $config += "guestinfo.ssh = `"true`""
                        $config += "guestinfo.syslog = `"$ip`""
                        $config += "guestinfo.password = `"$Password`""
                        $config += "guestinfo.createVMfs = `"false`""
                        $config | Set-Content -Path $NodeClone.config
            
            
                        if ($Disks -ne 0)
                            {
                            $SCSI = 1
                            [uint64]$Disksize = 100GB
                            $NodeClone | Set-VMXScsiController -SCSIController 1 -Type lsilogic | Out-Null
                            foreach ($LUN in (0..($Disks-1)))
                                {
                                if ($LUN -ge 7)
                                    {
                                    $LUN = $LUN+1
                                    }
                                $Diskname =  "SCSI$SCSI"+"_LUN$LUN.VMdk"
                                $Newdisk = New-VMXScsiDisk -NewDiskSize $Disksize -NewDiskname $Diskname -Verbose -VMXName $NodeClone.VMXname -Path $NodeClone.Path
                                $AddDisk = $NodeClone | Add-VMXScsiDisk -Diskname $Newdisk.Diskname -LUN $LUN -Controller $SCSI -VirtualSSD
                                }
                            }
                        $result = $NodeClone | Set-VMXSize -Size $Size
                        $result = $NodeClone | Set-VMXGuestOS -GuestOS VMkernel6
                        $result = $NodeClone | Set-VMXVTBit -VTBit:$true
                        $result = $NodeClone | Set-VMXDisplayName -DisplayName $NodeClone.CloneName
                        $MainMem = $NodeClone | Set-VMXMainMemory -usefile:$false
                        $Annotation = $Nodeclone | Set-VMXAnnotation -Line1 "Login Credentials" -Line2 "root" -Line3 "Password" -Line4 "VMware1!"
                        #$NodeClone | start-VMx | Out-Null
                        }
                    else
                        {
                        Write-Warning "Node $Nodeprefix$node already exists"
                        }
            
                }
                }
            }
            
            New-LabESXI @ESXI_param
            New-LabVCSA @VCSA_param
            New-LabScenario -ScenarioName LabVM7 -Builddir D:\Lab\Linked
            
            }). AddParameters($ParamList)

    
    $asynobject = $powershell.BeginInvoke()

    do
		{
            [System.Windows.Forms.Application]::DoEvents()
            write-host "..."
            [System.Windows.Forms.Application]::DoEvents()
        }
		until ($asynobject.IsCompleted -eq $true)

    $Button_Style = [MahApps.Metro.Controls.Dialogs.MetroDialogSettings]::new()
    $okAndCancel = [MahApps.Metro.Controls.Dialogs.MessageDialogStyle]::Affirmative  
    $result = [MahApps.Metro.Controls.Dialogs.DialogManager]::ShowModalMessageExternal($Form,"Create Lab","All masters for ESXI and VCSA have been created. Cool let's go ;)",$okAndCancel, $Button_Style)   
    New-Log -message "==> All is good in the folder $($WPF_Folder.Content) "

    $WPF_Create_L.IsEnabled = $true


})

$WPf_LabV.Add_Toggled({

if ($WPf_LabV.IsOn -eq $true){

new-log -message "==> The default Lab version is set to 7.x"
new-log -message "==> The Scenario name is set to LabVM7"

$WPF_Scenario.Content = "LabVM7"
$Script:ScenarioName = "LabVM7"

$WPF_VM_Size.SelectedItem -eq "XXL"

    $WPF_ESXICPUV.Content   = '4'
    $WPF_ESXIRAMV.Content   = '8 GB' 
    $WPF_VM_Size.SelectedIndex = 2

    New-Log -message "==> Set the Variable MasterName_ESXI to ESXIMaster7 VCSA to VCSAMaster7"
    $Script:Mastername_ESXI = "ESXIMaster7"
    $Script:Mastername_VCSA = "VCSAMaster7"

}
if ($WPf_LabV.IsOn -eq $false){

    new-log -message "==> The default Lab version is set to 6.x"
    new-log -message "==> The Scenario name is set to LabVM67"
    $WPF_Scenario.Content = "LabVM67"
    $Script:ScenarioName = "LabVM67"
    New-Log -message "==> Set the Variable MasterName_ESXI to ESXIMaster6.7 and VCSA to VCSAMaster6.7"

    $Script:Mastername_ESXI = "ESXIMaster6.7"
    $Script:Mastername_VCSA = "VCSAMaster6.7"

}

})
$WPF_iSCSI.Add_Toggled({
    
    if ($WPF_iSCSI.IsOn -eq $true){

        new-log -message "==> We want to use TrueNasCore for iSCSI"
        $WPF_TiSCSI.Visibility = "Visible"
        [MahApps.Metro.Controls.Dialogs.DialogManager]::ShowMessageAsync($Form, "Information", "We need the powershell module FreeNas 2.0.2. The script will install powershell module for you...")        
        if (Get-Module -ListAvailable -Name FreeNas) {
            
            new-log -message "==> The module FreeNas is already present"
        } 
        else {
            new-log -message "==> Module does not exist need to be installed"

            $PowerShell = [powershell]::Create()
    [void]$PowerShell.AddScript({
    install-module -Name FreeNas -Scope CurrentUser -Force
               
            })                   
            $PowerShell.Invoke()
            
            new-log -message "==> The Module FreeNas is installed in the CurrentUser Scope"
        }
    }
    if ($WPF_iSCSI.IsOn -eq $false){
    
        new-log -message "==> We don't want to use TrueNasCore for iSCSI"
        $WPF_TiSCSI.Visibility = "Collapsed"
    }
})

$WPF_Cloud.Add_Toggled({
    
    if ($WPF_Cloud.IsOn -eq $true){

        new-log -message "==> We want to deploy vOneCloud"
        $WPF_TvOneCloud.Visibility = "Visible"
        [MahApps.Metro.Controls.Dialogs.DialogManager]::ShowMessageAsync($Form, "Oups ;)", "This function in not implement yet ;)")        
    }
    if ($WPF_Cloud.IsOn -eq $false){
    
        new-log -message "==> We don't want to deploy vOneCloud"
        $WPF_TvOneCloud.Visibility = "Collapsed"
    }
})
$WPF_Scenario.Content = "LabVM67"
$Script:ScenarioName = "LabVM67"

$WPF_Set_Folder.Add_Click({

    Add-Type -AssemblyName System.Windows.Forms
    $MonDossier_Object = New-Object System.Windows.Forms.FolderBrowserDialog
    [void]$MonDossier_Object.ShowDialog()
    $Script:MonDossier = $MonDossier_Object.SelectedPath
    $Nom_Court = Split-Path -Leaf $MonDossier
    $WPF_Folder.Content = $Script:MonDossier
   
    New-Log -message "==> The default folder the lab is defined to $Mondossier"
   
    if (!(Test-Path $MonDossier\Linked)){
       
        New-Log -message "==> The folder Linked isn't presented need to be present"
        New-Item -Path $MonDossier -Name Linked -ItemType Directory | Out-Null
        New-Log -message "==> The folder Linked is created"

    }

    if (!(Test-Path $MonDossier\Masters)){
        
        New-Log -message "==> The folder Masters isn't presented need to be present"
        New-Item -Path $MonDossier -Name Masters -ItemType Directory | Out-Null
        New-Log -message "==> The folder Masters is created"
    }
})
$WPF_FindVM.Add_Click({
    
    $VMs = $null
    $VMs = get-VMX -Path $WPF_Folder.Content | Where-Object scenario -Match $Script:ScenarioName 

    if ($Null -eq $VMs){

        [MahApps.Metro.Controls.Dialogs.DialogManager]::ShowMessageAsync($Form, "Oups ;)", "the Folder is not define or we don't find any VM try again with different parameters ;)")        

    }
ForEach ($Item in $VMs)
{
    $Scenario = $Item.Scenario.Scenarioname
    $Data = New-Object PSObject
    $Data = $Data | Add-Member NoteProperty VMXName $Item.VMXName -passthru	
    $Data = $Data | Add-Member NoteProperty State $Item.State -passthru	
    $Data = $Data | Add-Member NoteProperty Scenario $Scenario -passthru	
    $Data = $Data | Add-Member NoteProperty Path $Item.Path -passthru
    $Data = $Data | Add-Member NoteProperty Config $Item.Config -passthru 	
    $WPF_VMFound.Items.Add($item) > $null						
}


})
$WPF_PlayVM.Add_Click({

    if ($WPF_VMFound.SelectedItems -ne $null){
        
        foreach ($item in $WPF_VMFound.SelectedItems) {
            
            new-log -message "==> Starting the VM $($Item.VMXName)"

            start-VMX -VMXName $Item.VMXName -config $item.Config 

        }

    }
    $WPF_VMFound.Items.Clear()
	$WPF_VMFound.Items.Refresh()
    $VMs = $null
    $VMs = get-VMX -Path $WPF_Folder.Content | Where-Object scenario -Match $Script:ScenarioName 
    
    new-log -message "==> Refresh the Status for VMs"

ForEach ($Item in $VMs)
{
    $Scenario = $Item.Scenario.Scenarioname
    $Data = New-Object PSObject
    $Data = $Data | Add-Member NoteProperty VMXName $Item.VMXName -passthru	
    $Data = $Data | Add-Member NoteProperty State $Item.State -passthru	
    $Data = $Data | Add-Member NoteProperty Scenario $Scenario -passthru	
    $Data = $Data | Add-Member NoteProperty Path $Item.Path -passthru
    $Data = $Data | Add-Member NoteProperty Config $Item.Config -passthru 	
    $WPF_VMFound.Items.Add($item) > $null						
}

})


$WPF_StopVM.Add_Click({

    if ($WPF_VMFound.SelectedItems -ne $null){
        
        foreach ($item in $WPF_VMFound.SelectedItems) {
            
            new-log -message "==> Stop the VM $($Item.VMXName)"

            Stop-VMX -VMXName $Item.VMXName -config $item.Config 

        }
    }
    $WPF_VMFound.Items.Clear()
	$WPF_VMFound.Items.Refresh()
    $VMs = $null
    $VMs = get-VMX -Path $WPF_Folder.Content | Where-Object scenario -Match $Script:ScenarioName 
    new-log -message "==> Refresh the Status for VMs"

ForEach ($Item in $VMs)
{
    $Scenario = $Item.Scenario.Scenarioname
    $Data = New-Object PSObject
    $Data = $Data | Add-Member NoteProperty VMXName $Item.VMXName -passthru	
    $Data = $Data | Add-Member NoteProperty State $Item.State -passthru	
    $Data = $Data | Add-Member NoteProperty Scenario $Scenario -passthru	
    $Data = $Data | Add-Member NoteProperty Path $Item.Path -passthru
    $Data = $Data | Add-Member NoteProperty Config $Item.Config -passthru 	
    $WPF_VMFound.Items.Add($item) > $null						
}

    
})
$windowcode = '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'
$asyncwindow = Add-Type -MemberDefinition $windowcode -name Win32ShowWindowAsync -namespace Win32Functions -PassThru
$null = $asyncwindow::ShowWindowAsync((Get-Process -PID $pid).MainWindowHandle, 0)
 
# Force garbage collection just to start slightly lower RAM usage.
[System.GC]::Collect()


$Form.ShowDialog() | Out-Null


