# Default Configurations
$global:demoroot = 'D:\PoshSummit2019\PowerShellOnAWS'
$global:s3BucketName = 'powershellsummit2019-us-east-1'

Set-Location -Path $global:demoroot

Import-Module -Name 'AWSPowerShell'
Set-DefaultAWSRegion -Region 'us-east-1'

# Deploy before talk
$cfnPath = 'D:\PoshSummit2019\PowerShellOnAWS\CloudFormation'
Set-Location -Path $cfnPath
$region = 'us-east-1'

# S3 Buckets
@(
    'dscdemo-report-bucket',
    'dscdemo-status-bucket',
    'dscdemo-ssmoutput-bucket'
) | ForEach-Object {
    $null = New-S3Bucket -BucketName $_
}

# Deploy the VPC
$stackName = 'VPC'
dotnet lambda deploy-serverless $stackName --template vpc.yml --region $region --s3-bucket $global:s3BucketName

# Deploy the DSC Demo SpotFleet
$stackName = 'DSCDemoInstances'
dotnet lambda deploy-serverless $stackName --template ec2-spot-fleet.yml --region $region --s3-bucket $global:s3BucketName
