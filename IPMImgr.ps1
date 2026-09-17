# Requires PowerShell Version 5.1

# ============================================================
# IPMI Server Manager v1.4
#
# 版本 v1	(2026-09-16)
#	發布 基本雛形
#
# 版本v1.3	(2026-09-17)
#	新增 自訂伺服器
#	刪除 IPMIUtil支援
#	增加 IPMITool支援
#	分離 設定清單
#
# 版本v1.4	(2026-09-17)
#	新增 軟關機
#	新增 關閉電源警示
#
# ============================================================

$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$IpmiTool = Join-Path $ScriptPath "ipmitool.exe"

# ============================================================
# Configuration
# ============================================================

$ConfigFile = Join-Path $ScriptPath "IPMImgr_cfg.json"

if (-not (Test-Path $ConfigFile)) {
	Write-Host ""
	Write-Host "錯誤：找不到設定檔。" -ForegroundColor Red
	Write-Host ""
	Write-Host "設定檔位置：" -ForegroundColor Yellow
	Write-Host $ConfigFile
	Write-Host ""

	exit 1
}

try {
	$Config = Get-Content `
		-Path $ConfigFile `
		-Raw |
		ConvertFrom-Json
}
catch {
	Write-Host ""
	Write-Host "錯誤：無法讀取設定檔。" -ForegroundColor Red
	Write-Host ""
	Write-Host "設定檔：" -ForegroundColor Yellow
	Write-Host $ConfigFile
	Write-Host ""
	Write-Host "錯誤訊息：" -ForegroundColor Yellow
	Write-Host $_.Exception.Message -ForegroundColor Red
	Write-Host ""

	exit 1
}

# ============================================================
# IPMI and Server Configuration
# ============================================================

$IPMIInterface = $Config.IPMI.Interface
$CipherSuite   = $Config.IPMI.CipherSuite
$PowerStatusTimeout = [int]$Config.IPMI.PowerStatusTimeout

$Servers = @(
	foreach ($Server in $Config.Servers) {

		@{
			Name     = $Server.Name
			IP       = $Server.IP
			Username = $Server.Username
			Password = $Server.Password
		}
	}
)

# ============================================================
# Common Functions
# ============================================================
function Show-Header {
	Clear-Host
	Write-Host ""
	Write-Host "==================================================" -ForegroundColor Cyan
	Write-Host "            IPMI Server Manager v1.4  "             -ForegroundColor Cyan
	Write-Host "==================================================" -ForegroundColor Cyan
	Write-Host ""
}

function Pause-Script {
    Write-Host ""
    Read-Host "按 Enter 返回選單"
}

# ============================================================
# Execute IPMITool
# ============================================================

function Invoke-IPMI {

	param (
		[hashtable]$Server,
		[string[]]$CommandArguments
	)

	Write-Host ""

	if (-not (Test-Path $IpmiTool)) {

		Write-Host "錯誤：找不到 ipmitool.exe" -ForegroundColor Red
		Write-Host ""
		Write-Host "目前搜尋位置：" -ForegroundColor Yellow
		Write-Host $IpmiTool

		Pause-Script
		return
	}

	# --------------------------------------------------------
	# ipmitool LAN Plus Parameters
	#
	# -I lanplus  = IPMI 2.0 / RMCP+
	# -C 3        = Cipher Suite 3
	# --------------------------------------------------------

	$CommonArguments = @(
		"-I", $IPMIInterface,
		"-H", $Server.IP,
		"-U", $Server.Username,
		"-P", $Server.Password,
		"-C", $CipherSuite
	)

	# CommandArguments 已經包含 command
	# ipmitool.exe -I lanplus -H <IP> -U IPMI -P <PW> -C 3 <Function>

	$FinalArguments = $CommonArguments + $CommandArguments

	Write-Host "執行指令中，請稍後..." -ForegroundColor Cyan
	Write-Host ""

	& $IpmiTool $FinalArguments

	$ExitCode = $LASTEXITCODE

	Write-Host ""

	if ($ExitCode -eq 0) {
		Write-Host "指令執行完成。" -ForegroundColor Green
	}
	else {
		Write-Host "ipmitool 執行失敗。" -ForegroundColor Red
		Write-Host "Exit Code : $ExitCode" -ForegroundColor Red
	}

	Write-Host ""
	Write-Host "==================================================" -ForegroundColor DarkGray

	Pause-Script
}

# ============================================================
# Get Server Power Status
#
# ipmitool chassis power status
#
# ============================================================

function Get-PowerStatus {

	param (
		[hashtable]$Server
	)

	if (-not (Test-Path $IpmiTool)) {

		return "UNKNOWN"
	}

	# --------------------------------------------------------
	# ipmitool LAN Plus Parameters
	# --------------------------------------------------------

	$CommonArguments = @(
		"-I", $IPMIInterface,
		"-H", $Server.IP,
		"-U", $Server.Username,
		"-P", $Server.Password,
		"-C", $CipherSuite
	)

	$CommandArguments = @(
		"chassis",
		"power",
		"status"
	)

	$FinalArguments = $CommonArguments + $CommandArguments

	# --------------------------------------------------------
	# Use Process to run ipmitool
	# --------------------------------------------------------

	$Process = New-Object System.Diagnostics.Process
	$Process.StartInfo.FileName = $IpmiTool
	$Process.StartInfo.Arguments = (
		$FinalArguments | ForEach-Object {
			'"' + ($_ -replace '"', '\"') + '"'
		}
	) -join " "

	$Process.StartInfo.UseShellExecute = $false
	$Process.StartInfo.CreateNoWindow = $true
	$Process.StartInfo.RedirectStandardOutput = $true
	$Process.StartInfo.RedirectStandardError = $true

	try {
		$Started = $Process.Start()

		if (-not $Started) {
			$Process.Dispose()
			return "UNKNOWN"
		}

		# ----------------------------------------------------
		# Set timeout
		# ----------------------------------------------------

		$Finished = $Process.WaitForExit($PowerStatusTimeout)

		if (-not $Finished) {
			try {
				$Process.Kill()
			}
			catch {
			}
			$Process.Dispose()
			return "UNKNOWN"
		}

		$Output = $Process.StandardOutput.ReadToEnd()
		$ExitCode = $Process.ExitCode
		$Process.Dispose()

		if ($ExitCode -ne 0) {
			return "UNKNOWN"
		}

		if ($Output -match "Chassis Power is on") {
			return "ON"
		}

		if ($Output -match "Chassis Power is off") {
			return "OFF"
		}
		return "UNKNOWN"
	}
	catch {
		try {
			if ($Process -and -not $Process.HasExited) {
				$Process.Kill()
			}
		}
		catch {
		}
		try {
			$Process.Dispose()
		}
		catch {
		}
		return "UNKNOWN"
	}
}

# ============================================================
# Power Action Confirmation
# ============================================================

function Confirm-PowerAction {

	param (
		[hashtable]$Server,
		[string]$Action,
		[string[]]$Command
	)

	Show-Header

	Write-Host "Server : $($Server.Name)" -ForegroundColor Yellow
	Write-Host "IP     : $($Server.IP)" -ForegroundColor Yellow
	Write-Host ""

	Write-Host "即將執行：" -ForegroundColor Cyan
	Write-Host "  $Action" -ForegroundColor Red
	Write-Host ""

	$Confirm = Read-Host "確定要執行嗎？(Y/N)"


	if ($Confirm -notmatch "^[Yy]$") {
		Write-Host ""
		Write-Host "操作已取消。" -ForegroundColor Yellow
		Start-Sleep -Seconds 1
		return
	}

	Invoke-IPMI `
		-Server $Server `
		-CommandArguments $Command

}

# ============================================================
# Custom Server
# ============================================================

function Show-CustomServerMenu {
	Show-Header

	Write-Host "自訂伺服器" -ForegroundColor Green
	Write-Host ""
	Write-Host "請輸入臨時操作的伺服器資訊。" -ForegroundColor Cyan
	Write-Host "此資訊只會用於本次操作，不會加入伺服器清單。"
	Write-Host ""

	while ($true) {
		$CustomIP = Read-Host "IP位址"

		if ([string]::IsNullOrWhiteSpace($CustomIP)) {
			Write-Host ""
			Write-Host "IP位址不可為空白，請重新輸入。" -ForegroundColor Red
			Write-Host ""

			continue
		}

		$IPValid = $CustomIP -match `
			'^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'

		if (-not $IPValid) {

			Write-Host ""
			Write-Host "IP位址格式錯誤，請重新輸入。" -ForegroundColor Red
			Write-Host ""

			continue
		}
		break
	}

	while ($true) {
		$CustomUsername = Read-Host "使用者名稱"

		if ([string]::IsNullOrWhiteSpace($CustomUsername)) {
			Write-Host ""
			Write-Host "使用者名稱不可為空白，請重新輸入。" -ForegroundColor Red
			Write-Host ""

			continue
		}
		break
	}

	while ($true) {
		$CustomPassword = Read-Host "密碼"

		if ([string]::IsNullOrWhiteSpace($CustomPassword)) {

			Write-Host ""
			Write-Host "密碼不可為空白，請重新輸入。" -ForegroundColor Red
			Write-Host ""

			continue
		}
		break
	}

	$CustomServer = @{
		Name     = "自訂伺服器"
		IP       = $CustomIP
		Username = $CustomUsername
		Password = $CustomPassword
	}

	Show-FunctionMenu `
		-Server $CustomServer
}

# ============================================================
# 一：Server Selection
# ============================================================

function Show-ServerMenu {
	while ($true) {
		Show-Header

		Write-Host "伺服器選擇" -ForegroundColor Green
		Write-Host ""

		for ($i = 0; $i -lt $Servers.Count; $i++) {
			$Number = $i + 1
			$Server = $Servers[$i]

			$PowerStatus = Get-PowerStatus `
				-Server $Server

			switch ($PowerStatus) {
				"ON" {
					$StatusText = "開機"
				}
				"OFF" {
					$StatusText = "關機"
				}
				default {
					$StatusText = "未知"
				}
			}

			$Line = " [{0}] {1,-20}  [{2,-15}]  " -f `
				$Number,
				$Server.Name,
				$Server.IP
			Write-Host $Line -NoNewline

			switch ($PowerStatus) {
				"ON" {
					Write-Host $StatusText -ForegroundColor Green
				}
				"OFF" {
					Write-Host $StatusText -ForegroundColor Red
				}
				default {
					Write-Host $StatusText -ForegroundColor Yellow
				}
			}
		}

		Write-Host ""
		Write-Host " [99] 輸入自訂伺服器"
		Write-Host " [0] 離開"
		Write-Host ""

		$Choice = Read-Host "請選擇伺服器"

		if ($Choice -eq "99") {
			Show-CustomServerMenu
			continue
		}

		if ($Choice -eq "0") {
			Clear-Host

			Write-Host ""
			Write-Host "IPMITool Server Manager 已結束。" -ForegroundColor Cyan
			Write-Host ""

			return
		}

		if ($Choice -match "^\d+$") {
			$Index = [int]$Choice - 1

			if ($Index -ge 0 -and $Index -lt $Servers.Count) {
				Show-FunctionMenu `
					-Server $Servers[$Index]
			}
			else {
				Write-Host ""
				Write-Host "無效選擇。" -ForegroundColor Red

				Start-Sleep -Seconds 1
			}
		}
		else {
			Write-Host ""
			Write-Host "無效選擇。" -ForegroundColor Red

			Start-Sleep -Seconds 1
		}
	}
}

# ============================================================
# 二：Function Selection
# ============================================================

function Show-FunctionMenu {
	param (
		[hashtable]$Server
	)

	while ($true) {
		Show-Header

		Write-Host "Server : $($Server.Name)" -ForegroundColor Yellow
		Write-Host "IP     : $($Server.IP)" -ForegroundColor Yellow
		Write-Host ""
		Write-Host "功能選擇" -ForegroundColor Green
		Write-Host ""
		Write-Host " [1] 開機"
		Write-Host " [2] 重啟"
		Write-Host " [3] 關機"
		Write-Host " [4] 關閉電源"
		Write-Host " [5] 設備狀態"
		Write-Host ""
		Write-Host " [0] 返回伺服器選擇"
		Write-Host ""

		$Choice = Read-Host "請選擇功能"

		switch ($Choice) {

			# ------------------------------------------------
			# Power ON
			# ipmitool chassis power on
			# ------------------------------------------------

			"1" {
				Confirm-PowerAction `
					-Server $Server `
					-Action "開機 (Power ON)" `
					-Command @(
						"chassis",
						"power",
						"on"
					)
			}

			# ------------------------------------------------
			# Reset / Reboot
			# ipmitool chassis power reset
			# ------------------------------------------------

			"2" {
				Confirm-PowerAction `
					-Server $Server `
					-Action "重啟 (Hard Reset)" `
					-Command @(
						"chassis",
						"power",
						"reset"
					)
			}

			# ------------------------------------------------
			# Shutdown
			# ipmitool chassis power soft
			# ------------------------------------------------

			"3" {
				Confirm-PowerAction `
					-Server $Server `
					-Action "關機 (Shutdown)" `
					-Command @(
						"chassis",
						"power",
						"soft"
					)
			}

			# ------------------------------------------------
			# Power OFF
			# ipmitool chassis power off
			# ------------------------------------------------

			"4" {
				Show-Header

				Write-Host "Server : $($Server.Name)" -ForegroundColor Yellow
				Write-Host "IP     : $($Server.IP)" -ForegroundColor Yellow
				Write-Host ""
				Write-Host "!!! 警告 !!!" -ForegroundColor Red
				Write-Host ""
				Write-Host "這個操作會立即關閉伺服器的電源！" -ForegroundColor Red
				Write-Host "伺服器將會直接斷電！" -ForegroundColor Red
				Write-Host ""
				Write-Host "這個操作不是正常的系統關機，" -ForegroundColor Red
				Write-Host "請確認目前的工作階段已經儲存。" -ForegroundColor Red
				Write-Host ""
				$Confirm = Read-Host "若確定要關閉電源，請輸入 YES"

				if ($Confirm -eq "YES") {
					Invoke-IPMI `
						-Server $Server `
						-CommandArguments @(
							"chassis",
							"power",
							"off"
						)
				}
				else {
					Write-Host ""
					Write-Host "操作已取消。" -ForegroundColor Yellow

					Start-Sleep -Seconds 1
				}
			}

			# ------------------------------------------------
			# Enter Status Menu
			# ------------------------------------------------

			"5" {
				Show-StatusMenu `
					-Server $Server
			}

			"0" {
				return
			}

			default {
				Write-Host ""
				Write-Host "無效選擇。" -ForegroundColor Red

				Start-Sleep -Seconds 1
			}
		}
	}
}


# ============================================================
# 三：Status Selection
# ============================================================

function Show-StatusMenu {

	param (
		[hashtable]$Server
	)

	while ($true) {
		Show-Header

		Write-Host "Server : $($Server.Name)" -ForegroundColor Yellow
		Write-Host "IP     : $($Server.IP)" -ForegroundColor Yellow
		Write-Host ""
		Write-Host "狀態選擇" -ForegroundColor Green
		Write-Host ""
		Write-Host " [1] 電源狀態"
		Write-Host " [2] 感測器狀態"
		Write-Host " [3] 系統事件"
		Write-Host ""
		Write-Host " [0] 返回功能選擇"
		Write-Host ""

		$Choice = Read-Host "請選擇"

		switch ($Choice) {
			# ------------------------------------------------
			# Power Status
			# ipmitool chassis power status
			# ------------------------------------------------

			"1" {
				Invoke-IPMI `
					-Server $Server `
					-CommandArguments @(
						"chassis",
						"power",
						"status"
					)
			}

			# ------------------------------------------------
			# Sensor Status
			# ------------------------------------------------

			"2" {
				Show-SensorMenu `
					-Server $Server
			}

			# ------------------------------------------------
			# System Event Log
			# ------------------------------------------------

			"3" {
				Show-SELMenu `
					-Server $Server
			}

			"0" {
				return
			}
			default {
				Write-Host ""
				Write-Host "無效選擇。" -ForegroundColor Red

				Start-Sleep -Seconds 1
			}
		}
	}
}


# ============================================================
# 四之一：Sensor Menu
# ============================================================

function Show-SensorMenu {

	param (
		[hashtable]$Server
	)

	while ($true) {
		Show-Header

		Write-Host "Server : $($Server.Name)" -ForegroundColor Yellow
		Write-Host "IP     : $($Server.IP)" -ForegroundColor Yellow
		Write-Host ""
		Write-Host "感測器狀態" -ForegroundColor Green
		Write-Host ""
		Write-Host " [1] 簡易顯示感測器狀態"
		Write-Host " [2] 顯示所有感測器狀態"
		Write-Host " [3] 顯示感測器閾值"
		Write-Host ""
		Write-Host " [0] 返回狀態選擇"
		Write-Host ""

		$Choice = Read-Host "請選擇"

		switch ($Choice) {
			# ------------------------------------------------
			# Simple Sensor
			# ipmitool sdr
			# ------------------------------------------------

			"1" {

				Invoke-IPMI `
					-Server $Server `
					-CommandArguments @(
						"sdr"
					)
			}

			# ------------------------------------------------
			# All Sensors
			# ipmitool sensor
			# ------------------------------------------------

			"2" {
				Invoke-IPMI `
					-Server $Server `
					-CommandArguments @(
						"sensor"
					)
			}

			# ------------------------------------------------
			# Sensor Threshold
			# ipmitool sdr elist
			# ------------------------------------------------

			"3" {

				Invoke-IPMI `
					-Server $Server `
					-CommandArguments @(
						"sdr",
						"elist"
					)
			}

			"0" {
				return
			}

			default {
				Write-Host ""
				Write-Host "無效選擇。" -ForegroundColor Red

				Start-Sleep -Seconds 1
			}
		}
	}
}


# ============================================================
# 四之二：SEL Menu
# ============================================================

function Show-SELMenu {

	param (
		[hashtable]$Server
	)

	while ($true) {
		Show-Header

		Write-Host "Server : $($Server.Name)" -ForegroundColor Yellow
		Write-Host "IP     : $($Server.IP)" -ForegroundColor Yellow
		Write-Host ""
		Write-Host "系統事件" -ForegroundColor Green
		Write-Host ""
		Write-Host " [1] 顯示全部系統事件"
		Write-Host " [2] 顯示最後 5 筆"
		Write-Host " [3] 顯示最後 10 筆"
		Write-Host " [4] 清除所有系統事件"
		Write-Host ""
		Write-Host " [0] 返回狀態選擇"
		Write-Host ""
		$Choice = Read-Host "請選擇"

		switch ($Choice) {
			# ------------------------------------------------
			# Show All SEL
			# ipmitool sel elist
			# ------------------------------------------------

			"1" {
				Invoke-IPMI `
					-Server $Server `
					-CommandArguments @(
						"sel",
						"elist"
					)
			}

			# ------------------------------------------------
			# Last 5 SEL
			# ipmitool sel elist last 5
			# ------------------------------------------------

			"2" {
				Invoke-IPMI `
					-Server $Server `
					-CommandArguments @(
						"sel",
						"elist",
						"last",
						"5"
					)
			}

			# ------------------------------------------------
			# Last 10 SEL
			# ipmitool sel elist last 10
			# ------------------------------------------------

			"3" {
				Invoke-IPMI `
					-Server $Server `
					-CommandArguments @(
						"sel",
						"elist",
						"last",
						"10"
					)
			}

			# ------------------------------------------------
			# Clear SEL
			# ipmitool sel clear
			# ------------------------------------------------

			"4" {
				Show-Header

				Write-Host "Server : $($Server.Name)" -ForegroundColor Yellow
				Write-Host "IP     : $($Server.IP)" -ForegroundColor Yellow
				Write-Host ""
				Write-Host "!!! 警告 !!!" -ForegroundColor Red
				Write-Host ""
				Write-Host "這個操作會清除遠端機器上所有的系統事件！" -ForegroundColor Red
				Write-Host "清除後無法復原。" -ForegroundColor Red
				Write-Host ""
				$Confirm = Read-Host "若確定要清除，請輸入 YES"

				if ($Confirm -eq "YES") {
					Invoke-IPMI `
						-Server $Server `
						-CommandArguments @(
							"sel",
							"clear"
						)
				}
				else {
					Write-Host ""
					Write-Host "操作已取消。" -ForegroundColor Yellow

					Start-Sleep -Seconds 1
				}
			}

			"0" {
				return
			}

			default {
				Write-Host ""
				Write-Host "無效選擇。" -ForegroundColor Red

				Start-Sleep -Seconds 1
			}
		}
	}
}

# ============================================================
# Program Start
# ============================================================

Show-ServerMenu