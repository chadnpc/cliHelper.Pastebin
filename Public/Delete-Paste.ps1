function Remove-Paste {
  [CmdletBinding(SupportsShouldProcess = $true)][Alias('Delete-Paste')]
  param (
  )

  begin {
  }

  process {
    if ($PSCmdlet.ShouldProcess("Target", "Operation")) {
    }
  }

  end {
  }
}