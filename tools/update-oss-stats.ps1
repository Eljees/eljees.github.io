<#
    update-oss-stats.ps1 — обновляет счётчики вклада в открытый код.

    Что делает:
      1. спрашивает публичный поиск GitHub, сколько PR автора смерджено / открыто / закрыто;
      2. собирает список проектов, куда принят хотя бы один патч;
      3. проставляет свежие числа в eljees.github.io/index.html, tumanov-portfolio/oss.yaml
         и в блок OSS-STATS внутри tumanov-portfolio/portfolio.md;
      4. коммитит и пушит оба репозитория, если что-то изменилось.

    Запуск вручную:  pwsh -File .\tools\update-oss-stats.ps1
    Токен не нужен: используется анонимный API (лимит 10 поисковых запросов в минуту).
#>

$ErrorActionPreference = 'Stop'
$Author = 'Eljees'

$SiteRoot = Split-Path -Parent $PSScriptRoot
$RepoRoot = Join-Path (Split-Path -Parent $SiteRoot) 'tumanov-portfolio'
$LogFile  = Join-Path $PSScriptRoot 'update-oss-stats.log'

function Log($m){
  $line = ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m)
  Write-Host $line
  Add-Content -Path $LogFile -Value $line -Encoding utf8
}

function Save-Utf8($path, $text){
  [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
}

$headers = @{ 'User-Agent' = 'eljees-portfolio-stats'; 'Accept' = 'application/vnd.github+json' }

function Search-Count($q){
  $uri = 'https://api.github.com/search/issues?q={0}&per_page=1' -f [uri]::EscapeDataString($q)
  (Invoke-RestMethod -Uri $uri -Headers $headers).total_count
}

Log '--- старт ---'

$merged = Search-Count "type:pr author:$Author is:merged -user:$Author";        Start-Sleep -Seconds 7
$open   = Search-Count "type:pr author:$Author is:open -user:$Author";          Start-Sleep -Seconds 7
$closed = Search-Count "type:pr author:$Author is:closed is:unmerged -user:$Author"; Start-Sleep -Seconds 7
$total  = $merged + $open + $closed

Log ("смерджено $merged, открыто $open, закрыто без принятия $closed, всего $total")

# перечисляем все PR, чтобы получить список проектов
$repos = @{}; $mergedRepos = @{}
$pages = [math]::Ceiling($total / 100)
if ($pages -lt 1) { $pages = 1 }
if ($pages -gt 10) { $pages = 10 }   # потолок поиска GitHub — 1000 результатов
foreach ($p in 1..$pages) {
  $uri = 'https://api.github.com/search/issues?q={0}&per_page=100&page={1}' -f [uri]::EscapeDataString("type:pr author:$Author -user:$Author"), $p
  $r = Invoke-RestMethod -Uri $uri -Headers $headers
  foreach ($i in $r.items) {
    $rp = $i.repository_url -replace 'https://api.github.com/repos/', ''
    $repos[$rp] = 1
    if ($i.pull_request.merged_at) { $mergedRepos[$rp] = 1 }
  }
  Start-Sleep -Seconds 7
}
$projects = $mergedRepos.Count
$touched  = $repos.Count
$today    = Get-Date -Format 'dd.MM.yyyy'
$isoDate  = Get-Date -Format 'yyyy-MM-dd'
Log ("проектов с принятыми патчами $projects, всего репозиториев $touched")

if ($merged -eq 0 -and $open -eq 0) { Log 'пустой ответ API — выходим, ничего не трогаем'; exit 1 }

# ── 1. index.html ───────────────────────────────────────────────
$indexPath = Join-Path $SiteRoot 'index.html'
$html = Get-Content -Path $indexPath -Raw -Encoding utf8
$html = [regex]::Replace($html, '(?<=<b id="oss-merged">)\d+(?=</b>)',   [string]$merged)
$html = [regex]::Replace($html, '(?<=<b id="oss-open">)\d+(?=</b>)',     [string]$open)
$html = [regex]::Replace($html, '(?<=<b id="oss-projects">)\d+(?=</b>)', [string]$projects)
$html = [regex]::Replace($html, '(?<=<b id="oss-repos">)\d+(?=</b>)',    [string]$touched)
$html = [regex]::Replace($html, '(?<=<span id="oss-updated">)[^<]*(?=</span>)', $today)
Save-Utf8 $indexPath $html

# ── 2. oss.yaml ─────────────────────────────────────────────────
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('# Вклад в открытый код. Обновляется скриптом tools/update-oss-stats.ps1 раз в неделю.')
[void]$sb.AppendLine('# Источник: публичный поиск GitHub по author:Eljees, исключая собственные репозитории (-user:Eljees).')
[void]$sb.AppendLine("author: $Author")
[void]$sb.AppendLine("updated: `"$isoDate`"")
[void]$sb.AppendLine('counts:')
[void]$sb.AppendLine("  merged: $merged          # принятых pull request в чужие проекты")
[void]$sb.AppendLine("  open: $open           # открытых, ожидают решения мейнтейнеров")
[void]$sb.AppendLine("  closed_unmerged: $closed # закрытых без принятия")
[void]$sb.AppendLine("  total: $total")
[void]$sb.AppendLine("  projects_with_merged: $projects   # проектов, куда приняли хотя бы один PR")
[void]$sb.AppendLine("  repos_touched: $touched         # всего затронутых репозиториев")
[void]$sb.AppendLine('query:')
[void]$sb.AppendLine("  merged: `"type:pr author:$Author is:merged -user:$Author`"")
[void]$sb.AppendLine("  open: `"type:pr author:$Author is:open -user:$Author`"")
[void]$sb.AppendLine('projects_with_merged:')
foreach ($k in ($mergedRepos.Keys | Sort-Object)) { [void]$sb.AppendLine("  - $k") }
Save-Utf8 (Join-Path $RepoRoot 'oss.yaml') $sb.ToString()

# ── 3. portfolio.md, блок между маркерами ───────────────────────
$mdPath = Join-Path $RepoRoot 'portfolio.md'
$md = Get-Content -Path $mdPath -Raw -Encoding utf8
$statLine = "**$merged** принятых pull request в **$projects** сторонних проектов, **$open** открытых, всего затронут **$touched** репозиторий. Данные на **$today**."
$md = [regex]::Replace($md, '(?s)(?<=<!-- OSS-STATS -->\r?\n).*?(?=\r?\n<!-- /OSS-STATS -->)', $statLine)
Save-Utf8 $mdPath $md

# ── 4. коммит и пуш ─────────────────────────────────────────────
foreach ($dir in @($SiteRoot, $RepoRoot)) {
  Push-Location $dir
  $dirty = git status --porcelain
  if ($dirty) {
    git add -A
    git commit -m "Обновлены счётчики открытого кода: $merged смерджено, $open открыто ($today)" | Out-Null
    git push | Out-Null
    Log ("запушено: " + (Split-Path -Leaf $dir))
  } else {
    Log ("без изменений: " + (Split-Path -Leaf $dir))
  }
  Pop-Location
}
Log '--- готово ---'
