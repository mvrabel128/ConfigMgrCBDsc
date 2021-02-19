$script:dscResourceCommonPath = Join-Path (Join-Path -Path (Split-Path -Parent -Path (Split-Path -Parent -Path $PsScriptRoot)) -ChildPath Modules) -ChildPath DscResource.Common
$script:configMgrResourcehelper = Join-Path (Join-Path -Path (Split-Path -Parent -Path (Split-Path -Parent -Path $PsScriptRoot)) -ChildPath Modules) -ChildPath ConfigMgrCBDsc.ResourceHelper

Import-Module -Name $script:dscResourceCommonPath
Import-Module -Name $script:configMgrResourcehelper

$script:localizedData = Get-LocalizedData -DefaultUICulture 'en-US'

<#
    .SYNOPSIS
        This will return a hashtable of results.

    .PARAMETER SiteCode
        Specifies the site code for Configuration Manager site.

    .PARAMETER CollectionName
        Specifies a name for the collection.

    .PARAMETER CollectionType
        Specifies the type of collection. Valid values are User and Device.
        Not used in Get-TargetResource.
#>
function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [String]
        $SiteCode,

        [Parameter(Mandatory = $true)]
        [String]
        $CollectionName,

        [Parameter(Mandatory = $true)]
        [ValidateSet('User','Device')]
        [String]
        $CollectionType
    )

    Write-Verbose -Message $script:localizedData.RetrieveSettingValue
    Import-ConfigMgrPowerShellModule -SiteCode $SiteCode
    Set-Location -Path "$($SiteCode):\"

    $collection = Get-CMCollection -Name $CollectionName

    if ($collection)
    {
        $refresh = switch ($collection.RefreshType)
        {
            '1' { 'Manual' }
            '2' { 'Periodic' }
            '4' { 'Continuous' }
            '6' { 'Both' }
        }

        $type = switch ($collection.CollectionType)
        {
            '1' { 'User' }
            '2' { 'Device' }
        }

        if ($type -eq 'User')
        {
            $rules = Get-CMUserCollectionQueryMembershipRule -CollectionName $collection.Name | Select-Object QueryExpression, RuleName
            [array]$excludes = (Get-CMUserCollectionExcludeMembershipRule -CollectionName $collection.Name).RuleName
            [array]$directMember = (Get-CMUserCollectionDirectMembershipRule -CollectionName $collection.Name).RuleName
            [array]$directMemberId = (Get-CMUserCollectionDirectMembershipRule -CollectionName $collection.Name).ResourceID
            [array]$includeMember = (Get-CMUserCollectionIncludeMembershipRule -CollectionName $collection.Name).RuleName
        }
        else
        {
            $rules = Get-CMDeviceCollectionQueryMembershipRule -CollectionName $collection.Name | Select-Object QueryExpression, RuleName
            [array]$excludes = (Get-CMDeviceCollectionExcludeMembershipRule -CollectionName $collection.Name).RuleName
            [array]$directMember = (Get-CMDeviceCollectionDirectMembershipRule -CollectionName $collection.Name).RuleName
            [array]$directMemberId = (Get-CMDeviceCollectionDirectMembershipRule -CollectionName $collection.Name).ResourceID
            [array]$includeMember = (Get-CMDeviceCollectionIncludeMembershipRule -CollectionName $collection.Name).RuleName
        }

        if ($collection.RefreshType -eq 2 -or $collection.RefreshType -eq 6)
        {
            $cSchedule = $collection.RefreshSchedule

            if ($cSchedule.DaySpan -gt 0)
            {
                $rInterval = 'Days'
                $rCount = $cSchedule.DaySpan
            }
            elseif ($cSchedule.HourSpan -gt 0)
            {
                $rInterval = 'Hours'
                $rCount = $cSchedule.HourSpan
            }
            elseif ($cSchedule.MinuteSpan -gt 0)
            {
                $rInterval = 'Minutes'
                $rCount = $cSchedule.MinuteSpan
            }
            else
            {
                $rInterval = 'None'
            }
        }

        if ($rules)
        {
            $cimCollection = New-Object -TypeName 'System.Collections.ObjectModel.Collection`1[Microsoft.Management.Infrastructure.CimInstance]'

            foreach ($rule in $rules)
            {
                $cimcollection += (New-CimInstance -ClassName DSC_CMCollectionQueryRules -Property @{
                    QueryExpression = $rule.QueryExpression
                    RuleName        = $rule.RuleName
                } -ClientOnly -Namespace 'root/microsoft/Windows/DesiredStateConfiguration')
            }
        }

        $status = 'Present'
    }
    else
    {
        $status = 'Absent'
    }

    return @{
        SiteCode               = $SiteCode
        CollectionName         = $CollectionName
        Comment                = $collection.Comment
        CollectionType         = $type
        LimitingCollectionName = $collection.LimitToCollectionName
        ScheduleInterval       = $rInterval
        ScheduleCount          = $rCount
        RefreshType            = $refresh
        QueryRules             = $cimcollection
        ExcludeMembership      = $excludes
        DirectMembership       = $directMember
        DirectMembershipId     = $directMemberId
        IncludeMembership      = $includeMember
        Ensure                 = $status
    }
}

<#
    .SYNOPSIS
        This will set the desired state.

    .PARAMETER SiteCode
        Specifies the site code for Configuration Manager site.

    .PARAMETER CollectionName
        Specifies a name for the collection.

    .PARAMETER CollectionType
        Specifies the type of collection. Valid values are User and Device.

    .PARAMETER LimitingCollectionName
        Specifies the name of a collection to use as the default scope for this collection.

    .PARAMETER Comment
        Specifies a comment for the collection.

    .PARAMETER ScheduleInterval
        Specifies the time when the scheduled event recurs none, minutes, hours and days.

    .PARAMETER ScheduleCount
        Specifies how often the recur interval is run. If hours are specified the max value
        is 23. Anything over 23 will result in 23 to be set. If days are specified the max value
        is 31. Anything over 31 will result in 31 to be set.

    .PARAMETER RefreshType
        Specifies how Configuration Manager refreshes the collection.
        Valid values are: Manual, Periodic, Continuous, and Both.

    .PARAMETER ExcludeMembership
        Specifies the collection name to exclude clients from. If clients are in the excluded collection they will
        not be added to the collection.

    .PARAMETER IncludeMembership
        Specifies the collection name to include clients from. Only clients from the included
        collections can be added to the collection.

    .PARAMETER DirectMembership
        Specifies the resourceid or name for the direct membership rule.

    .PARAMETER QueryRules
        Specifies the name of the rule and the query expression that Configuration Manager uses to update collections.

    .PARAMETER Ensure
        Specifies if the collection is to be present or absent.
#>
function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [String]
        $SiteCode,

        [Parameter(Mandatory = $true)]
        [String]
        $CollectionName,

        [Parameter(Mandatory = $true)]
        [ValidateSet('User','Device')]
        [String]
        $CollectionType,

        [Parameter()]
        [String]
        $LimitingCollectionName,

        [Parameter()]
        [String]
        $Comment,

        [Parameter()]
        [ValidateSet('None','Minutes','Hours','Days')]
        [String]
        $ScheduleInterval,

        [Parameter()]
        [UInt32]
        $ScheduleCount,

        [Parameter()]
        [ValidateSet('Manual','Periodic','Continuous','Both')]
        [String]
        $RefreshType,

        [Parameter()]
        [String[]]
        $ExcludeMembership,

        [Parameter()]
        [String[]]
        $IncludeMembership,

        [Parameter()]
        [String[]]
        $DirectMembership,

        [Parameter()]
        [Microsoft.Management.Infrastructure.CimInstance[]]
        $QueryRules,

        [Parameter()]
        [ValidateSet('Present','Absent')]
        [String]
        $Ensure = 'Present'
    )

    Import-ConfigMgrPowerShellModule -SiteCode $SiteCode
    Set-Location -Path "$($SiteCode):\"

    try
    {
        $state = Get-TargetResource -SiteCode $SiteCode -CollectionName $CollectionName -CollectionType $CollectionType

        if ((-not [string]::IsNullOrEmpty($state.CollectionType)) -and ($state.CollectionType -ne $CollectionType))
        {
            throw ($script:localizedData.CollectionType -f $CollectionType, $state.CollectionType)
        }

        if ($PSBoundParameters.ContainsKey('ExcludeMembership') -and $PSBoundParameters.ContainsKey('IncludeMembership'))
        {
            foreach ($exclude in $ExcludeMembership)
            {
                if ($IncludeMembership -contains $exclude)
                {
                    throw ($script:localizedData.RuleConflict -f $exclude)
                }
            }
        }

        if (($PSBoundParameters.ContainsKey('ScheduleInterval')) -and ($ScheduleInterval -ne 'None' -and
            -not $PSBoundParameters.ContainsKey('ScheduleCount')))
        {
            throw $script:localizedData.IntervalCount
        }

        if ($Ensure -eq 'Present')
        {
            if ($state.Ensure -eq 'Absent')
            {
                if ([string]::IsNullOrEmpty($LimitingCollectionName))
                {
                    throw $script:localizedData.MissingLimiting
                }

                Write-Verbose -Message ($script:localizedData.CollectionCreate -f $CollectionName)

                $newCollection = @{
                    Name                   = $CollectionName
                    CollectionType         = $CollectionType
                    LimitingCollectionName = $LimitingCollectionName
                }

                New-CMCollection @newCollection
            }

            $buildingParams = @{
                Name = $CollectionName
            }

            if ([string]::IsNullOrEmpty($newCollection))
            {
                $paramsToCheck = @('Comment','RefreshType','LimitingCollectionName')
            }
            else
            {
                $paramsToCheck = @('Comment','RefreshType')
            }

            foreach ($param in $PSBoundParameters.GetEnumerator())
            {
                if ($paramsToCheck -contains $param.Key)
                {
                    if ($param.Value -ne $state[$param.Key])
                    {
                        Write-Verbose -Message ($script:localizedData.CollectionSetting -f $CollectionName, `
                                                $param.Key, $param.Value, $state[$param.Key])
                        $buildingParams += @{
                            $param.Key = $param.Value
                        }
                    }
                }
            }

            if (-not [string]::IsNullOrEmpty($ScheduleInterval))
            {
                if ((($PSBoundParameters.ContainsKey('RefreshType')) -and ($RefreshType -eq 'Periodic' -or $RefreshType -eq 'Both')) -or
                    (([string]::IsNullOrEmpty($RefreshType)) -and ($state.RefreshType -eq 'Periodic' -or $state.RefreshType -eq 'Both')))
                {
                    if ($ScheduleInterval -ne $state.ScheduleInterval)
                    {
                        Write-Verbose -Message ($script:localizedData.SIntervalTest -f $ScheduleInterval, $state.ScheduleInterval)
                        $setSchedule = $true
                    }

                    if ($ScheduleInterval -ne 'None')
                    {
                        if ($ScheduleInterval -eq 'Days' -and $ScheduleCount -ge 32)
                        {
                            Write-Warning -Message ($script:localizedData.MaxIntervalDays -f $ScheduleCount)
                            $scheduleCheck = 31
                        }
                        elseif ($ScheduleInterval -eq 'Hours' -and $ScheduleCount -ge 24)
                        {
                            Write-Warning -Message ($script:localizedData.MaxIntervalHours -f $ScheduleCount)
                            $scheduleCheck = 23
                        }
                        elseif ($ScheduleInterval -eq 'Minutes' -and $ScheduleCount -ge 60)
                        {
                            Write-Warning -Message ($script:localizedData.MaxIntervalMins -f $ScheduleCount)
                            $scheduleCheck = 59
                        }
                        else
                        {
                            $scheduleCheck = $ScheduleCount
                        }

                        if ($scheduleCheck -ne $state.ScheduleCount)
                        {
                            Write-Verbose -Message ($script:localizedData.SCountTest -f $scheduleCheck, $state.ScheduleCount)
                            $setSchedule = $true
                        }
                    }

                    if ($setSchedule -eq $true)
                    {
                        if ($ScheduleInterval -eq 'None')
                        {
                            $pschedule = New-CMSchedule -Nonrecurring
                        }
                        else
                        {
                            $pScheduleSet = @{
                                RecurInterval = $ScheduleInterval
                                RecurCount    = $scheduleCheck
                            }

                            $pschedule = New-CMSchedule @pScheduleSet
                        }

                        $buildingParams += @{
                            RefreshSchedule = $pSchedule
                        }
                    }
                }
                else
                {
                    Write-Warning -Message $script:localizedData.ScheduleType
                }
            }

            if ($buildingParams.Count -gt 1)
            {
                Set-CMCollection @buildingParams
            }

            if (-not [string]::IsNullOrEmpty($ExcludeMembership))
            {
                foreach ($member in $ExcludeMembership)
                {
                    $excludeRule = @{}

                    if (([string]::IsNullOrEmpty($state.ExcludeMembership)) -or ($state.ExcludeMembership -notcontains $member))
                    {
                        if ($state.IncludeMembership -contains $member -or $state.QueryRules.RuleName -contains $member -or
                            $state.DirectMembership -contains $member)
                        {
                            [array]$errorMsg += ($script:localizedData.ExcludeError -f $member)
                        }
                        else
                        {
                            $excludeRule = @{
                                CollectionName        = $CollectionName
                                ExcludeCollectionName = $member
                            }

                            Write-Verbose -Message ($script:localizedData.ExcludeMemberRule -f $CollectionName, $member)

                            if ((Get-CMCollection -Name $member))
                            {
                                if ($CollectionType -eq 'User')
                                {
                                    Add-CMUserCollectionExcludeMembershipRule @excludeRule
                                }
                                else
                                {
                                    Add-CMDeviceCollectionExcludeMembershipRule @excludeRule
                                }
                            }
                            else
                            {
                                [array]$errorMsg += ($script:localizedData.ExcludeNonAdd -f $member)
                            }
                        }
                    }
                }
            }

            if (-not [string]::IsNullOrEmpty($IncludeMembership))
            {
                foreach ($member in $IncludeMembership)
                {
                    $includeRule = @{}

                    if (([string]::IsNullOrEmpty($state.IncludeMembership)) -or ($state.IncludeMembership -notcontains $member))
                    {
                        if ($state.ExcludeMembership -contains $member -or $state.QueryRules.RuleName -contains $member -or
                            $state.DirectMembership -contains $member)
                        {
                            [array]$errorMsg += ($script:localizedData.IncludeError -f $member)
                        }
                        else
                        {
                            $includeRule = @{
                                CollectionName        = $CollectionName
                                IncludeCollectionName = $member
                            }

                            Write-Verbose -Message ($script:localizedData.IncludeMemberRule -f $CollectionName, $member)

                            if (Get-CMCollection -Name $member -CollectionType $CollectionType)
                            {
                                if ($CollectionType -eq 'User')
                                {
                                    Add-CMUserCollectionIncludeMembershipRule @includeRule
                                }
                                else
                                {
                                    Add-CMDeviceCollectionIncludeMembershipRule @includeRule
                                }
                            }
                            else
                            {
                                [array]$errorMsg += ($script:localizedData.IncludeNonAdd -f $member)
                            }
                        }
                    }
                }
            }

            if (-not [string]::IsNullOrEmpty($DirectMembership))
            {
                foreach ($member in $DirectMembership)
                {
                    if ((-not [string]::IsNullOrEmpty($member)) -and ([string]::IsNullOrEmpty($state.DirectMembership) -or
                        $state.DirectMembership -notcontains $member) -and ([string]::IsNullOrEmpty($state.DirectMembershipId) -or
                        $state.DirectMembershipId -notcontains $member))
                    {
                        $directRule = @{}

                        if ($member -match "^\d+$")
                        {
                            $clientName = (Get-CMResource -ResourceId $member -Fast).Name

                            if ($clientName)
                            {
                                if ($DirectMembership -contains $clientName)
                                {
                                    [array]$errorMsg += ($script:localizedData.DirectConflict -f $member, $clientName)
                                }
                                else
                                {
                                    $directRule = @{
                                        CollectionName = $CollectionName
                                        ResourceId     = $member
                                    }
                                }
                            }
                            else
                            {
                                [array]$errorMsg += ($script:localizedData.InvalidId -f $member)
                            }
                        }
                        else
                        {
                            if ($CollectionType -eq 'User')
                            {
                                $resourceID = Get-CMUser -Name $member

                                if ($resourceID)
                                {
                                    $directRule = @{
                                        CollectionName = $CollectionName
                                        ResourceId     = $resourceID.ResourceId
                                    }
                                }
                                else
                                {
                                    [array]$errorMsg += ($script:localizedData.DirectNonAdd -f $member)
                                }
                            }
                            else
                            {
                                $resourceID = Get-CMDevice -Name $member

                                if ($resourceID)
                                {
                                    $directRule = @{
                                        CollectionName = $CollectionName
                                        ResourceId     = $resourceID.ResourceId
                                    }
                                }
                                else
                                {
                                    [array]$errorMsg += ($script:localizedData.DirectNonAdd -f $member)
                                }
                            }
                        }

                        if ($directRule.Count -ge 1)
                        {
                            Write-Verbose -Message ($script:localizedData.DirectMemberRule -f $CollectionName, $member)

                            if ($CollectionType -eq 'User')
                            {
                                Add-CMUserCollectionDirectMembershipRule @directRule
                            }
                            else
                            {
                                Add-CMDeviceCollectionDirectMembershipRule @directRule
                            }
                        }
                    }
                }
            }

            if (-not [string]::IsNullOrEmpty($QueryRules))
            {
                foreach ($rule in $QueryRules)
                {
                    $importRule = @{}

                    if (($null -eq $state.QueryRules) -or
                        ($state.QueryRules.QueryExpression.Replace(' ','') -notcontains $rule.QueryExpression.Replace(' ','')))
                    {
                        Write-Verbose -Message ($script:localizedData.QueryRule -f $CollectionName, $($rule.QueryExpression))

                        $importRule = @{
                            CollectionName  = $CollectionName
                            RuleName        = $rule.RuleName
                            QueryExpression = $rule.QueryExpression
                        }

                        if ($CollectionType -eq 'User')
                        {
                            Add-CMUserCollectionQueryMembershipRule @importRule
                        }
                        else
                        {
                            Add-CMDeviceCollectionQueryMembershipRule @importRule
                        }
                    }
                }
            }
        }
        else
        {
            if ($state.Ensure -eq 'Present')
            {
                Write-Verbose -Message ($script:localizedData.RemoveCollection -f $CollectionName)
                Remove-CMCollection -Name $CollectionName
            }
        }

        if ($errorMsg)
        {
            throw $errorMsg
        }
    }
    catch
    {
        throw $_
    }
    finally
    {
        Set-Location -Path "$env:temp"
    }
}

<#
    .SYNOPSIS
        This will test the desired state.

    .PARAMETER SiteCode
        Specifies the site code for Configuration Manager site.

    .PARAMETER CollectionName
        Specifies a name for the collection.

    .PARAMETER CollectionType
        Specifies the type of collection. Valid values are User and Device.

    .PARAMETER LimitingCollectionName
        Specifies the name of a collection to use as the default scope for this collection.

    .PARAMETER Comment
        Specifies a comment for the collection.

    .PARAMETER ScheduleInterval
        Specifies the time when the scheduled event recurs none, minutes, hours and days.

    .PARAMETER ScheduleCount
        Specifies how often the recur interval is run. If hours are specified the max value
        is 23. Anything over 23 will result in 23 to be set. If days are specified the max value
        is 31. Anything over 31 will result in 31 to be set.

    .PARAMETER RefreshType
        Specifies how Configuration Manager refreshes the collection.
        Valid values are: Manual, Periodic, Continuous, and Both.

    .PARAMETER ExcludeMembership
        Specifies the collection name to exclude clients from. If clients are in the excluded collection they will
        not be added to the collection.

    .PARAMETER IncludeMembership
        Specifies the collection name to include clients from. Only clients from the included
        collections can be added to the collection.

    .PARAMETER DirectMembership
        Specifies the resourceid or name for the direct membership rule.

    .PARAMETER QueryRules
        Specifies the name of the rule and the query expression that Configuration Manager uses to update collections.

    .PARAMETER Ensure
        Specifies if the collection is to be present or absent.
#>
function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [String]
        $SiteCode,

        [Parameter(Mandatory = $true)]
        [String]
        $CollectionName,

        [Parameter(Mandatory = $true)]
        [ValidateSet('User','Device')]
        [String]
        $CollectionType,

        [Parameter()]
        [String]
        $LimitingCollectionName,

        [Parameter()]
        [String]
        $Comment,

        [Parameter()]
        [ValidateSet('None','Minutes','Hours','Days')]
        [String]
        $ScheduleInterval,

        [Parameter()]
        [UInt32]
        $ScheduleCount,

        [Parameter()]
        [ValidateSet('Manual','Periodic','Continuous','Both')]
        [String]
        $RefreshType,

        [Parameter()]
        [String[]]
        $ExcludeMembership,

        [Parameter()]
        [String[]]
        $IncludeMembership,

        [Parameter()]
        [String[]]
        $DirectMembership,

        [Parameter()]
        [Microsoft.Management.Infrastructure.CimInstance[]]
        $QueryRules,

        [Parameter()]
        [ValidateSet('Present','Absent')]
        [String]
        $Ensure = 'Present'
    )

    Import-ConfigMgrPowerShellModule -SiteCode $SiteCode
    Set-Location -Path "$($SiteCode):\"
    $state = Get-TargetResource -SiteCode $SiteCode -CollectionName $CollectionName -CollectionType $CollectionType
    $result = $true

    if ($Ensure -eq 'Present')
    {
        if ($state.Ensure -eq 'Absent')
        {
            if ([string]::IsNullOrEmpty($LimitingCollectionName))
            {
                Write-Warning -Message $script:localizedData.MissingLimiting
            }

            Write-Verbose -Message ($script:localizedData.CollectionAbsent -f $CollectionName)
            $result = $false
        }
        else
        {
            $testParams = @{
                CurrentValues = $state
                DesiredValues = $PSBoundParameters
                ValuesToCheck = @('Comment','RefreshType','LimitingCollectionName')
            }

            $result = Test-DscParameterState @testParams -TurnOffTypeChecking -Verbose

            if ($state.CollectionType -ne $CollectionType)
            {
                Write-Warning -Message ($script:localizedData.CollectionType -f $CollectionType, $state.CollectionType)
                $result = $false
            }

            if ($PSBoundParameters.ContainsKey('ExcludeMembership') -and $PSBoundParameters.ContainsKey('IncludeMembership'))
            {
                foreach ($exclude in $ExcludeMembership)
                {
                    if ($IncludeMembership -contains $exclude)
                    {
                        Write-Warning -Message ($script:localizedData.RuleConflict -f $exclude)
                    }
                }
            }

            if ($PSBoundParameters.ContainsKey('ScheduleInterval'))
            {
                if ((($PSBoundParameters.ContainsKey('RefreshType')) -and ($RefreshType -eq 'Periodic' -or $RefreshType -eq 'Both')) -or
                    (([string]::IsNullOrEmpty($RefreshType)) -and ($state.RefreshType -eq 'Periodic' -or $state.RefreshType -eq 'Both')))
                {
                    if ($ScheduleInterval -ne 'None' -and -not $PSBoundParameters.ContainsKey('ScheduleCount'))
                    {
                        Write-Warning -Message $script:localizedData.IntervalCount
                        $result = $false
                    }
                    else
                    {
                        if ($ScheduleInterval -ne $state.ScheduleInterval)
                        {
                            Write-Verbose -Message ($script:localizedData.SIntervalTest -f $ScheduleInterval, $state.ScheduleInterval)
                            $result = $false
                        }

                        if ($ScheduleInterval -ne 'None')
                        {
                            if ($ScheduleInterval -eq 'Days' -and $ScheduleCount -ge 32)
                            {
                                Write-Warning -Message ($script:localizedData.MaxIntervalDays -f $ScheduleCount)
                                $scheduleCheck = 31
                            }
                            elseif ($ScheduleInterval -eq 'Hours' -and $ScheduleCount -ge 24)
                            {
                                Write-Warning -Message ($script:localizedData.MaxIntervalHours -f $ScheduleCount)
                                $scheduleCheck = 23
                            }
                            elseif ($ScheduleInterval -eq 'Minutes' -and $ScheduleCount -ge 60)
                            {
                                Write-Warning -Message ($script:localizedData.MaxIntervalMins -f $ScheduleCount)
                                $scheduleCheck = 59
                            }
                            else
                            {
                                $scheduleCheck = $ScheduleCount
                            }

                            if ($scheduleCheck -ne $state.ScheduleCount)
                            {
                                Write-Verbose -Message ($script:localizedData.SCountTest -f $scheduleCheck, $state.ScheduleCount)
                                $result = $false
                            }
                        }
                    }
                }
                else
                {
                    Write-Warning -Message $script:localizedData.ScheduleType
                }
            }

            if (-not [string]::IsNullOrEmpty($ExcludeMembership))
            {
                foreach ($member in $ExcludeMembership)
                {
                    if (([string]::IsNullOrEmpty($state.ExcludeMembership)) -or ($state.ExcludeMembership -notcontains $member))
                    {
                        if ($state.IncludeMembership -contains $member -or $state.QueryRules.RuleName -contains $member -or
                            $state.DirectMembership -contains $member)
                        {
                            Write-Warning -Message ($script:localizedData.ExcludeError -f $member)
                        }

                        Write-Verbose -Message ($script:localizedData.ExcludeMemberRule -f $CollectionName, $member)
                        $result = $false
                    }
                }
            }

            if (-not [string]::IsNullOrEmpty($IncludeMembership))
            {
                foreach ($member in $IncludeMembership)
                {
                    if (([string]::IsNullOrEmpty($state.IncludeMembership)) -or ($state.IncludeMembership -notcontains $member))
                    {
                        if ($state.DirectMembership -contains $member -or $state.QueryRules.RuleName -contains $member -or
                            $state.ExcludeMembership -contains $member)
                        {
                            Write-Warning -Message ($script:localizedData.IncludeError -f $member)
                        }

                        Write-Verbose -Message ($script:localizedData.IncludeMemberRule -f $CollectionName, $member)
                        $result = $false
                    }
                }
            }

            if (-not [string]::IsNullOrEmpty($DirectMembership))
            {
                foreach ($member in $DirectMembership)
                {
                    if (([string]::IsNullOrEmpty($state.DirectMembership)) -or ($state.DirectMembership -notcontains $member -and
                        $state.DirectMembershipId -notcontains $member))
                    {
                        Write-Verbose -Message ($script:localizedData.DirectMemberRule -f $CollectionName, $member)
                        $result = $false
                    }
                }
            }

            if (-not [string]::IsNullOrEmpty($QueryRules))
            {
                foreach ($rule in $QueryRules)
                {
                    if (([string]::IsNullOrEmpty($state.QueryRules.QueryExpression)) -or
                       ($state.QueryRules.QueryExpression.Replace(' ','') -notcontains $rule.QueryExpression.Replace(' ','')))
                    {
                        Write-Verbose -Message ($script:localizedData.QueryRule -f $CollectionName, $rule.QueryExpression)
                        $result = $false
                    }
                }
            }
        }
    }
    else
    {
        if ($state.Ensure -eq 'Present')
        {
            Write-Verbose -Message ($script:localizedData.RemoveCollection -f $CollectionName)
            $result = $false
        }
    }

    Write-Verbose -Message ($script:localizedData.TestState -f $result)
    Set-Location -Path "$env:temp"
    return $result
}

Export-ModuleMember -Function *-TargetResource
