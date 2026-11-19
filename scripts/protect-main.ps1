#requires -Version 5.1
<#
.SYNOPSIS
    给 main 应用分支保护：只接受通过自动检查的 Pull Request，禁止直推、强制推送与删除。

.DESCRIPTION
    检查名取自 .github/workflows/ci.yml 的 job 名称。新仓库第一次应用前，
    先让一次 Pull Request 的检查跑完，否则提交状态会一直显示「等待上报」。
    本脚本只改仓库设置，不改文件。需要仓库管理员权限。

.EXAMPLE
    gh auth login
    ./scripts/protect-main.ps1 -Repo owner/ffxiv-green-screen
#>
param(
    [Parameter(Mandatory = $true)][string]$Repo,
    [string[]]$Contexts = @('checks', 'plugin-build'),
    [string]$Branch = 'main'
)
$ErrorActionPreference = 'Stop'
if ($Repo -notmatch '^[\w.-]+/[\w.-]+$') { throw "仓库名应形如 owner/name，收到：$Repo" }

$body = @{
    required_status_checks         = @{ strict = $false; contexts = $Contexts }
    enforce_admins                 = $true
    required_pull_request_reviews  = @{ required_approving_review_count = 0; dismiss_stale_reviews = $false }
    restrictions                   = $null
    required_linear_history        = $false
    allow_force_pushes             = $false
    allow_deletions                = $false
    required_conversation_resolution = $true
} | ConvertTo-Json -Depth 5

# 用临时文件而不是标准输入：Windows PowerShell 5.1 把字符串接到原生程序时会带 BOM，JSON 会解析失败。
$temp = Join-Path ([IO.Path]::GetTempPath()) ('branch-protection-' + [guid]::NewGuid().ToString('N') + '.json')
try {
    [IO.File]::WriteAllText($temp, $body, (New-Object System.Text.UTF8Encoding($false)))
    gh api --method PUT "repos/$Repo/branches/$Branch/protection" --input $temp
    if ($LASTEXITCODE -ne 0) {
        throw "写入分支保护失败。确认 gh 已登录，且该账号对 $Repo 有管理员权限。"
    }
} finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
}

gh api "repos/$Repo/branches/$Branch/protection" --jq '{
    required_checks: .required_status_checks.contexts,
    strict: .required_status_checks.strict,
    approvals: .required_pull_request_reviews.required_approving_review_count,
    admins_enforced: .enforce_admins.enabled,
    force_push: .allow_force_pushes.enabled,
    deletions: .allow_deletions.enabled
}'
