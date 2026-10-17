# Active Directory IAM Lab (lab.local)

A hands-on Windows Server 2022 Active Directory lab I built to practice identity and access management (IAM): directory design, role-based access, Group Policy, delegated administration, password policy and user lifecycle automation with PowerShell.

Everything runs in virtual machines on one PC. The lab uses evaluation licenses and is not a production design.

## Environment

VMware Workstation, one NAT network (`192.168.23.0/24`).

| VM | Role | OS | IP |
|---|---|---|---|
| DC01 | Domain controller + DNS | Windows Server 2022 Standard (evaluation) | 192.168.23.10 |
| CLIENT01 | Domain-joined workstation | Windows 11 (evaluation) | 192.168.23.50 |

## Directory structure

```
lab.local
└── Corp
    ├── Users
    │   ├── IT
    │   ├── HR
    │   └── Sales
    ├── Groups         (IT-Support, IT-Staff, HR-Staff, Sales-Staff)
    ├── Servers
    ├── Workstations   (CLIENT01)
    └── Disabled       (accounts of people who left)
```

## What I built

1. **Domain controller:** static IP, AD DS and DNS roles, new forest `lab.local`.
2. **OUs, users and groups:** department OUs, role-based security groups, users created in the correct OU.
3. **Group Policy:** a computer policy linked to the Workstations OU and a user policy linked to the Sales OU. Verified with `Get-GPInheritance` and `gpresult` on the client.
4. **Delegation of control:** the IT-Support group can reset passwords in the IT OU only, without being a Domain Admin. Verified with `dsacls`.
5. **Fine-grained password policy:** members of IT-Support need at least 12 characters and are locked out for 30 minutes after 3 bad attempts. Verified with `Get-ADFineGrainedPasswordPolicy`.
6. **Domain join:** Windows 11 client joined to the domain and placed in the Workstations OU.
7. **Joiner / Mover / Leaver automation:** PowerShell functions for the user lifecycle (see below).

### Joiner / Mover / Leaver (`scripts/JML.ps1`)

- **Joiner:** builds the username from a naming convention, places the account in the department OU, adds the department group, and sets a random temporary password that must be changed at first logon. It refuses to create a duplicate.
- **Mover:** moves the account to the new OU, swaps the department group, and lists any other groups so a person can decide whether the access is still needed (access creep).
- **Leaver:** disables the account, removes group memberships, records the former groups and the date in the description, and moves the account to the Disabled OU. Accounts are disabled, not deleted, to keep an audit trail.

No passwords are stored in any script. `scripts/Setup-Lab.ps1` rebuilds the structure above on a fresh domain. It was written after I built the lab by hand and has not been re-run end to end, so test it in a lab first.


## Screenshots

Delegation of control: giving IT-Support the password reset task on the IT OU

<img width="508" height="433" alt="delegation-wizard" src="https://github.com/user-attachments/assets/acce72bb-9dd8-49ce-83f5-a5d591df530e" />



Delegation verified with dsacls: IT-Support has the Reset Password right

<img width="340" height="103" alt="dsacls-delegation" src="https://github.com/user-attachments/assets/31580e27-aca6-4a75-8186-f9a266b1c228" />



Fine-grained password policy for IT-Support (12 characters, lockout after 3 attempts for 30 minutes)

<img width="934" height="505" alt="fgpp-settings" src="https://github.com/user-attachments/assets/c637b936-ab2b-47c1-bd84-ef15f123ec2a" />



User policy applied to a Sales user, and the restriction message the user sees

<img width="626" height="346" alt="gpo-user-restriction" src="https://github.com/user-attachments/assets/789d4bfd-5522-4af3-bb73-22b06a0c9a1a" />



Login screen after repeated wrong passwords on a locked-out account

<img width="719" height="445" alt="account-lockout" src="https://github.com/user-attachments/assets/c705b8df-8f46-4b02-9fb0-86183fe92659" />


## Troubleshooting write-ups

**Domain join refused: "This device is joined to Azure AD"**
- Symptom: `Add-Computer` failed on a freshly installed Windows 11 VM.
- Diagnosis: `dsregcmd /status` showed `AzureAdJoined : YES`.
- Cause: I signed in with a work or school account during Windows setup, which registered the PC with that organization's Entra tenant.
- Fix: disconnect from the work or school account (`dsregcmd /leave` or Settings), restart, then join the domain.
- Lesson: use a local account during setup on lab machines.

**Group Policy not updating: wrong DNS on the client**
- Symptom: internet worked, but `gpupdate /force` failed and `lab.local` did not resolve.
- Diagnosis: `nslookup lab.local` returned "Non-existent domain" from `1.1.1.1`.
- Cause: the client pointed at a public DNS server, which has no AD records.
- Fix: point the client's DNS to the domain controller and run `ipconfig /flushdns`.
- Note: `nltest /dsgetdc` still succeeded, because it answered from the client's cache.

**GPO did not apply: computer setting on an OU without computers**
- Symptom: a USB-restriction GPO linked to the Sales OU never appeared in `gpresult`.
- Cause: it was a computer setting linked to an OU that only contains user accounts.
- Fix: link computer policies to the OU that holds the computer (Workstations) and use user settings for user OUs.

**Clock skew test: no failure observed**
- Hypothesis: a client clock more than 5 minutes off breaks Kerberos.
- Test: confirmed `MaxClockSkew` is 5 in the Default Domain Policy, set the client 15 and then 60 minutes ahead, and measured the offset with `w32tm /stripchart`.
- Result: ticket requests and `gpupdate` still succeeded, and the domain controller logged only successful ticket events.
- Conclusion: Microsoft documentation describes the client retrying with the domain controller's time after a skew error. Failure auditing was not confirmed during the test, so I could not observe a rejected first attempt.

**Standard user cannot elevate**
- A domain user hitting a UAC prompt on the client cannot run an elevated PowerShell without admin credentials. This is expected, and a good example of least privilege.

## Observations

- The Default Domain Policy has no account lockout (threshold 0). Only the fine-grained policy for IT-Support locks accounts. In a real environment I would add lockout to the default policy.

## Skills practiced

Active Directory design (OUs, groups, RBAC), Group Policy and inheritance, delegation and least privilege, password and lockout policy, PowerShell automation, DNS and Kerberos troubleshooting, reading event logs.

## Next steps

Connect this directory to Microsoft Entra ID with Entra Connect to practice hybrid identity.
