<#
.SYNOPSIS
    Builds the lab directory structure on a fresh lab.local domain controller.

.DESCRIPTION
    Creates OUs, groups, sample users, the fine-grained password policy and two GPOs.
    Safe to re-run: objects that already exist are skipped.
    Sample users get random temporary passwords, printed once on screen.

    This script documents the lab as it was built by hand. It has not been
    re-run end to end on a fresh domain, so test it in a lab before relying on it.

    Not scripted: delegation of control. That was done with the Delegate Control
    wizard on the IT OU, giving IT-Support the "Reset user passwords" task.
    Verify it with:  dsacls "OU=IT,OU=Users,OU=Corp,<domain DN>"
#>

#Requires -Modules ActiveDirectory, GroupPolicy

. "$PSScriptRoot\JML.ps1"

$dn = Get-LabDomainDN

function New-LabOU {
    param([string]$Name, [string]$Path)
    $existing = Get-ADOrganizationalUnit -Filter "Name -eq '$Name'" -SearchBase $Path -SearchScope OneLevel
    if (-not $existing) {
        New-ADOrganizationalUnit -Name $Name -Path $Path
        Write-Host "OU created: $Name"
    }
}

# 1. OUs (parents first)
New-LabOU -Name 'Corp'         -Path $dn
New-LabOU -Name 'Users'        -Path "OU=Corp,$dn"
New-LabOU -Name 'IT'           -Path "OU=Users,OU=Corp,$dn"
New-LabOU -Name 'HR'           -Path "OU=Users,OU=Corp,$dn"
New-LabOU -Name 'Sales'        -Path "OU=Users,OU=Corp,$dn"
New-LabOU -Name 'Groups'       -Path "OU=Corp,$dn"
New-LabOU -Name 'Servers'      -Path "OU=Corp,$dn"
New-LabOU -Name 'Workstations' -Path "OU=Corp,$dn"
New-LabOU -Name 'Disabled'     -Path "OU=Corp,$dn"

# 2. Security groups
foreach ($g in 'IT-Support', 'IT-Staff', 'HR-Staff', 'Sales-Staff') {
    if (-not (Get-ADGroup -Filter "Name -eq '$g'")) {
        New-ADGroup -Name $g -GroupScope Global -GroupCategory Security -Path "OU=Groups,OU=Corp,$dn"
        Write-Host "Group created: $g"
    }
}

# 3. Sample users (joiner function from JML.ps1 generates the passwords)
$people = @(
    @{ First = 'Youssef'; Last = 'Amrani';   Dept = 'IT'    },
    @{ First = 'Sara';    Last = 'Idrissi';  Dept = 'HR'    },
    @{ First = 'Karim';   Last = 'Bensouda'; Dept = 'Sales' }
)
foreach ($p in $people) {
    New-LabUser -FirstName $p.First -LastName $p.Last -Department $p.Dept
}
Add-ADGroupMember -Identity 'IT-Support' -Members 'yamrani'

# 4. Fine-grained password policy for IT-Support
if (-not (Get-ADFineGrainedPasswordPolicy -Filter "Name -eq 'IT-Strict-Password-Policy'")) {
    New-ADFineGrainedPasswordPolicy -Name 'IT-Strict-Password-Policy' -Precedence 10 `
        -MinPasswordLength 12 -PasswordHistoryCount 10 -ComplexityEnabled $true `
        -LockoutThreshold 3 -LockoutDuration '00:30:00' -LockoutObservationWindow '00:30:00' `
        -ReversibleEncryptionEnabled $false
    Add-ADFineGrainedPasswordPolicySubject -Identity 'IT-Strict-Password-Policy' -Subjects 'IT-Support'
    Write-Host 'Fine-grained password policy created'
}

# 5. GPOs: one computer-side (Workstations OU), one user-side (Sales OU)
function New-LabGpoLinked {
    param([string]$Name, [string]$Key, [string]$ValueName, [string]$Target)
    if (-not (Get-GPO -Name $Name -ErrorAction SilentlyContinue)) {
        New-GPO -Name $Name | Out-Null
        Set-GPRegistryValue -Name $Name -Key $Key -ValueName $ValueName -Type DWord -Value 1 | Out-Null
        New-GPLink -Name $Name -Target $Target | Out-Null
        Write-Host "GPO created and linked: $Name"
    }
}

New-LabGpoLinked -Name 'Workstations-Restrict-USB' `
    -Key 'HKLM\Software\Policies\Microsoft\Windows\RemovableStorageDevices' `
    -ValueName 'Deny_All' -Target "OU=Workstations,OU=Corp,$dn"

New-LabGpoLinked -Name 'Sales-User-Restrictions' `
    -Key 'HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' `
    -ValueName 'NoControlPanel' -Target "OU=Sales,OU=Users,OU=Corp,$dn"

Write-Host 'Done. Review the temporary passwords above, then close this window.' -ForegroundColor Cyan
