$Title = "[Datastore] vSAN Config Maximum"
$Header = "[Datastore] vSAN Config Max - Components Per Host"
$Display = "Table"
$Author = "William Lam, Dario Doerflinger"
$PluginVersion = 1.3
$PluginCategory = "vSphere"

# Start of Settings
# Percentage threshold to warn?
$vsanWarningThreshold = 50
# End of Settings

# Update settings where there is an override
$vsanWarningThreshold = Get-vCheckSetting $Title "vsanWarningThreshold" $vsanWarningThreshold

# This config maximum is different for each version of VSAN, 3000 for 5.5
$vSANComponentMaximumMapping = @{
    "6.7.0"="9000"
    "6.5.0"="9000"
    "6.0.0"="9000"
    "5.5.0"="3000"
}

foreach ($cluster in $clusviews) {
    if ($cluster.ConfigurationEx.VsanConfigInfo.Enabled) {

        $vSANVersion = Get-VSANVersion -paramCluster $cluster
        $vSANVersionShort = [string]($vSANVersion.Version |Select-Object -Unique).split(" ")[0]

        if ($vSANComponentMaximumMapping.ContainsKey($vSANVersionShort)) {
            $vSANComponentMaximum = $vSANComponentMaximumMapping[$vSANVersionShort]
        } else {
            $vSANComponentMaximum = "3000"
        }

        foreach ($vmhost in ($cluster.Host) | Sort-Object -Property Name) {
            $vmhostView = Get-View $vmhost -Property Name, ConfigManager.VsanSystem, ConfigManager.VsanInternalSystem
            $vsanSys = Get-View -Id $vmhostView.ConfigManager.VsanSystem
            $vsanIntSys = Get-View -Id $vmhostView.ConfigManager.VsanInternalSystem

            $vsanProps = @("lsom_objects_count", "owner")
            $results = $vsanIntSys.QueryPhysicalVsanDisks($vsanProps)
            $vsanStatus = $vsanSys.QueryHostStatus()

            $componentCount = 0
            $json = $results | ConvertFrom-Json
            foreach ($line in $json | Get-Member) {
                # ensure component is owned by ESXi host
                if ($vsanStatus.NodeUuid -eq $json.$($line.Name).owner) {
                    $componentCount += $json.$($line.Name).lsom_objects_count
                }
            }
            $checkValue = [int]($componentCount / $vsanComponentMaximum * 100)

            if ($checkValue -gt $vsanWarningThreshold) {
                New-Object -TypeName PSObject -Property @{
                    "VMHost"         = $vmhostView.Name
                    "ComponentCount" = $componentCount 
                }
            }
        }
    }
}

$Comments = ("VSAN hosts approaching {0}% limit of {1} components per host. For more information please refer to Cormac Hogan's article <a href='http://cormachogan.com/2013/09/04/vsan-part-4-understanding-objects-and-components/' target='_blank'>Understanding Objects and Components</a>" -f $vsanWarningThreshold, $vsanComponentMaximum )

# Changelog
## 1.0 : Initial Release
## 1.1 : Fix indentation + using global $clusviews
## 1.2 : Add Get-vCheckSetting
## 1.3 : Added Component Maximum Selector
