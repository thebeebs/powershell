if (Get-Module -Name 'AWSPowerShell.NetCore' -ListAvailable)
{
    Import-Module -Name 'AWSPowerShell.NetCore'
}
elseif (Get-Module -Name 'AWSPowerShell' -ListAvailable)
{
    Import-Module -Name 'AWSPowerShell'
}
else
{
    throw 'Please install an AWS PowerShell Module.'
}

# Deploy before talk
$global:DemoRoot = 'D:\Workspace\Speaking\PSSummitNA-2019\PowerShellOnAWS\Workspace'
$cfnPath = "$global:DemoRoot\CloudFormation"
$region = 'us-east-1'
Set-DefaultAWSRegion -Region $region

$s3BucketName = 'powershellsummit2019-us-east-1'

Set-Location -Path $cfnPath

# Command to retrieve .NET Core Linux AMI ID
# This needs manual updating insiding the CFN template for now.
(Get-EC2ImageByName -Name amzn2-ami-hvm-2.0.20180622.1-x86_64-gp2-dotnetcore-2019.04.09 -Region $region).ImageId | Set-ClipboardText

# Deploy the DSC Demo SpotFleet
$stackName = 'DSCDemoInstances'
dotnet lambda deploy-serverless $stackName --template ec2-spot-fleet.yml --region $region --s3-bucket $s3BucketName
