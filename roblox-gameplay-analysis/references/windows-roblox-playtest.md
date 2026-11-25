# Windows 上的 Roblox 实测

## 开局与输入校准

- 确认用户指定的 Experience、Roblox Player 窗口及当前界面。*Survive the Apocalypse* 的示例 Experience 的 Place ID 为 `90148635862803`。单人实验从空队列进入，按顺序核对创建面板、高亮的 `1` 和创建后的 `1/1`。批量执行已经明确的点击动作，保留人数和传送结果的视觉核对。面板超时后，重新核对开局区状态。曾经在开场提示仍覆盖画面时发送移动键，角色因此误入已有队伍。
- 从实际桌面会话检查前台。在本次 Windows 环境里，默认沙箱的进程列表看不到 Roblox，桌面会话可以看到它。使用宿主提供的权限机制。应用切换后重新核对窗口和画面，避免把输入发给其他应用。
- 原型用 Windows PowerShell 5.1、System.Drawing、前台客户区截图和 Windows 扫描码输入。先做静态匹配自检，再在 Roblox 前台做采集探针。采集时间只代表测到的截图和局部匹配开销。

```powershell
powershell.exe -NoProfile -File .\scripts\roblox-route-prototype.ps1 -SelfTest
powershell.exe -NoProfile -File .\scripts\roblox-route-prototype.ps1 -CaptureProbe -ReferenceWidth 2213 -ReferenceHeight 1118
```

- 第一次在新机器运行时，先做一次短走和松键检查，再从前后画面量镜头转向。分别核对窗口物理客户区与当前设置下的游戏 UI。截图工具可能显示缩放后的窗口或包含标题栏，瞄准输入则用客户区坐标。参考尺寸只负责换算，宽高比、游戏语言和鼠标灵敏度变化仍可能改变实际识别和转向。
- 把录像目录或输入视频路径作为运行参数。用短录像保存拾取、交付、卡住和掉血等关键片段。实时操控在本地完成截图、决策和输入，录像用于复核。

## 取油交付示例

给启动器提供本机校准得到的 JSON。以下值来自本次尝试的工作参考系，可用来理解字段。基准尺寸或开局场景改变后，需要按实机画面核对。

```json
{
  "referenceWidth": 2213,
  "referenceHeight": 1118,
  "returnTurnX": 600,
  "fuelTargetX": 395,
  "fuelArrivalY": 300,
  "fuelTolerance": 125,
  "generatorTargetX": 915,
  "generatorTargetY": 125,
  "generatorTolerance": 205,
  "generatorMinimumWidth": 670,
  "trailOriginX": 1105,
  "trailOriginY": 660,
  "retraceOutbound": true,
  "regions": {
    "fuelMarker": { "x": 710, "y": 245, "width": 780, "height": 515 },
    "pickupKey": { "x": 2056, "y": 986, "width": 150, "height": 83 },
    "bagTrail": { "x": 20, "y": 640, "width": 2150, "height": 445 },
    "generator": { "x": 190, "y": 245, "width": 1900, "height": 240 },
    "returnTrail": { "x": 10, "y": 390, "width": 2190, "height": 715 },
    "recovery": { "x": 1346, "y": 608, "width": 320, "height": 96 },
    "health": { "x": 23, "y": 819, "width": 443, "height": 34 }
  }
}
```

- 区域位置为基准客户区坐标。`fuelTargetX`、`fuelArrivalY` 和发电机目标坐标分别相对于各自区域。`trailOriginX`、`trailOriginY` 是基准客户区坐标。`returnTurnX` 是鼠标相对移动量，按镜头设置实测。`recovery` 采样稳定的地面纹理，`health` 包住整条可见血量槽。两者可以省略，省略后对应的自动应急不启用。
- 开始前装备背包，确认预计的油桶箭头在视野内，确认到目标的大致通路。需要从发电机旁挪开时，可在 JSON 加入 `departure`，例如 `{"keys":["d"],"durationMs":420}`。只有实际记录过出程运动才可倒放路线。希望直接循箭头返程时，把 `retraceOutbound` 设为 `false`。
- 拾取区域应包含瞄准油桶后出现的那一行 `F` 键帽，排除底部「取消存储」行。识别键帽后仍需确认物件消失、返程箭头出现或背包增量。返程识别发电机条和交付后进度变化，复核背包计数和发电机等级。视角位置变化会改变进度条的位置及宽度。

```powershell
powershell.exe -NoProfile -File .\scripts\invoke-fuel-route.ps1 -ProfilePath .\fuel-profile.json -DryRun
powershell.exe -NoProfile -File .\scripts\invoke-fuel-route.ps1 -ProfilePath .\fuel-profile.json -TraceReturn
```

`-DryRun` 不发输入，需要前台 Roblox 画面，仍然受步骤前置条件限制。例如当前没看到油桶标记时，后续瞄准步骤不能据此运行。正常运行输出每步匹配状态、耗时、绕障和掉血应急次数。看到绕障计数增加后，仍须核对角色位置和任务是否继续。脚本在关键步骤检查前台，并在结束时释放它持有的按键。

## 录像复核

```powershell
.\scripts\measure-replay.ps1 -Mode PickupKey -VideoPath $video `
  -FfmpegPath $ffmpeg -Crop '153:85:2060:985' -AtSeconds 24,29,32,35,38
.\scripts\measure-replay.ps1 -Mode Health -VideoPath $attackVideo `
  -FfmpegPath $ffmpeg -Crop '248:22:12:644' -AtSeconds 48.8,49,49.1,49.25
```

`-Crop` 采用 `宽:高:左:顶` 的录像像素坐标。`-Resize` 可缩放中间样本再恢复到采样规格，检查识别对重采样的敏感度。 `Motion` 模式按输入顺序比较相邻样本，测阈值时要让采样时间间隔与现场循环接近。录像下采样只是离线对照，跨机结论需要在另一台机器上用实际窗口重跑。

## 2026-11-25 的实测记录

| 证据 | 支持的结论 |
|---|---|
| 录像 `Roblox 2026-11-25 14-58-20.mp4`，单人取油交付 **14.34 秒** | 同一轮连续取油和交付曾跑通，背包归零，发电机从 0% 到 63%。 |
| 另一轮确认 `1/1` 的单人局，接近油桶 **3.75 秒**，补发拾取键，再以人工绕障动作接回自动返程 **5.04 秒** | 该窗口下按段走通。两段耗时排除了等待和人工修正。 |
| 录像 `13-42-26` 与 `14-58-20` 的拾取键帽样本，原尺寸及缩放样本检测成功 | 键帽形状可作为本次观察到的提示。新检测尚未在完整实战路线中确认自动拾取。 |
| 返程在树与栅栏之间卡住。先后退再横移后可接回箭头。后来接近墙角时自动绕障触发两次，仍被击倒 | 继续测不同障碍和路线恢复。方向提示可指向墙后目标。 |
| 录像 `Roblox 2026-11-25 13-19-36.mp4`，受击附近的血条填充约 97% → 92% → 84% | 本机样本支持以掉血作为应急输入的触发条件。僵尸接近时的提前改向和受击后的完整恢复仍待验证。 |
| 本机前台小区域采集探针连续 20 次匹配位置一致，单次约 8–14 毫秒 | 只衡量这组前台采集和匹配样本。 |

## 地图升级对照

同一单人局先在等级 2 确认地图显示和可达边界，记录出生区、道路、建筑、固定地标与界外区域。升级到等级 3 时记录实际进度与新增可达范围，在相同位置和视角复拍。再开一局复核固定地标和变化是否重现，分别记录可见范围、可达范围和物件布局。这样能检验观察到的是解锁、替换、逐步加载，还是不同开局的布局差异。等级 2 到 3 的受控对照尚未完成，游戏内部生成算法仍待验证。
