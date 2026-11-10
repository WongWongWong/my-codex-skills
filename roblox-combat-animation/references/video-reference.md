# 视频参考获取与检查

用于从用户提供的链接取得招式参考并定位可核对的画面。先复用已成功的方法，再针对实际错误切换路径；不把网页标题、下载完成或抽帧成功当成已观看的证据。动作拆解接续 [动作与效果](animation-and-effects.md)，音效制作接续 [音效接入](audio-integration.md)。

## 入口与获取顺序

1. 记录来源链接、视频编号、分 P、用户指定时间和版本。清理分享追踪参数时保留 `p`、时间定位等有效信息；短链接先解析最终地址，不直接套用完整视频页的解析方式。
2. 检查当前项目已有视频、来源记录、抽帧结果和成功命令。确认视频编号与分 P 相同、文件可解码后复用；新的时间段只补提取，不重复下载整片。已有时间记录只能帮助定位，不能代替实际查看。
3. 已有适用的成功获取路径时可以直接复用，不必每次先试网页播放器。浏览器能播放时可以正常观看；访问失败、播放器反复超时且没有新线索时，转到可用的媒体获取方式和本地查看。
4. B 站可尝试下文已在实际任务中成功的“视频信息 → 播放地址 → 本地媒体”路线。其他平台使用其可用工具或获取方式，不套用 B 站接口。接口与返回格式可能变化，运行时检查结果。
5. 下载后核对实际时长、分辨率、帧率、音轨及目标片段解码。请求的清晰度不代表实际返回的清晰度；低清版本看不清接触细节时尝试可用的更清晰来源，不能靠放大补出不存在的细节。

## B 站获取示例

以下 PowerShell 示例参数化了已成功的接口调用和请求头，适用于完整 BVID 视频页及返回单段 `durl` 的情况。保存为临时 `.ps1` 后传入 `VideoUrl` 与 `OutputDirectory`；输出放项目参考缓存，不放 Skill 安装目录。未提供 `p` 时才默认 P1；指定 P 不存在时停止，不回退到 P1。

```powershell
param(
    [Parameter(Mandatory)][uri]$VideoUrl,
    [Parameter(Mandatory)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
if ($VideoUrl.Scheme -ne 'https' -or
    $VideoUrl.Host -notin @('www.bilibili.com', 'bilibili.com') -or
    $VideoUrl.AbsolutePath -cnotmatch '^/video/(BV[0-9A-Za-z]{10})/?$') {
    throw '需要解析后的 B 站 HTTPS BVID 视频页地址'
}
$videoId = $Matches[1]
$queryPairs = @{}
foreach ($pair in $VideoUrl.Query.TrimStart('?').Split('&')) {
    if (-not $pair) { continue }
    $parts = $pair.Split('=', 2)
    $queryPairs[[uri]::UnescapeDataString($parts[0])] =
        if ($parts.Count -eq 2) { [uri]::UnescapeDataString($parts[1]) } else { '' }
}
$pageNumber = 1
if ($queryPairs.ContainsKey('p')) {
    if (-not [int]::TryParse($queryPairs['p'], [ref]$pageNumber) -or $pageNumber -lt 1) {
        throw '分 P 参数无效'
    }
}
$sourceUrl = "https://www.bilibili.com/video/$videoId/?p=$pageNumber"
$headers = @{ 'User-Agent' = 'Mozilla/5.0'; 'Referer' = $sourceUrl }
$meta = Invoke-RestMethod -Uri "https://api.bilibili.com/x/web-interface/view?bvid=$videoId" -Headers $headers
if ($null -eq $meta.code -or $meta.code -ne 0 -or -not $meta.data) {
    throw "视频信息请求失败：$($meta.code) $($meta.message)"
}
$page = @($meta.data.pages | Where-Object { $_.page -eq $pageNumber })
if ($page.Count -ne 1 -or -not $page[0].cid) { throw '未找到指定分 P 的 cid' }
$contentId = $page[0].cid
$play = Invoke-RestMethod -Uri "https://api.bilibili.com/x/player/playurl?bvid=$videoId&cid=$contentId&qn=32&fnval=0&fourk=0" -Headers $headers
if ($null -eq $play.code -or $play.code -ne 0 -or -not $play.data) {
    throw "播放地址请求失败：$($play.code) $($play.message)"
}
$segments = @($play.data.durl)
if ($segments.Count -ne 1 -or -not $segments[0].url -or $play.data.format -ne 'mp4') {
    throw '当前示例只处理单段 MP4；检查返回结构并转到相应媒体处理分支'
}
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($outputRoot) | Out-Null
$videoPath = Join-Path $outputRoot "${videoId}_p${pageNumber}.mp4"
$recordPath = Join-Path $outputRoot "${videoId}_p${pageNumber}.source.json"
if ((Test-Path -LiteralPath $videoPath) -or (Test-Path -LiteralPath $recordPath)) {
    throw '已有缓存：先核对来源和解码情况，复用或选择新的输出目录'
}
Invoke-WebRequest -Uri $segments[0].url -Headers $headers -OutFile $videoPath
if ((Get-Item -LiteralPath $videoPath).Length -le 0) { throw '下载文件为空' }
[ordered]@{
    source = $sourceUrl; suppliedUrl = $VideoUrl.AbsoluteUri
    bvid = $videoId; page = $pageNumber; cid = $contentId
    title = $meta.data.title; part = $page[0].part
    durationSeconds = $page[0].duration
    returnedQuality = $play.data.quality; returnedFormat = $play.data.format
    mediaPath = $videoPath; downloadedAt = [DateTime]::UtcNow.ToString('o')
} | ConvertTo-Json | Set-Content -LiteralPath $recordPath -Encoding utf8
Write-Output $videoPath
```

此处 `qn=32` 是请求参数，不是实际画质保证。单段限制是示例的适用范围，不是平台保证：返回多个 `durl` 时按顺序获取并正确拼接，返回 DASH 时处理视频与音频流并核对同步，不能只取第一段或把无声视频当完整参考。临时媒体 URL 失效时重新请求播放地址，不反复下载旧地址。来源记录保留稳定视频页地址，不保存临时播放地址、Cookie 或令牌。

## 本地定位与连续帧示例

先查找可用的 FFmpeg／ffprobe。PATH 中没有时，检查已知安装的软件所带工具或此前成功使用的位置；不因 `Get-Command ffmpeg` 找不到就断言本机没有，也不把某台机器的安装路径写成通用要求。

用 ffprobe 或 FFmpeg 输入信息检查媒体，并实际解码目标片段；只读取容器信息不足以证明目标片段完整。按需要分层查看：全片低频概览定位版本与招式 → 目标范围检查前后过程 → 快速交接、接触前后提取连续源帧。概览抽帧频率与片段长度按素材调整，不固定为招式节奏。

以下 PowerShell 示例以参数指定文件、时间与 FFmpeg 路径，生成概览、带原音的片段和连续帧。`Ffmpeg` 可用 PATH 中的命令名或已发现的绝对路径；`OutputDirectory` 必须是新的目录，避免混入旧帧。先根据概览选定片段；已知时间时可跳过概览命令。

```powershell
param(
    [Parameter(Mandatory)][string]$VideoPath,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [Parameter(Mandatory)][ValidateRange(0, 86400)][double]$StartSeconds,
    [Parameter(Mandatory)][ValidateRange(0.01, 86400)][double]$DurationSeconds,
    [string]$Ffmpeg = 'ffmpeg'
)
$ErrorActionPreference = 'Stop'
$mediaPath = (Resolve-Path -LiteralPath $VideoPath).Path
$ffmpegPath = (Get-Command $Ffmpeg -CommandType Application -ErrorAction Stop).Source
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $outputRoot) { throw '请选择新的抽帧目录，避免混入旧结果' }
[IO.Directory]::CreateDirectory($outputRoot) | Out-Null
$start = $StartSeconds.ToString([Globalization.CultureInfo]::InvariantCulture)
$duration = $DurationSeconds.ToString([Globalization.CultureInfo]::InvariantCulture)

# 稀疏概览仅用于定位，不能用于判断快速接触和换手。
& $ffmpegPath -hide_banner -loglevel error -i $mediaPath -an -vf 'fps=1/8,scale=480:-2,tile=4x4' -fps_mode vfr -n (Join-Path $outputRoot 'overview_%03d.jpg')
if ($LASTEXITCODE -ne 0) { throw '概览生成失败' }

# 解码后导出指定区间，保留可用原音，供正常速度和慢放检查。
& $ffmpegPath -hide_banner -loglevel error -ss $start -i $mediaPath -t $duration -map 0:v:0 -map '0:a:0?' -c:v mpeg4 -q:v 2 -c:a aac -n (Join-Path $outputRoot 'clip.mp4')
if ($LASTEXITCODE -ne 0) { throw '目标片段生成失败' }

# 不加 fps 滤镜或插帧；按源解码顺序保留连续帧及时间日志。
& $ffmpegPath -hide_banner -loglevel info -ss $start -i $mediaPath -t $duration -map 0:v:0 -an -vf showinfo -fps_mode passthrough -n (Join-Path $outputRoot 'frame_%05d.png') 2> (Join-Path $outputRoot 'frame-times.log')
if ($LASTEXITCODE -ne 0) { throw '连续帧生成失败' }
if (-not (Get-ChildItem -LiteralPath $outputRoot -Filter 'frame_*.png' -File | Select-Object -First 1)) {
    throw '目标区间没有输出帧，检查时长与起始位置'
}
[ordered]@{
    mediaPath = $mediaPath; startSeconds = $StartSeconds
    durationSeconds = $DurationSeconds; frameTiming = 'frame-times.log'
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $outputRoot 'segment.json') -Encoding utf8
```

实际打开片段和图片，记录已查看的范围；导出文件本身不算观看。连续帧可以制作联系表或裁剪放大，但保留原帧与上下文，避免裁掉支撑脚、另一只手或受击者。按片段起点及日志中的帧时间定位回源视频；可变帧率素材不能只用“帧序号 ÷ 标称帧率”推算时间。工具版本不支持某参数或编码器时，按实际能力调整并验证输出。

声音需要单独实际试听。音轨存在不代表已听清，慢放后的音高与节奏不能代替正常速度的声音判断；无法试听或音效被解说、配乐遮挡时，明确哪些声音结论尚未确认。正常速度、慢放、连续帧各自支持什么结论，按真实检查范围报告。

## 失败后的处理与停止条件

| 现象 | 下一步 |
|---|---|
| 网页打不开或播放器连续超时 | 复用缓存／成功命令，切换到可用媒体获取路径和本地查看，不重复等待同一播放器 |
| 套接字权限、沙箱或执行环境网络限制 | 核实错误来源；必要时按环境流程申请相应权限后重试，不能把环境限制写成平台视频不可读；实际拒绝授权后停止该受限操作 |
| 命令退出码为 0，但请求打印错误 | 检查异常、接口业务码和返回数据；PowerShell 请求用终止错误处理，不能只看进程退出码 |
| 播放地址失效、业务码失败或响应结构变化 | 根据具体错误更新地址或处理分支；不沿用过期 URL，不将 HTML／错误响应当视频保存成功 |
| 下载成功但无法解码、片段缺失或画面不清 | 检查实际格式、段数、时长及画质；修正获取或解码方法，再检查同一目标片段 |
| 登录、付费或其他实际访问限制 | 使用已有且获授权的访问方式；不能绕过访问控制，也不能承诺所有链接必可获取 |

同类错误重复出现且没有新线索时切换路径，不机械增加等待或无限重试。可用且获授权的路径确实受阻后，报告失败的具体环节、已尝试的方法和仍可确认的内容，再请求最小必要帮助（如可访问链接、指定片段或本地文件）。不要只以“浏览器失败／播放器超时”作为放弃读取的理由，也不让用户逐击代做参考分析。
