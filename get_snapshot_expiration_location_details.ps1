$clusterInfo = Get-RubrikVersion
$clusterName = $clusterInfo.Name
$date = Get-Date -Format "yyyy-MM-dd"
$vms = Get-RubrikVM -PrimaryClusterID local

$vmresults = @()

foreach ($vm in $vms) {
    $snapshots = Get-RubrikSnapshot -id $vm.Id

    foreach ($snapshot in $snapshots) {
        $snapshotData = $snapshot | Select-Object @{
            Name = "Object Name"; Expression = {$vm.Name}
        }, id, date, @{
            Name = "Local Expiration Date"; Expression = {$snapshot.snapshotRetentionInfo.localInfo.ExpirationTime}
        }, @{
            Name = "Archival Expiration Date"; Expression = {$snapshot.snapshotRetentionInfo.archivalInfos.ExpirationTime}
        }, @{
            Name = "Hostname"; Expression = {$vm.ipAddress}
        },  @{
            Name = "slaName"; Expression = {$snapshot.slaName}
        }, @{
            Name = "ArchivalName"; Expression = {$snapshot.snapshotRetentionInfo.archivalInfos.name}
        }, @{
            Name = "Replication Cluster Name"; Expression = {$snapshot.snapshotRetentionInfo.replicationInfos.name}
        }, @{
            Name = "Replication Expiration Date"; Expression = {$snapshot.snapshotRetentionInfo.replicationInfos.ExpirationTime}
        }

        $vmresults += $snapshotData
    }
}




$databases = Get-RubrikDatabase
$dbresults = @()

foreach ($db in $databases) {
    $snapshots = Get-RubrikSnapshot -id $db.id

    foreach ($snapshot in $snapshots) {
        $snapshotData = $snapshot | Select-Object @{
            Name = "Object Name"; Expression = {$db.name}
        }, id, date, @{
            Name = "Local Expiration Date"; Expression = {$snapshot.snapshotRetentionInfo.localInfo.ExpirationTime}
        }, @{
            Name = "Archival Expiration Date"; Expression = {$snapshot.snapshotRetentionInfo.archivalInfos.ExpirationTime}
        }, @{
            Name = "Hostname"; Expression = {$db.rootProperties.rootName}
        },  @{
            Name = "slaName"; Expression = {$snapshot.slaName}
        }, @{
            Name = "ArchivalName"; Expression = {$snapshot.snapshotRetentionInfo.archivalInfos.name}
        }, @{
            Name = "Replication Cluster Name"; Expression = {$snapshot.snapshotRetentionInfo.replicationInfos.name}
        }, @{
            Name = "Replication Expiration Date"; Expression = {$snapshot.snapshotRetentionInfo.replicationInfos.ExpirationTime}
        }

        $dbresults += $snapshotData
    }
}

# Export to CSV
$vmresults | Export-Csv -Path "/Users/Aadil.Mir/Documents/Metlife/$($clusterName)_Virtual_Machines_$($date).csv" -NoTypeInformation
$dbresults | Export-Csv -Path "/Users/Aadil.Mir/Documents/Metlife/$($clusterName)_Databases_$($date).csv" -NoTypeInformation

