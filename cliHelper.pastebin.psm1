#!/usr/bin/env pwsh
using namespace System.Collections.Generic

#Requires -Modules cliHelper.core, cliHelper.env

#region    Classes
enum PasteVisibility {
  Public
  Unlisted
  Private
}

class PasteOptions {
  [string]$Name
  [string]$Format
  [string]$Expire
  [string]$UserKey
  [string]$FolderKey
  [PasteVisibility]$Visibility
  PasteOptions() {}
  PasteOptions([hashtable]$hashtable) {
    [ValidateNotNullOrEmpty()][hashtable]$hashtable = $hashtable
    $hashtable.Keys.ForEach({ $this.$_ = $hashtable[$_] })
  }
}

<#
.SYNOPSIS
  Main class
.DESCRIPTION
  Implementation of Pastebin developers API
.EXAMPLE
  #Set Api Key
  [Pastebin]::SetApiDevKey("PASTEBIN_API_KEY") # Replace with your API key

  # --- Create a new paste (public)
  $newPasteUrl = [Pastebin]::NewPaste("Hello, Pastebin!", @{ Name = "MyTestPaste.txt"; Expire = "1H" })
  Write-Host "New Paste URL: $newPasteUrl"

  # --- Create an unlisted paste:

  $pasteOptions = [PasteOptions]@{
    Name    = "My Unlisted Paste"
    Format  = "powershell"
    Visibility = 1     # 0 = Public, 1 = Unlisted, 2 = Private
    Expire  = "1D"  # 1 Day
  }

  $unlistedPasteUrl = [Pastebin]::NewPaste('$x = 10; Write-Host "This is unlisted"', $pasteOptions)
  Write-Host "Unlisted Paste URL: $unlistedPasteUrl"

  # --- Login (replace with your credentials) ---
  $userKey = [Pastebin]::Login("your_username", "your_password")

  if ($userKey) {
    Write-Host "Login successful. User Key: $userKey"
    # List pastes for the logged-in user
    $pastes = [Pastebin]::ListPastes(10)  # Get up to 10 pastes
    Write-Host "User Pastes:"
    Write-Host $pastes

    #  Get user details
    $userDetails = [Pastebin]::GetUserDetails
    Write-Host "User Details:"
    Write-Host $userDetails

    # Assuming $newPasteUrl is from a paste *you* created (and you're logged in)
    if ($newPasteUrl) {
      # Extract paste key:
      $pasteKey = $newPasteUrl -replace "https://pastebin.com/"

      # --- Get raw paste content (using user key)
      $rawContent = [Pastebin]::GetRawPaste($pasteKey)
      Write-Host "Raw Paste Content (User):"
      Write-Host $rawContent

      # --- Delete the paste ---
      $deleteResult = [Pastebin]::DeletePaste($pasteKey)
      Write-Host "Delete Result: $deleteResult"
    }

  } else {
    Write-Warning "Login failed.  Subsequent operations requiring login will not work."
  }

  # --- Get raw paste content (public or unlisted, no login required)
  $publicPasteKey = "UIFdu235s"  # Replace with a known public/unlisted paste key
  $rawPublicContent = [Pastebin]::GetRawPublicPaste($publicPasteKey)
  Write-Host "Raw Paste Content (Public):"
  Write-Host $rawPublicContent

  # --- Logout ---
  [Pastebin]::Logout()
  Write-Host "Logged out. User key cleared."

  # Try to list pastes after logout (should fail)
  $pastesAfterLogout = [Pastebin]::ListPastes
  Write-Host "Trying to list after logout"
  Write-Host $pastesAfterLogout
.LINK
  Specify a URI to a help page, this will show when Get-Help -Online is used.
#>
Class Pastebin {
  #  Properties (consider making these instance properties if you want to support multiple accounts)
  hidden static $Config = @{
    ApiDevKey  = (Read-Env .env).Where({ $_.Name -eq "PASTEBIN_API_KEY" }).Value   # Replace with actual API key OR get it from a secure store.  HIGHLY recommended to NOT hardcode.
    ApiUserKey = $null # Store user key after successful login.
  } -as 'PsRecord'

  Pastebin() {}
  # Pastebin([string]$DeveloperKey) {
  #   if (-not [string]::IsNullOrEmpty($DeveloperKey)) {
  #     [Pastebin]::Config.ApiDevKey = $DeveloperKey
  #   } else {
  #     Write-Warning "API key Should Be Set"
  #   }
  # }

  # Makes API requests __ Handles common POST logic.
  hidden static [string] MakeApiRequest([string]$Url, [hashtable]$Parameters) {
    # Convert hashtable to a properly formatted query string
    $queryString = ($Parameters.GetEnumerator() | ForEach-Object {
        if ($_.Value -is [System.Collections.IEnumerable] -and $_.Value -isnot [string]) {
          # Handle array values (though Pastebin API doesn't seem to use them)
          $_.Value | ForEach-Object { "$($_.Key)=$([System.Web.HttpUtility]::UrlEncode($_))" }
        } else {
          "$($_.Key)=$([System.Web.HttpUtility]::UrlEncode($_.Value))"
        }
      }) -join "&"


    try {
      $response = Invoke-WebRequest -Uri $Url -Method Post -Body $queryString -UseBasicParsing -ContentType "application/x-www-form-urlencoded"

      if ($response.StatusCode -eq 200) {
        return $response.Content
      } else {
        Write-Error "API Request Failed. Status Code: $($response.StatusCode) - $($response.StatusDescription)"
        return $null # Or throw an exception, depending on your error handling strategy
      }
    } catch {
      Write-Error "API Request Failed: $($_.Exception.Message)"
      return $null  # Or re-throw the exception
    }
  }

  static [string] NewPaste([string]$Code, [hashtable]$Options = @{}) {
    if ([string]::IsNullOrEmpty([Pastebin]::Config.ApiDevKey)) {
      Write-Error "ApiDevKey is not set.  Use Set-ApiDevKey or the constructor to set it."
      return $null
    }
    $parameters = @{
      api_dev_key    = [Pastebin]::Config.ApiDevKey
      api_option     = 'paste'
      api_paste_code = $Code
    }

    # Add optional parameters if provided
    if ($Options.ContainsKey('Name')) { $parameters.Add('api_paste_name', $Options['Name']) }
    if ($Options.ContainsKey('Format')) { $parameters.Add('api_paste_format', $Options['Format']) }
    if ($Options.ContainsKey('Visibility')) { $parameters.Add('api_paste_private', $Options['Visibility']) }
    if ($Options.ContainsKey('Expire')) { $parameters.Add('api_paste_expire_date', $Options['Expire']) }
    if ($Options.ContainsKey('FolderKey')) { $parameters.Add('api_folder_key', $Options['FolderKey']) }
    if ($Options.ContainsKey('UserKey') -or (-not [string]::IsNullOrEmpty([Pastebin]::Config.ApiUserKey))) {
      $parameters.Add('api_user_key', $(if ($Options.ContainsKey('UserKey')) { $Options['UserKey'] }else { [Pastebin]::Config.ApiUserKey }))
    }

    $result = [Pastebin]::MakeApiRequest("https://pastebin.com/api/api_post.php", $parameters)
    if ($result -and $result -notmatch "^Bad API request") {
      return $result
    } else {
      Write-Error "Failed to create paste: $result"
      return $null
    }
  }

  # Login and get user key
  static [string] Login([string]$Username, [securestring]$Password) {
    if ([string]::IsNullOrEmpty([Pastebin]::Config.ApiDevKey)) {
      Write-Error "ApiDevKey is not set.  Use Set-ApiDevKey or the constructor to set it."
      return $null
    }
    $parameters = @{
      api_dev_key       = [Pastebin]::Config.ApiDevKey
      api_user_name     = $Username
      api_user_password = $Password | xconvert Tostring
    }
    $result = [Pastebin]::MakeApiRequest("https://pastebin.com/api/api_login.php", $parameters)

    if ($result -and $result -notmatch "^Bad API request") {
      [Pastebin]::Config.ApiUserKey = $result  # Store the user key
      return $result
    } else {
      Write-Error "Login Failed: $result"
      return $null
    }
  }
  static [void] SetApiDevKey([string]$DeveloperKey) {
    [Pastebin]::Config.ApiDevKey = $DeveloperKey
  }
  static [void] SetApiUserKey([string]$UserKey) {
    [Pastebin]::Config.ApiUserKey = $UserKey
  }
  static [string] GetApiUserKey() {
    return [Pastebin]::Config.ApiUserKey
  }
  static [string] GetApiDevKey() {
    return [Pastebin]::Config.ApiDevKey
  }
  #  List pastes for a user
  static [string] ListPastes([int]$Limit = 50) {
    if ([string]::IsNullOrEmpty([Pastebin]::Config.ApiDevKey)) {
      Write-Error "ApiDevKey is not set.  Use Set-ApiDevKey or the constructor to set it."
      return $null
    }
    if ([string]::IsNullOrEmpty([Pastebin]::Config.ApiUserKey)) {
      Write-Error "User not logged in.  Use Login() first."
      return $null
    }
    $parameters = @{
      api_dev_key       = [Pastebin]::Config.ApiDevKey
      api_user_key      = [Pastebin]::Config.ApiUserKey
      api_option        = 'list'
      api_results_limit = $Limit
    }

    return [Pastebin]::MakeApiRequest("https://pastebin.com/api/api_post.php" , $parameters)
  }
  static [string] DeletePaste([string]$PasteKey) {
    if ([string]::IsNullOrEmpty([Pastebin]::Config.ApiDevKey)) {
      Write-Error "ApiDevKey is not set.  Use Set-ApiDevKey or the constructor to set it."
      return $null
    }
    if ([string]::IsNullOrEmpty([Pastebin]::Config.ApiUserKey)) {
      Write-Error "User not logged in.  Use Login() first."
      return $null
    }

    $parameters = @{
      api_dev_key   = [Pastebin]::Config.ApiDevKey
      api_user_key  = [Pastebin]::Config.ApiUserKey
      api_paste_key = $PasteKey
      api_option    = 'delete'
    }

    $result = [Pastebin]::MakeApiRequest("https://pastebin.com/api/api_post.php" , $parameters)
    if ($result -eq "Paste Removed") {
      return $result
    }
    Write-Error "Failed to delete paste: $result"
    return $null
  }
  static [string] GetUserDetails() {
    if ([string]::IsNullOrEmpty([Pastebin]::Config.ApiDevKey)) {
      Write-Error "ApiDevKey is not set.  Use Set-ApiDevKey or the constructor to set it."
      return $null
    }
    if ([string]::IsNullOrEmpty([Pastebin]::Config.ApiUserKey)) {
      Write-Error "User not logged in.  Use Login() first."
      return $null
    }

    $parameters = @{
      api_dev_key  = [Pastebin]::Config.ApiDevKey
      api_user_key = [Pastebin]::Config.ApiUserKey
      api_option   = 'userdetails'
    }

    return [Pastebin]::MakeApiRequest("https://pastebin.com/api/api_post.php" , $parameters)
  }
  #  Get raw paste content (requires user login)
  static [string] GetRawPaste([string]$PasteKey) {
    if ([string]::IsNullOrEmpty([Pastebin]::Config.ApiDevKey)) {
      Write-Error "ApiDevKey is not set.  Use Set-ApiDevKey or the constructor to set it."
      return $null
    }
    if ([string]::IsNullOrEmpty([Pastebin]::Config.ApiUserKey)) {
      Write-Error "User not logged in for private paste retrieval.  Use Login() first, or use GetRawPublicPaste()."
      return $null
    }
    $parameters = @{
      api_dev_key   = [Pastebin]::Config.ApiDevKey
      api_user_key  = [Pastebin]::Config.ApiUserKey
      api_paste_key = $PasteKey
      api_option    = 'show_paste'
    }

    return [Pastebin]::MakeApiRequest("https://pastebin.com/api/api_raw.php" , $parameters)
  }
  # Get raw paste content (public or unlisted)
  static [string] GetRawPublicPaste([string]$PasteKey) {
    if ([string]::IsNullOrEmpty([Pastebin]::Config.ApiDevKey)) {
      Write-Error "ApiDevKey is not set.  Use Set-ApiDevKey or the constructor to set it."
      return $null
    }
    try {
      $response = Invoke-WebRequest -Uri "https://pastebin.com/raw/$PasteKey" -Method Get -UseBasicParsing
      if ($response.StatusCode -eq 200) {
        return $response.Content
      } else {
        Write-Error "API Request Failed. Status Code: $($response.StatusCode) - $($response.StatusDescription)"
        return $null # Or throw an exception, depending on your error handling strategy
      }
    } catch {
      Write-Error "Could Not Get Paste: $($_.Exception.Message)"
      return $null
    }
  }
  # Logout (Clears the stored API User Key)
  static [void] Logout() {
    [Pastebin]::Config.ApiUserKey = $null
  }
}

#endregion Classes
# Types that will be available to users when they import the module.
$typestoExport = @(
  [Pastebin], [PasteOptions], [PasteVisibility]
)
$TypeAcceleratorsClass = [PsObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
foreach ($Type in $typestoExport) {
  if ($Type.FullName -in $TypeAcceleratorsClass::Get.Keys) {
    $Message = @(
      "Unable to register type accelerator '$($Type.FullName)'"
      'Accelerator already exists.'
    ) -join ' - '

    [System.Management.Automation.ErrorRecord]::new(
      [System.InvalidOperationException]::new($Message),
      'TypeAcceleratorAlreadyExists',
      [System.Management.Automation.ErrorCategory]::InvalidOperation,
      $Type.FullName
    ) | Write-Warning
  }
}
# Add type accelerators for every exportable type.
foreach ($Type in $typestoExport) {
  $TypeAcceleratorsClass::Add($Type.FullName, $Type)
}
# Remove type accelerators when the module is removed.
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
  foreach ($Type in $typestoExport) {
    $TypeAcceleratorsClass::Remove($Type.FullName)
  }
}.GetNewClosure();

$scripts = @();
$Public = Get-ChildItem "$PSScriptRoot/Public" -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue
$scripts += Get-ChildItem "$PSScriptRoot/Private" -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue
$scripts += $Public

foreach ($file in $scripts) {
  Try {
    if ([string]::IsNullOrWhiteSpace($file.fullname)) { continue }
    . "$($file.fullname)"
  } Catch {
    Write-Warning "Failed to import function $($file.BaseName): $_"
    $host.UI.WriteErrorLine($_)
  }
}

$Param = @{
  Function = $Public.BaseName
  Cmdlet   = '*'
  Alias    = '*'
  Verbose  = $false
}
Export-ModuleMember @Param
