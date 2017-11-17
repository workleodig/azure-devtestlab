﻿<#
The MIT License (MIT)
Copyright (c) Microsoft Corporation  
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.  

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. 

.SYNOPSIS
This script adds the specified set of marketplace images to the list of allowed images in the specified lab
.PARAMETER DevTestLabName
The name of the lab.
.PARAMETER ImagesToAdd
The name(s) of the Marketplace Images to enable

#>

#Requires -Version 3.0
#Requires -Module AzureRM.Resources

param
(
    [Parameter(Mandatory=$true, HelpMessage="The name of the DevTest Lab to update")]
    [string] $DevTestLabName,

    [Parameter(Mandatory=$true, HelpMessage="The array of Marketplace Image names to enable")]
    $ImagesToAdd
)

$lab = Find-AzureRmResource -ResourceType 'Microsoft.DevTestLab/labs' | Where-Object {$_.Name -eq $DevTestLabName}

if(!$lab)
{
    throw "Lab named $DevTestLabName was not found"
}

$existingPolicy = (Get-AzureRmResource -ResourceType 'Microsoft.DevTestLab/labs/policySets/policies' -ResourceName ($lab.Name + '/default') -ResourceGroupName $lab.ResourceGroupName -ApiVersion 2016-05-15) | Where-Object {$_.Name -eq 'GalleryImage'}
if($existingPolicy)
{
    $existingImages = [Array] (ConvertFrom-Json $existingPolicy.Properties.threshold)
    $savePolicyChanges = $false
}
else
{
    $existingImages =  @()
    $savePolicyChanges = $true
}

if($existingPolicy.Properties.threshold -eq '[]')
{
    Write-Output "Skipping $($lab.Name) because it currently allows all marketplace images"
    return
}

$allAvailableImages = Get-AzureRmResource -ResourceType Microsoft.DevTestLab/labs/galleryImages -ResourceName $lab.Name -ResourceGroupName $lab.ResourceGroupName -ApiVersion 2017-04-26-preview
$finalImages = $existingImages

foreach($image in $ImagesToAdd)
{
    $imageObject = $allAvailableImages | Where-Object {$_.Name -eq $image}
        
    if(!$imageObject)
    {
        throw "Image $image is not available in the lab"
    }

    $addImage = $true
    $parsedAvailableImage = $imageObject.Properties.imageReference

    foreach($finalImage in $finalImages)
    {
        #determine whether or not the requested image is already allowed in this lab
        $parsedFinalImg = ConvertFrom-Json $finalImage

        if($parsedFinalImg.offer -eq $parsedAvailableImage.offer -and $parsedFinalImg.publisher -eq $parsedAvailableImage.publisher -and $parsedFinalImg.sku -eq $parsedAvailableImage.sku -and $parsedFinalImg.osType -eq $parsedAvailableImage.osType -and $parsedFinalImg.version -eq $parsedAvailableImage.version)
        {
            $addImage = $false
            break
        }
    }

    if($addImage)
    {
        Write-Output "  Adding image $image to the lab"
        $finalImages += ConvertTo-Json $parsedAvailableImage -Compress
        $savePolicyChanges = $true
    }
}

if($savePolicyChanges)
{
    $thresholdValue = '["'
    for($i = 0; $i -lt $finalImages.Length; $i++)
    {
        $value = $finalImages[$i]
        if($i -ne 0)
        {
            $thresholdValue = $thresholdValue + '","'
        }

        $thresholdValue = $thresholdValue + $value.Replace('"', '\"')
    }
    $thresholdValue = $thresholdValue + '"]'

    $policyObj = @{
        status = 'Enabled'
        factName = 'GalleryImage'
        threshold = $thresholdValue
        evaluatorType = 'AllowedValuesPolicy'
    }

    $resourceName = $lab.Name + '/default'
    $resourceType = "Microsoft.DevTestLab/labs/policySets/policies/galleryimage"
    if($existingPolicy)
    {
        #update the existing policy to include our images
        Write-Output "Updating $($lab.Name) Marketplace Images policy"
        Set-AzureRmResource -ResourceType $resourceType -ResourceName $resourceName -ResourceGroupName $lab.ResourceGroupName -ApiVersion 2017-04-26-preview -Properties $policyObj -Force
    }
    else
    {
        #create a new policy for the specified images
        Write-Output "Creating $($lab.Name) Marketplace Images policy"
        New-AzureRmResource -ResourceType $resourceType -ResourceName $resourceName -ResourceGroupName $lab.ResourceGroupName -ApiVersion 2017-04-26-preview -Properties $policyObj -Force
    }
}
else
{
    Write-Output ("No policy changes required for allowed Marketplace Images in lab " + $lab.Name)
}
