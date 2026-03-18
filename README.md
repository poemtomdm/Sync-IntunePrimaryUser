# 🔄 Intune Primary User Sync
 
> Automatically aligns the **Primary User** of Windows devices in Microsoft Intune with the **last logged-on user**, using the Microsoft Graph API.
 
---
 
## 📋 Table of Contents
 
- [Why This Exists](#-why-this-exists)
- [How It Works](#-how-it-works)
- [Prerequisites](#-prerequisites)
- [Azure App Registration Setup](#-azure-app-registration-setup)
- [Parameters](#-parameters)
- [Usage Examples](#-usage-examples)
- [Output](#-output)
- [Dry Run Mode](#-dry-run-mode)
- [Limitations](#-limitations)
 
---
 
## 💡 Why This Exists
 
In Microsoft Intune, the **Primary User** of a device drives several critical policies and experiences:
 
- **User-targeted app deployments** — apps assigned to users only deploy if that user is set as Primary User
- **Conditional Access** — user-device affinity checks rely on this assignment
- **Company Portal** — the Primary User is shown ownership of the device
- **License reporting** — some license models count per Primary User
 
The problem is that **Intune does not automatically update the Primary User** when a device is handed off to a different employee, re-imaged, or shared. Over time, devices accumulate **stale Primary User assignments** that break app targeting and reporting.
 
This script solves that by comparing the current Primary User with the most recently logged-on user — and correcting any mismatch.
 
---
 
## ⚙️ How It Works
 
```
1. Authenticates to Microsoft Graph using a Service Principal (Client Credentials flow)
2. Retrieves all Windows-managed devices from Intune (with pagination support)
3. For each device, compares:
      currentPrimaryUser  ←→  lastLoggedOnUser (from usersLoggedOn collection)
4. If a mismatch is detected:
      - Fetches display name of the correct user
      - Updates the Primary User relationship via Graph API
      - Logs the change to a JSON report
5. Outputs a timestamped JSON report of all changes made
```
 
---
 
## 🧰 Prerequisites
 
| Requirement | Details |
|---|---|
| PowerShell | 5.1+ or PowerShell 7+ |
| Module | `Microsoft.Graph.Authentication` |
| Permissions | App-only (Service Principal) |
 
Install the required module if not already present:
 
```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
```
 
---
 
## 🔐 Azure App Registration Setup
 
You need an **App Registration** in Azure AD with the following **Application permissions** (not Delegated):
 
| Permission | Reason |
|---|---|
| `DeviceManagementManagedDevices.ReadWrite.All` | Read devices and update Primary User |
| `User.Read.All` | Resolve user display names |
 
After granting permissions, generate a **Client Secret** and note:
- `Tenant ID`
- `Client ID` (Application ID)
- `Client Secret` (value, not the secret ID)
 
---
 
## 📝 Parameters
 
| Parameter | Type | Required | Description |
|---|---|---|---|
| `-TenantId` | `string` | ✅ Yes | Your Azure AD Tenant ID (GUID) |
| `-ClientId` | `string` | ✅ Yes | App Registration Client ID |
| `-ClientSecret` | `string` | ✅ Yes | App Registration Client Secret |
| `-DryRun` | `switch` | ❌ No | Simulate changes without applying them |
 
---
 
## 🚀 Usage Examples
 
### Basic run — apply all corrections
 
```powershell
.\Sync-IntuneDevicePrimaryUser.ps1 `
    -TenantId  "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
    -ClientId  "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy" `
    -ClientSecret "your-client-secret-value"
```
 
### Dry run — preview changes only, nothing is written
 
```powershell
.\Sync-IntuneDevicePrimaryUser.ps1 `
    -TenantId  "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
    -ClientId  "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy" `
    -ClientSecret "your-client-secret-value" `
    -DryRun
```
 
### Scheduled Task / Automation (non-interactive)
 
```powershell
$params = @{
    TenantId     = $env:INTUNE_TENANT_ID
    ClientId     = $env:INTUNE_CLIENT_ID
    ClientSecret = $env:INTUNE_CLIENT_SECRET
}
.\Sync-IntuneDevicePrimaryUser.ps1 @params
```
 
> 💡 **Tip:** Store credentials as environment variables or retrieve them from Azure Key Vault rather than hardcoding them in scripts or pipelines.
 
---
 
## 📤 Output
 
### Console output (live)
 
```
Connecting to Microsoft Graph
Retrieving Windows devices...
MISMATCH: DESKTOP-AB12CD -> Target Primary: Jane Smith
MISMATCH: LAPTOP-XY9900 -> Target Primary: Bob Johnson
Process finished. Results saved to: PrimaryUserSync_20250318_1430.json
```
 
### JSON report (written to script directory)
 
A timestamped file is created for every run that makes at least one change:
 
**Filename:** `PrimaryUserSync_yyyyMMdd_HHmm.json`
 
```json
[
  {
    "DeviceName": "DESKTOP-AB12CD",
    "Previous":   "John Doe",
    "NewPrimary": "Jane Smith",
    "Timestamp":  "2025-03-18 14:30"
  },
  {
    "DeviceName": "LAPTOP-XY9900",
    "Previous":   "Alice Brown",
    "NewPrimary": "Bob Johnson",
    "Timestamp":  "2025-03-18 14:30"
  }
]
```
 
If no devices needed updating, no file is written and the console shows:
 
```
No Windows devices required synchronization.
```
 
---
 
## 🧪 Dry Run Mode
 
The `-DryRun` switch lets you **safely audit** your environment before committing changes.
 
In dry run mode the script:
- ✅ Authenticates and queries all devices normally
- ✅ Identifies and reports all mismatches
- ❌ Does **not** call the update API
- ❌ Does **not** write a JSON report
 
Console output in dry run:
 
```
[DRY RUN] Would update DESKTOP-AB12CD to Jane Smith
[DRY RUN] Would update LAPTOP-XY9900 to Bob Johnson
```
 
**Always run with `-DryRun` first** when deploying to a new tenant.
 
---
 
## ⚠️ Limitations
 
- **Windows only** — the script filters for `operatingSystem eq 'Windows'`. macOS and mobile devices are out of scope by design.
- **Last-logged-on logic** — the script uses the last entry in the `usersLoggedOn` collection. Shared/kiosk devices with multiple frequent users may churn frequently.
- **No rollback** — the JSON report acts as an audit trail, but there is no automated rollback. Previous Primary User assignments can be restored manually via the report data.
- **Beta API** — the script uses the `beta` endpoint of Microsoft Graph. Microsoft may change or deprecate beta endpoints without notice.
- **Rate limiting** — on very large tenants (10,000+ devices), you may encounter Graph API throttling. Consider adding retry logic with exponential backoff for production use at scale.
 
---
 
## 📄 License
 
MIT — free to use, modify, and distribute.
