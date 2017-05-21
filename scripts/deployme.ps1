$scriptRoot = Split-Path ( Split-Path $MyInvocation.MyCommand.Path )

function Invoke-ArmDeployment {
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [guid]$subId,

        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 1)]
        [ValidateScript( {$_ -notmatch '\s+' -and $_ -match '[a-zA-Z0-9]+'})] 
        [string]$resourceGroupName,

        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 2)]
        [ValidateSet("Japan East", "East US 2", "West Europe", "Southeast Asia", "South Central US", "UK South", "West Central US", "North Europe", "Canada Central", "Australia Southeast", "Central India")] # limited to Azure Automation regions
        [string]$location,

        [Parameter(Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            Position = 3)]
        [ValidateSet("dev", "prod")]
        [string]$deploymentPrefix
    )

    $locationcoerced = $location.ToLower() -replace ' ', ''

    # Set proper subscription according to input and\or login to Azure and save token for further "deeds"
    Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  Login to your Azure account if prompted" -ForegroundColor DarkYellow
    Try {
        $null = Set-AzureRmContext -SubscriptionId $subId
    }
    Catch [System.Management.Automation.PSInvalidOperationException] {
        $ProfilePath = "$home\AzureCredProfile"
        if (Test-Path $ProfilePath -PathType Leaf) {
            Select-AzureRmProfile -path $ProfilePath
        }
        else {
            $null = Add-AzureRmAccount -SubscriptionId $subId
            $null = Set-AzureRmContext -SubscriptionId $subId
            $null = Save-AzureRmProfile -Path $ProfilePath
        }
    }
    if ($error[0].Exception.Message -in "Run Login-AzureRmAccount to login.", "Provided subscription $subId does not exist") {
        Write-Error "Login routine failed! Verify your subId"
        exit 1
    }
    try { 
        Do {
            $StorageAcct = $resourceGroupName + $deploymentPrefix + ( -join ((97..122) + (48..57) | Get-Random -Count 3 | ForEach-Object {[char]$_})) -replace "[^a-z0-9]"
            $availability = Get-AzureRmStorageAccountNameAvailability $StorageAcct
        } 
        while ( !$availability.NameAvailable )

        $components = @("application", "dmz", "security", "management", "operations", "networking")
        $resourceGroupNames = $components | ForEach-Object { New-AzureRmResourceGroup -Name (($resourceGroupName, $deploymentPrefix, $_) -join '-') -Location $location -Force }

        # !FIX ($data = get-deploymentData, but now it is empty)
        # Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  Starting $($data[0])" -ForegroundColor Green
        Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  Starting Deployment" -ForegroundColor Green
        #$result = New-AzureRmResourceGroupDeployment -TemplateFile "$scriptRoot\templates\vnets_peering.json" `#-TemplateParameterFile $data[1] `
        #    -Name $data[0] -ResourceGroupName $resourceGroupName -ErrorAction Stop -Verbose
        $result = New-AzureRmResourceGroupDeployment -TemplateFile "$scriptRoot\templates\resources\networking\azuredeploy.json" `
            -Name $(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss') -ResourceGroupName (($resourceGroupName, $deploymentPrefix, 'networking') -join '-') -ErrorAction Stop -Verbose

        # Write-Host "  Starting $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Green
        # $result = New-AzureRmResourceGroupDeployment -TemplateFile "$scriptRoot\templates\DMZ\DMZ.json"`
        #     -Name $(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss') -ResourceGroupName (($resourceGroupName, $deploymentPrefix, 'dmz') -join '-') -ErrorAction Stop -Verbose

        # Write-Host "  Starting $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Green
        # $result = New-AzureRmResourceGroupDeployment -TemplateFile "$scriptRoot\templates\Security\Security.json"`
        #     -Name $(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss') -ResourceGroupName (($resourceGroupName, $deploymentPrefix, 'Security') -join '-') -ErrorAction Stop -Verbose

        # $KeyVaultName = $resourceGroupName + $deploymentPrefix + ( -join ((97..122) + (48..57) | Get-Random -Count 20 | ForEach-Object {[char]$_}))
        # $parameters = @{
        #     "KeyVaultName" = $KeyVaultName
        #     "tenantid"     = (get-AzureRmContext).Tenant.TenantId
        # }
        # Write-Host "  Starting $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Green
        # $result = New-AzureRmResourceGroupDeployment -TemplateFile "$scriptRoot\templates\PAAS\PAAS.json"  -TemplateParameterObject $parameters `
        #     -Name $(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss') -ResourceGroupName (($resourceGroupName, $deploymentPrefix, 'operations') -join '-') -ErrorAction Stop -Verbose

        # Write-Host "  Starting $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Green
        # $result = New-AzureRmResourceGroupDeployment -TemplateFile "$scriptRoot\templates\management\management.json"`
        #     -Name $(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss') -ResourceGroupName (($resourceGroupName, $deploymentPrefix, 'management') -join '-') -ErrorAction Stop -Verbose
    }
    catch {
        Write-Error $_
        if ($env:destroy) {
            #Remove-Item $data[1]
            # remove all RG
            Invoke-DeleteResourceGroup -RGs $resourceGroupName            
        }
    }
}

function Get-DeploymentData {
    $tmp1 = [System.IO.Path]::GetTempFileName()
    $deploymentName = "{0}-deployment-{1}" -f $deploymentPrefix, (Get-Date -Format MMddyyyy)

    # parameters file transformations

    $deploymentName, $tmp1
}

# $AAAcct = New-AzureRmAutomationAccount -ResourceGroupName "$locationcoerced-automation" -Location $location -Name $StorageAcct -ErrorAction Stop

# # Get needed Powershell DSC modules and start upload to Azure Automation directly
# # from powershellgallery.com, need to get this list dynamically from DSC configuration
# $modules = Find-Module -Name NX, xPSDesiredStateConfiguration, xNetworking, xWebAdministration #, PSDscResources
# $modules | ForEach-Object {
#     $url = 'https://www.powershellgallery.com/api/v2/package/{0}/{1}' -f $_.Name, $_.Version
#     do {
#         $ActualUrl = $url
#         $Url = (Invoke-WebRequest -Uri $url -MaximumRedirection 0 -ErrorAction Ignore).Headers.Location 
#     } while ( $Url -ne $Null ) # finding actual module payload url

#     $null = New-AzureRmAutomationModule -ResourceGroupName  "$locationcoerced-automation" -AutomationAccountName $StorageAcct `
#         -Name $_.Name -ContentLink $ActualUrl -ErrorAction Stop
# }

# Get List of Files | ForEach-Object {
#     Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  Importing configuration `"$_`"" -ForegroundColor Green
#     $null = Import-AzureRmAutomationDscConfiguration -SourcePath "$scriptRoot\artifacts\$_" -Published -Force `
#         -ResourceGroupName "$locationcoerced-automation" -AutomationAccountName $StorageAcct -ErrorAction Stop
# }

# $StorageAccount = New-AzureRmStorageAccount -ResourceGroupName "$locationcoerced-automation" -Name $StorageAcct -Type Standard_LRS `
#     -Location $location -ErrorAction Stop # probably need to use one of the existing resource groups
# $keys = Get-AzureRmAutomationRegistrationInfo -ResourceGroupName "$locationcoerced-automation" `
#     -AutomationAccountName $StorageAcct -ErrorAction Stop
# $data = Get-DeploymentData
# $StorageAccount | New-AzureStorageContainer -Name payload -Permission Container | Out-Null
# Get-ChildItem $scriptRoot\nestedTemplates -Filter *.json | ForEach-Object {
#     $null = Set-AzureStorageBlobContent -Context $StorageAccount.Context -Container payload -File $_.FullName -ErrorAction Stop
# }

# $modules | ForEach-Object { 
#     do {
#         Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  Waiting for module import to succeed" -ForegroundColor DarkYellow; Start-Sleep 10
#         $uploadStatus = Get-AzureRmAutomationModule -ResourceGroupName "$locationcoerced-automation" -AutomationAccountName $StorageAcct `
#             -Name $_.Name -ErrorAction Stop                
#     } while ( $uploadStatus.ProvisioningState -notin 'Succeeded', 'Failed')
            
#     if ( $uploadStatus.ProvisioningState -eq 'Failed' ) {
#         Write-Error "Module upload failed."
#         exit 1
#     }
# }

# # check status before creating payload vms                
# $null = Start-AzureRmAutomationDscCompilationJob -ResourceGroupName "$locationcoerced-automation" -ConfigurationName 'Ubuntu' `
#     -AutomationAccountName $StorageAcct -ErrorAction Stop
# $null = Start-AzureRmAutomationDscCompilationJob -ResourceGroupName "$locationcoerced-automation" -ConfigurationName 'Windows' `
#     -AutomationAccountName $StorageAcct -ConfigurationData @{ AllNodes = @( @{ NodeName = "ssh"; Role = "BitVise" } ) } -ErrorAction Stop
# $null = Start-AzureRmAutomationDscCompilationJob -ResourceGroupName "$locationcoerced-automation" -ConfigurationName 'Windows' `
#     -AutomationAccountName $StorageAcct -ConfigurationData @{ AllNodes = @( @{ NodeName = "bastion"; Role = "Bastion" } ) } -ErrorAction Stop
# $null = Start-AzureRmAutomationDscCompilationJob -ResourceGroupName "$locationcoerced-automation" -ConfigurationName 'Windows' `
#     -AutomationAccountName $StorageAcct -ConfigurationData @{ AllNodes = @( @{ NodeName = "web"; Role = "IIS", "BitVise" } ) } -ErrorAction Stop