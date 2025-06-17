# This script is for querying SQL DBs for any rows with a certain column/value

$DB = "changeMe"
$Server = "server.domain.local"
$ColumnToFind = "columnName"
$ColumnToFindValue = "someVal"

$TableQuery = 'SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES'

$Tables = Invoke-Sqlcmd -ServerInstance $server -Database $DB -Query $TableQuery -TrustServerCertificate | Select-Object -ExpandProperty TABLE_NAME

$Tables2 = $Tables | Where-Object{($_ -like "*wage*") -or ($_ -like "*tax*")}

[object[]]$Results = $null

Foreach ($Table in $Tables){

    $ColumnQuery = "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = `'$Table`'"
    $Columns = Invoke-Sqlcmd -ServerInstance $Server -Database $DB -Query $ColumnQuery -TrustServerCertificate | Select-Object -ExpandProperty COLUMN_NAME
    
    #Query the table if it contains the column we are looking for
    if($ColumnToFind -in $Columns){
        $ResultQuery = "SELECT * FROM $Table WHERE $ColumnToFind = `'$ColumnToFindValue`'"
        $Result = Invoke-Sqlcmd -ServerInstance $Server -Database $DB -Query $ResultQuery -TrustServerCertificate 
    }
    $Results += $Result
}

$Results