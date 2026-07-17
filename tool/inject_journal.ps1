$file = 'c:\Users\Admin\Downloads\flutter_windows_3.41.2-stable\flutter\bin\aestheticskintracker\lib\screens\scar_healing_tracker_screen.dart'
$insertFile = 'c:\Users\Admin\Downloads\flutter_windows_3.41.2-stable\flutter\bin\aestheticskintracker\tool\journal_methods.dart'

$text = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8)
$insert = [System.IO.File]::ReadAllText($insertFile, [System.Text.Encoding]::UTF8)

$target = '  Widget _buildTimeline() {'
$newText = $text.Replace($target, $insert + "`n" + $target)

if ($newText.Length -gt $text.Length) {
  [System.IO.File]::WriteAllText($file, $newText, [System.Text.Encoding]::UTF8)
  Write-Host "SUCCESS. New length: $($newText.Length)"
} else {
  Write-Host "FAILED: replacement did not change file"
}
