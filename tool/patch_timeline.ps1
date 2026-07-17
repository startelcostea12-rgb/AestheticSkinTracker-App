$file = 'c:\Users\Admin\Downloads\flutter_windows_3.41.2-stable\flutter\bin\aestheticskintracker\lib\screens\scar_healing_tracker_screen.dart'
$t = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8)

$journalCall = '_buildEntryJournalSection(entry, globalIdx),'
$jIdx = $t.IndexOf($journalCall)
if ($jIdx -lt 0) { Write-Host 'NOT FOUND'; exit 1 }
$afterCall = $jIdx + $journalCall.Length

# Find the itemBuilder closing: '        );' on its own (8 spaces)
# Search for unique pattern of the itemBuilder end
$containerClose = "`n        );"
$contIdx = $t.IndexOf($containerClose, $afterCall)
if ($contIdx -lt 0) { Write-Host 'Container close NOT FOUND'; exit 1 }
Write-Host "afterCall=$afterCall, contIdx=$contIdx"

$nl = [System.Environment]::NewLine
$correctClose = $nl + "                    ]," + $nl + "                  )," + $nl + "                )," + $nl + "              ]," + $nl + "            )," + $nl + "          )," + $nl + "        );"

$newText = $t.Substring(0, $afterCall) + $correctClose + $t.Substring($contIdx + $containerClose.Length)
[System.IO.File]::WriteAllText($file, $newText, [System.Text.Encoding]::UTF8)
Write-Host "Done. New length: $($newText.Length)"
