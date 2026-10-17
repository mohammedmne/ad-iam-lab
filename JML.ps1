<#
.SYNOPSIS
    Joiner / Mover / Leaver helpers for the lab.local Active Directory lab.

.DESCRIPTION
    Load into your session with:   . .\JML.ps1
    Then:
        New-LabUser     -FirstName Salma -LastName Benali -Department HR
        Move-LabUser    -Sam sbenali -NewDepartment Sales
        Disable-LabUser -Sam sbenali

    No passwords are stored in this file. Initial passwords are generated
    at run time and shown once on screen. Do not paste that console output
    into documentation.

    Assumes this OU layout: Corp > Users > (IT | HR | Sales), Corp > Disabled,
    and security groups named IT-Staff, HR-Staff and Sales-Staff.

    Written for a lab domain. Test in a lab, not in production.
#>

#Requires -Modules ActiveDirectory

function Get-LabDomainDN {
    (Get-ADDomain).DistinguishedName
}

function New-RandomPassword {
    <# Returns a random password that has upper, lower, digit and symbol characters. #>
    param([ValidateRange(12, 64)][int]$Length = 16)

    $sets = @(
        'ABCDEFGHJKLMNPQRSTUVWXYZ',
        'abcdefghijkmnopqrstuvwxyz',
        '23456789',
        '!@#$%^&*-_=+'
    )
    $all = $sets -join ''
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()

    $pick = {
        param([string]$chars)
        $bytes = New-Object byte[] 4
        $rng.GetBytes($bytes)
        $chars[[int]([BitConverter]::ToUInt32($bytes, 0) % $chars.Length)]
    }

    # one character from each class, then fill up to the requested length
    $result = @(foreach ($s in $sets) { & $pick $s })
    while ($result.Count -lt $Length) { $result += & $pick $all }

    # shuffle so the first four characters are not always upper/lower/digit/symbol
    $password = -join ($result | Sort-Object { & $pick $all })
    $rng.Dispose()
    $password
}

function New-LabUser {
    <# JOINER: create the account in the right OU, add the department group, force a password change. #>
    param(
        [Parameter(Mandatory)][string]$FirstName,
        [Parameter(Mandatory)][string]$LastName,
        [Parameter(Mandatory)][ValidateSet('IT', 'HR', 'Sales')][string]$Department,
        [System.Security.SecureString]$InitialPassword
    )

    $dn  = Get-LabDomainDN
    $sam = ($FirstName.Substring(0, 1) + $LastName).ToLower()
    $ou  = "OU=$Department,OU=Users,OU=Corp,$dn"

    if (Get-ADUser -Filter "SamAccountName -eq '$sam'") {
        Write-Warning "User $sam already exists. Nothing created."
        return
    }

    $generated = $false
    if (-not $InitialPassword) {
        $plain = New-RandomPassword
        $InitialPassword = ConvertTo-SecureString $plain -AsPlainText -Force
        $generated = $true
    }

    New-ADUser -Name "$FirstName $LastName" `
        -GivenName $FirstName -Surname $LastName `
        -SamAccountName $sam -UserPrincipalName "$sam@$((Get-ADDomain).DNSRoot)" `
        -Department $Department -Path $ou `
        -AccountPassword $InitialPassword -Enabled $true -ChangePasswordAtLogon $true

    Add-ADGroupMember -Identity "$Department-Staff" -Members $sam
    Write-Host "Created $sam in $Department and added to $Department-Staff" -ForegroundColor Green

    if ($generated) {
        Write-Host "Temporary password (shown once, must be changed at first logon): $plain" -ForegroundColor Cyan
    }
}

function Move-LabUser {
    <# MOVER: change OU, department attribute and department group; flag any other groups for review. #>
    param(
        [Parameter(Mandatory)][string]$Sam,
        [Parameter(Mandatory)][ValidateSet('IT', 'HR', 'Sales')][string]$NewDepartment
    )

    $dn   = Get-LabDomainDN
    $user = Get-ADUser -Filter "SamAccountName -eq '$Sam'" -Properties Department
    if (-not $user) { Write-Warning "User $Sam not found."; return }

    $old = $user.Department
    if ($old -eq $NewDepartment) { Write-Warning "$Sam is already in $NewDepartment."; return }

    Move-ADObject -Identity $user.DistinguishedName -TargetPath "OU=$NewDepartment,OU=Users,OU=Corp,$dn"
    Set-ADUser -Identity $Sam -Department $NewDepartment

    if ($old) {
        Remove-ADGroupMember -Identity "$old-Staff" -Members $Sam -Confirm:$false -ErrorAction SilentlyContinue
    }
    Add-ADGroupMember -Identity "$NewDepartment-Staff" -Members $Sam

    Write-Host "$Sam moved from $old to $NewDepartment" -ForegroundColor Green

    # access-creep check: anything besides the new department group needs a human decision
    $left = Get-ADPrincipalGroupMembership -Identity $Sam |
        Where-Object { $_.Name -ne 'Domain Users' -and $_.Name -ne "$NewDepartment-Staff" }
    if ($left) {
        Write-Warning 'Groups still assigned, review whether they are still needed:'
        $left | Select-Object -ExpandProperty Name
    }
}

function Disable-LabUser {
    <# LEAVER: disable, remove groups, record the old groups in the description, move to the Disabled OU. #>
    param([Parameter(Mandatory)][string]$Sam)

    $dn   = Get-LabDomainDN
    $user = Get-ADUser -Filter "SamAccountName -eq '$Sam'" -Properties MemberOf
    if (-not $user) { Write-Warning "User $Sam not found."; return }

    $groupNames = ($user.MemberOf | ForEach-Object { (Get-ADGroup $_).Name }) -join ', '

    Disable-ADAccount -Identity $Sam
    foreach ($g in $user.MemberOf) {
        Remove-ADGroupMember -Identity $g -Members $Sam -Confirm:$false
    }
    Set-ADUser -Identity $Sam -Description "Disabled $(Get-Date -Format yyyy-MM-dd). Former groups: $groupNames"
    Move-ADObject -Identity $user.DistinguishedName -TargetPath "OU=Disabled,OU=Corp,$dn"

    Write-Host "$Sam disabled, groups removed, moved to Disabled OU" -ForegroundColor Yellow
}
