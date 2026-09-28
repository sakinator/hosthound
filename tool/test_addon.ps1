$tests = @(
  @{ name = 'Addon Manifest'; url = 'http://localhost:7002/manifest.json'; expect = 'id' },
  @{ name = 'Catalog Base'; url = 'http://localhost:7002/catalog/movie/yt_indian.json'; expect = 'metas' },
  @{ name = 'Catalog Skip (Pagination)'; url = 'http://localhost:7002/catalog/movie/yt_indian/skip=10.json'; expect = 'metas' },
  @{ name = 'Catalog Genre Filter'; url = 'http://localhost:7002/catalog/movie/yt_indian/genre=Bollywood%20Full%20Movies.json'; expect = 'metas' },
  @{ name = 'Catalog Search Filter'; url = 'http://localhost:7002/catalog/movie/yt_indian/search=Don.json'; expect = 'metas' },
  @{ name = 'Catalog Archive.org'; url = 'http://localhost:7002/catalog/movie/archive_movies.json'; expect = 'metas' },
  @{ name = 'Catalog Dailymotion'; url = 'http://localhost:7002/catalog/movie/dm_movies.json'; expect = 'metas' },
  @{ name = 'Meta Enriched IMDB (Inception)'; url = 'http://localhost:7002/meta/movie/tt1375666.json'; expect = 'meta' },
  @{ name = 'Stream Series (Game of Thrones)'; url = 'http://localhost:7002/stream/series/tt0944947:1:1.json'; expect = 'streams' },
  @{ name = 'Stream Custom (Dailymotion)'; url = 'http://localhost:7002/stream/movie/dm:xb0xz66.json'; expect = 'streams' },
  @{ name = 'Stream Movie (Inception)'; url = 'http://localhost:7002/stream/movie/tt1375666.json'; expect = 'streams' }
)

Write-Host "================ STREMIO / NUVIO ADDON AUDIT ================" -ForegroundColor Cyan

$allPassed = $true

foreach ($test in $tests) {
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  try {
    $res = Invoke-WebRequest -Uri $test.url -Method Get -TimeoutSec 20 -UseBasicParsing
    $sw.Stop()
    $json = $res.Content | ConvertFrom-Json
    $cors = $res.Headers['Access-Control-Allow-Origin']
    if ($cors -ne '*') {
      Write-Host "[-] $($test.name) CORS MISSING or not wildcard: $cors" -ForegroundColor Red
      $allPassed = $false
      continue
    }

    $prop = $json.PSObject.Properties[$test.expect]
    if ($null -eq $prop) {
      Write-Host "[-] $($test.name) MISSING EXPECTED KEY '$($test.expect)'" -ForegroundColor Red
      $allPassed = $false
    } else {
      $itemCount = if ($prop.Value -is [System.Collections.IList]) { $prop.Value.Count } else { 1 }
      Write-Host "[+] $($test.name): 200 OK ($($sw.ElapsedMilliseconds)ms) - Key: '$($test.expect)' (Count: $itemCount) | CORS: '$cors'" -ForegroundColor Green
    }
  } catch {
    $allPassed = $false
    Write-Host "[-] $($test.name): FAILED - $($_.Exception.Message)" -ForegroundColor Red
  }
}

Write-Host "`n--- OPTIONS CORS Preflight Audit ---" -ForegroundColor Cyan
try {
  $optionsRes = Invoke-WebRequest -Uri "http://localhost:7002/manifest.json" -Method Options -UseBasicParsing
  Write-Host "[+] OPTIONS /manifest.json: Status $($optionsRes.StatusCode) | CORS: $($optionsRes.Headers['Access-Control-Allow-Origin']) | Methods: $($optionsRes.Headers['Access-Control-Allow-Methods'])" -ForegroundColor Green
} catch {
  Write-Host "[-] OPTIONS /manifest.json FAILED: $($_.Exception.Message)" -ForegroundColor Red
  $allPassed = $false
}

Write-Host "`n--- Stream Schema Compliance Audit ---" -ForegroundColor Cyan
try {
  $stRes = Invoke-WebRequest -Uri "http://localhost:7002/stream/movie/dm:xb0xz66.json" -Method Get -UseBasicParsing
  $stJson = $stRes.Content | ConvertFrom-Json
  if ($stJson.streams.Count -gt 0) {
    $sample = $stJson.streams[0]
    Write-Host "[+] Stream object schema check:" -ForegroundColor Green
    Write-Host "    name: $($sample.name)"
    Write-Host "    title: $($sample.title)"
    Write-Host "    url: $($sample.url)"
    Write-Host "    behaviorHints: $(ConvertTo-Json $sample.behaviorHints -Compress)"
  }
} catch {
  Write-Host "[-] Stream schema check failed: $($_.Exception.Message)" -ForegroundColor Red
}

if ($allPassed) {
  Write-Host "`n>>> ALL ADDON PROTOCOL CHECKS PASSED SUCCESSFULLY <<<" -ForegroundColor Green
} else {
  Write-Host "`n>>> SOME AUDIT CHECKS FAILED <<<" -ForegroundColor Red
}
