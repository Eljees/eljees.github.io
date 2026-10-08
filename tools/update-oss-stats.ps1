<#
    update-oss-stats.ps1 — обновляет счётчики вклада в открытый код.

    Что делает:
      1. спрашивает публичный поиск GitHub, сколько PR автора смерджено / открыто / закрыто;
      2. собирает список проектов, куда принят хотя бы один патч;
      3. проставляет свежие числа в eljees.github.io/index.html, tumanov-portfolio/oss.yaml
         и в блок OSS-STATS внутри tumanov-portfolio/portfolio.md;
      4. коммитит и пушит оба репозитория, если что-то изменилось.

    Запуск вручную:  pwsh -File .\tools\update-oss-stats.ps1
    Используется GitHub CLI с существующей авторизованной сессией.
    Проверка без записи и публикации: -VerifyOnly.
    Полнота страниц и независимые счётчики проверяются до изменения файлов.
#>

param([switch]$VerifyOnly)

$ErrorActionPreference = 'Stop'
$Author = 'Eljees'

$SiteRoot = Split-Path -Parent $PSScriptRoot
$RepoRoot = Join-Path (Split-Path -Parent $SiteRoot) 'tumanov-portfolio'
$LogFile  = Join-Path $PSScriptRoot 'update-oss-stats.log'

function Log($m){
  $line = ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m)
  Write-Host $line
  if (-not $VerifyOnly) { Add-Content -Path $LogFile -Value $line -Encoding utf8 }
}

function Save-Utf8($path, $text){
  [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
}

# gh uses the existing authenticated account; no credential is written to files.
$ProfileToday = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([datetime]::UtcNow, 'Russian Standard Time').Date
$today = $ProfileToday.ToString('dd.MM.yyyy')
$isoDate = $ProfileToday.ToString('yyyy-MM-dd')
$periodStart = $ProfileToday.AddYears(-1).ToString('yyyy-MM-dd')
$baseQuery = "is:pr author:$Author -user:$Author is:public"
$windowQuery = "$baseQuery is:merged merged:$periodStart..$isoDate"

function Search-GitHub($q, $page = 1) {
  $raw = & gh api --method GET search/issues -f "q=$q" -f 'per_page=100' -f "page=$page" -f 'sort=updated' -f 'order=desc'
  if ($LASTEXITCODE -ne 0) { throw 'GitHub search failed; no statistics will be published' }
  $result = ($raw -join "`n") | ConvertFrom-Json
  if ($result.incomplete_results) { throw 'GitHub search is incomplete; no statistics will be published' }
  return $result
}
function Search-Count($q) { (Search-GitHub $q).total_count }

Log '--- старт ---'
$merged = Search-Count "$baseQuery is:merged"
$open = Search-Count "$baseQuery is:open"
$closed = Search-Count "$baseQuery is:closed is:unmerged"
$mergedYear = Search-Count $windowQuery
$total = $merged + $open + $closed
if ($total -eq 0 -or $total -gt 1000) { throw 'Empty or over-limit search; partition/review before publishing' }

# Stable pagination, duplicate detection and independent counts prevent partial
# project/repository counts from replacing the last verified snapshot.
$items = @{}
$pages = [math]::Ceiling($total / 100)
foreach ($page in 1..$pages) {
  $result = Search-GitHub $baseQuery $page
  if ($result.total_count -ne $total) { throw 'Search changed during pagination; retry later' }
  foreach ($item in $result.items) {
    if ($items.ContainsKey($item.html_url)) { throw 'Duplicate search page item; retry later' }
    $items[$item.html_url] = $item
  }
}
if ($items.Count -ne $total) { throw 'Missing search results; no statistics will be published' }
$repos = @{}; $mergedRepos = @{}
$actualMerged=0; $actualOpen=0; $actualClosed=0; $actualYear=0
foreach ($item in $items.Values) {
  $rp = $item.repository_url -replace '^https://api.github.com/repos/', ''
  $repos[$rp] = 1
  if ($item.pull_request.merged_at) {
    $actualMerged++; $mergedRepos[$rp] = 1
    $mergeDate = ([datetimeoffset]$item.pull_request.merged_at).UtcDateTime.ToString('yyyy-MM-dd')
    if ($mergeDate -ge $periodStart -and $mergeDate -le $isoDate) { $actualYear++ }
  } elseif ($item.state -eq 'open') { $actualOpen++ } else { $actualClosed++ }
}
if ($actualMerged -ne $merged -or $actualOpen -ne $open -or $actualClosed -ne $closed -or $actualYear -ne $mergedYear) {
  throw 'Full result set disagrees with independent count queries; no statistics will be published'
}
$projects = $mergedRepos.Count; $touched = $repos.Count
Log "смерджено всего $merged, за 12 месяцев $mergedYear, открыто $open, закрыто без merge $closed; проектов $projects, репозиториев $touched"
if ($VerifyOnly) {
  [ordered]@{ merged=$merged; merged_12_months=$mergedYear; open=$open; closed_unmerged=$closed; total=$total; projects=$projects; repos=$touched; updated_iso=$isoDate; period_start=$periodStart } | ConvertTo-Json
  exit 0
}

# ── 1. index.html ───────────────────────────────────────────────
$indexPath = Join-Path $SiteRoot 'index.html'
$html = Get-Content -Path $indexPath -Raw -Encoding utf8
$html = [regex]::Replace($html, '(?<=<b id="oss-merged">)\d+(?=</b>)',   [string]$mergedYear)
$html = [regex]::Replace($html, '(?<=<b id="oss-open">)\d+(?=</b>)',     [string]$open)
$html = [regex]::Replace($html, '(?<=<b id="oss-projects">)\d+(?=</b>)', [string]$projects)
$html = [regex]::Replace($html, '(?<=<b id="oss-repos">)\d+(?=</b>)',    [string]$touched)
$html = [regex]::Replace($html, '(?<=<span id="oss-updated">)[^<]*(?=</span>)', $today)
$html = [regex]::Replace($html, '(?<=<span id="site-updated">)[^<]*(?=</span>)', $today)
$mergedWindowUrl = 'https://github.com/search?q={0}&amp;type=pullrequests' -f [uri]::EscapeDataString($windowQuery)
$html = [regex]::Replace($html, 'https://github.com/search\?q=[^"\n]+&amp;type=pullrequests(?=" data-ru="смерджённые")', $mergedWindowUrl)
Save-Utf8 $indexPath $html

# ── 1b. oss-stats.json — источник правды для страницы ───────────
# Числа в index.html — всего лишь последний снимок для поисковиков и режима без JS.
# Страница на загрузке читает oss-stats.json и переписывает их, поэтому коммит
# index.html из устаревшей копии больше не показывает посетителям старые цифры.
$jsonPath = Join-Path $SiteRoot 'oss-stats.json'
$stats = [ordered]@{
  merged          = $merged
  merged_12_months = $mergedYear
  period_start    = $periodStart
  period_end      = $isoDate
  scope           = 'Public PRs authored by Eljees in repositories owned by others'
  open            = $open
  closed_unmerged = $closed
  total           = $total
  projects        = $projects
  repos           = $touched
  updated         = $today
  updated_iso     = $isoDate
}
Save-Utf8 $jsonPath (($stats | ConvertTo-Json) + "`n")

# ── 1c. sitemap.xml — дата последнего изменения страницы ────────
$sitemapPath = Join-Path $SiteRoot 'sitemap.xml'
if (Test-Path $sitemapPath) {
  $sm = Get-Content -Path $sitemapPath -Raw -Encoding utf8
  $sm = [regex]::Replace($sm, '(?<=<lastmod>)[^<]*(?=</lastmod>)', $isoDate)
  Save-Utf8 $sitemapPath $sm
}

# ── 2. oss.yaml ─────────────────────────────────────────────────
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('# Вклад в открытый код. Обновляется скриптом tools/update-oss-stats.ps1 раз в неделю.')
[void]$sb.AppendLine('# Источник: публичный поиск GitHub по author:Eljees, исключая собственные репозитории (-user:Eljees).')
[void]$sb.AppendLine("author: $Author")
[void]$sb.AppendLine("updated: `"$isoDate`"")
[void]$sb.AppendLine("period_start: `"$periodStart`"")
[void]$sb.AppendLine("period_end: `"$isoDate`"")
[void]$sb.AppendLine('counts:')
[void]$sb.AppendLine("  merged: $merged          # принятых pull request в чужие проекты")
[void]$sb.AppendLine("  merged_12_months: $mergedYear")
[void]$sb.AppendLine("  open: $open           # открытых, ожидают решения мейнтейнеров")
[void]$sb.AppendLine("  closed_unmerged: $closed # закрытых без принятия")
[void]$sb.AppendLine("  total: $total")
[void]$sb.AppendLine("  projects_with_merged: $projects   # проектов, куда приняли хотя бы один PR")
[void]$sb.AppendLine("  repos_touched: $touched         # всего затронутых репозиториев")
[void]$sb.AppendLine('query:')
[void]$sb.AppendLine("  merged: `"$baseQuery is:merged`"")
[void]$sb.AppendLine("  open: `"$baseQuery is:open`"")
[void]$sb.AppendLine("  merged_12_months: `"$windowQuery`"")
[void]$sb.AppendLine("  closed_unmerged: `"$baseQuery is:closed is:unmerged`"")
[void]$sb.AppendLine('projects_with_merged:')
foreach ($k in ($mergedRepos.Keys | Sort-Object)) { [void]$sb.AppendLine("  - $k") }
Save-Utf8 (Join-Path $RepoRoot 'oss.yaml') $sb.ToString()

# ── 3. portfolio.md, блок между маркерами ───────────────────────
$mdPath = Join-Path $RepoRoot 'portfolio.md'
$md = Get-Content -Path $mdPath -Raw -Encoding utf8
$statLine = "**$mergedYear** публичных PR приняты в сторонние репозитории за последние 12 месяцев ($periodStart — $isoDate); **$open** PR открыты. За всё время: принятые патчи в **$projects** проектах, всего затронуто **$touched** репозиториев; **$closed** PR закрыты без merge. Данные на **$today**."
$md = [regex]::Replace($md, '(?s)(?<=<!-- OSS-STATS -->\r?\n).*?(?=\r?\n<!-- /OSS-STATS -->)', $statLine)
$md = [regex]::Replace($md, '(?m)^Актуально на .*$', ("Актуально на {0} · As of {1}" -f $today, $isoDate))
Save-Utf8 $mdPath $md

# ── 4. коммит и пуш ─────────────────────────────────────────────
# git пишет предупреждения и прогресс в stderr; при ErrorActionPreference=Stop
# PowerShell считает это ошибкой и обрывает скрипт — поэтому глушим поток и
# проверяем результат по коду возврата.
$ErrorActionPreference = 'Continue'
$failed = $false
foreach ($dir in @($SiteRoot, $RepoRoot)) {
  $name = Split-Path -Leaf $dir
  Push-Location $dir
  try {
    $dirty = git status --porcelain 2>&1 | Where-Object { $_ -notmatch '^warning:' }
    if ($dirty) {
      if ($dir -eq $SiteRoot) { git add -- index.html oss-stats.json sitemap.xml 2>&1 | Out-Null }
      else { git add -- oss.yaml portfolio.md 2>&1 | Out-Null }
      if (-not (git diff --cached --name-only)) { Pop-Location; continue }
      git commit -m "Обновлены счётчики открытого кода: $merged смерджено, $open открыто ($today)" 2>&1 | Out-Null
      if ($LASTEXITCODE -ne 0) { Log "$name : commit вернул $LASTEXITCODE"; $failed = $true; Pop-Location; continue }
      # На удалённой ветке могли появиться чужие коммиты — без этого push
      # отлетает как non-fast-forward (локальная ветка не продолжение удалённой).
      git pull --rebase 2>&1 | Out-Null
      $code = $LASTEXITCODE
      if ($code -ne 0) {
        git rebase --abort 2>&1 | Out-Null
        Log "$name : pull --rebase вернул $code — вероятен конфликт, push пропущен, нужны руки"
        $failed = $true; Pop-Location; continue
      }
      git push 2>&1 | Out-Null
      if ($LASTEXITCODE -eq 0) { Log "$name : запушено" } else { Log "$name : push вернул $LASTEXITCODE"; $failed = $true }
    } else {
      Log "$name : без изменений"
    }
  } catch {
    Log "$name : сбой — $($_.Exception.Message)"
    $failed = $true
  }
  Pop-Location
}
if ($failed) {
  Log '--- завершено с ошибками ---'
  exit 1
}
Log '--- готово ---'
