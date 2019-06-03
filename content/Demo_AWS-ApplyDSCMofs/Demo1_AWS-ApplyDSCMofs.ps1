<#

    AWS Systems Manager launched PowerShell DSC support in November 2018 via the document
    "AWS-ApplyDSCMofs".

    Supports standard DSC MOFs and integrates with AWS.

    - AWS Secrets Manager
    - AWS Systems Manager, Parameter Store
    - AWS Systems Manager, Compliance
    - Amazon S3


    DSC Configuration Features:

    1.  PSCredential Objects: At runtime evaluation of PSCredentials against AWS Secrets
        Manager or AWS Systems Manager Parameter Store.
        -> PSCredential Username = AWS ARN to the credential

    2.  Token Substitution: At runtime evaluation of tokens, with retrieval from Environment
        Variables, AWS Systems Manager Parameter Store, EC2 Tags or Managed Instance Tags.
        
        Token notation supports:
          - tag     Amazon EC2 or managed instance tags.
          - tag64   Same as "tag", but the value is base64 encoded.
          - env     Environment variables.
          - ssm     Parameter Store values. Supports String or SecureString types.
          - tagssm  Same as "tag", but reverts to Parameter Store if no tag is set. Allows 
                    "ssm" override with a "tag"

        For example:
          - '{env:SystemDrive}'
          - '{ssm:ParameterStoreItem}'

    Links:
    Maintain DSC and Report Compliance of Windows Instances using AWS Systems Manager
    2018-11-15: https://aws.amazon.com/about-aws/whats-new/2018/11/maintain-desired-state-configuration-and-report-compliance-of-windows-instances-using-aws-systems-manager-and-powershell-dsc/

    Creating Associations that Run MOF Files:
    https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-state-manager-using-mof-file.html

    Launch Blog:
    https://aws.amazon.com/blogs/mt/run-compliance-enforcement-and-view-compliant-and-non-compliant-instances-using-aws-systems-manager-and-powershell-dsc/

    Samples Gist:
    https://gist.github.com/austoonz/14ad194db6e55dcee96bf97ea07adb45

#>

# Setup
$filePath = "$global:DemoRoot\Demo_AWS-ApplyDSCMofs"
Set-Location -Path $filePath

Import-Module -Name AWSPowerShell
Set-DefaultAWSRegion -Region 'us-east-1'
Clear-Host

# Useful links

# Lets go and evaluate the target machines using AWS Session Manager
Get-LocalUser -Name 'DSCDemoUser'
Get-ChildItem -Path "$env:SystemDrive\AWS" | ForEach-Object {
    Write-Host ('File:    "{0}"' -f $_.FullName)
    Write-Host ('Content: "{0}"' -f (Get-Content -Path $_.FullName))
    ''
}


# Create a PSCredential Object and save to AWS Secrets Manager
$localUserCredential = Get-Credential -UserName 'DemoLocalUser' -Message 'Enter a new password'

try
{
    $secret = Get-SECSecret -SecretId 'DSCDemoUser'
    $null = Update-SECSecret -SecretId $secret.ARN -SecretString (ConvertTo-Json -InputObject @{
        Username = $localUserCredential.UserName
        Password = $localUserCredential.GetNetworkCredential().Password
    })
}
catch
{
    $null = New-SECSecret -Name 'DSCDemoUser' -SecretString (ConvertTo-Json -InputObject @{
        Username = $localUserCredential.UserName
        Password = $localUserCredential.GetNetworkCredential().Password
    })
}
$secretArn = (Get-SECSecret -SecretId 'DSCDemoUser').ARN

# Create a Systems Manager Parameter to retrieve
$splat = @{
    Name        = 'DSCDemoParameter'
    Value       = 'Hello PowerShell Summit!'
    Description = 'Testing DSC Integration with Parameter Store'
    Type        = 'String'
    Overwrite   = $true
}
Write-SSMParameter @splat

# Create the DSC Configuration
configuration DSCDemo {
    param ( [String] $SecretArn )

    Import-DscResource -ModuleName PSDesiredStateConfiguration

    node localhost {
        File CreateFolder {
            DestinationPath = '{env:SystemDrive}\AWS'
            Type            = 'Directory'
        }

        File CreateEnvironmentFile {
            DestinationPath = '{env:SystemDrive}\AWS\{tag:Environment}.txt'
            Type            = 'File'
            Contents        = '{ssm:DSCDemoParameter}'
        }

        $ss = ConvertTo-SecureString -String 'This is ignored!' -AsPlaintext -Force
        $credential = [PSCredential]::New($SecretArn, $ss)
        
        User DSCDemoUser {
            UserName    = 'DSCDemoUser'
            Description = 'This is a local user created by DSC on AWS'
            Ensure      = 'Present'
            FullName    = 'DSC Demo User'
            Password    = $credential
        }
    }
}


# Configuration Data for plain text passwords
$configData = @{
    AllNodes = @(
        @{
            NodeName                    = 'localhost'
            PSDscAllowPlainTextPassword = $true
        }
    )
}


# Generate the MOF
$mofFile = DSCDemo -SecretArn $secretArn -ConfigurationData $configData

# Write the MOF to S3
$bucketName = 'powershellsummit2019-us-east-1'
$mofKey = 'MOFs/DSCDemo.mof'

$writeS3Object = @{
    BucketName = $bucketName
    Key = $mofKey
    File = $mofFile.FullName
}
Write-S3Object @writeS3Object

# Create the Systems Manager Association
$associationName = 'DSCDemo'
$newSSMAssociation = @{
    AssociationName = $associationName
    Name = 'AWS-ApplyDSCMofs' # For reference, this is "DocumentName" on Send-SSMCommand
    Target = @(
        @{
            Key = 'tag:Name'
            Values = @( 'DSCDemo' )
        }
    )
    Parameter = @{
        MofsToApply = 's3:{0}:{1}' -f $bucketName, $mofKey
        ServicePath = 'dscdemo'
        MofOperationMode = 'Apply'
        ReportBucketName = 'dscdemo-report-bucket'
        StatusBucketName = 'dscdemo-status-bucket'
        ModuleSourceBucketName = 'NONE'
        AllowPSGalleryModuleSource = 'False'
        RebootBehavior = 'AfterMof'
        UseComputerNameForReporting = 'False'
        EnableVerboseLogging = 'True'
        EnableDebugLogging = 'False'
        ComplianceType = 'Custom:DSCDemo'
        PreRebootScript = ''
    }
    S3Location_OutputS3BucketName = 'dscdemo-ssmoutput-bucket'
    S3Location_OutputS3KeyPrefix = 'dscdemo'
    MaxConcurrency = 2
    MaxError = 1
    ScheduleExpression = 'cron(0/30 * * * ? *)'
}
$associationId = (Get-SSMAssociationList | Where-Object {$_.AssociationName -eq $associationName}).AssociationId
if ($associationId) {Remove-SSMAssociation -Name $associationName -AssociationId $associationId -Force}

New-SSMAssociation @newSSMAssociation

# Lets go and evaluate the target machines again...
Get-LocalUser -Name 'DSCDemoUser'
Get-ChildItem -Path "$env:SystemDrive\AWS" | ForEach-Object {
    Write-Host ('File:    "{0}"' -f $_.FullName)
    Write-Host ('Content: "{0}"' -f (Get-Content -Path $_.FullName))
    ''
}
