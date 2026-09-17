# IPMImgr
IPMI伺服器管理腳本，可自定義伺服器清單。

<br />

## 這是什麼？
**IPMI Server Manager**（簡稱：IPMImgr）
是一個簡單操作、可自定義伺服器清單的IPMI管理腳本。

<br />

## 功能特色
1. 使用PowerShell，搭配一鍵啟動執行檔，省去繁瑣的設定。
2. 獨立設定檔，使用json格式，方便伺服器增減。
3. 支援IPMITool電源切換、及伺服器狀態顯示。
4. 階層式選單與操作確認，避免下錯指令。

<br />

## 執行環境
可以在 `Windows` 平台上執行，只需備妥 `IPMITool.exe`。<br>
必須使用Powershell 5.1或更高版本。

<br />

## 操作說明
請先將 `ipmitool.exe` 放置於腳本根目錄，<br>
執行 `run_IPMImgr.cmd` 即可啟動腳本。<br>
輸入 `99` 可設定一次性伺服器目標。

<br />

## 設定說明
所有設定皆讀取自 `IPMImgr_cfg.json` 。<br>
<br />
IPMI 區塊：<br>
`Interface` 設定協定，預設為lanplus。<br>
`CipherSuite` 設定加密，預設為3。<br>
`PowerStatusTimeout`設定電源狀態檢測逾時，預設為1.5秒。<br>

Servers 區塊：<br>
`Name` 設定伺服器識別名稱。<br>
`IP` 設定伺服器位址。<br>
`Username` 設定IPMI登入帳號。<br>
`Password` 設定IPMI登入密碼。<br>

<br />

## 授權條款

此腳本遵循 [GNU General Public License 3.0](https://www.gnu.org/licenses/gpl-3.0.zh-tw.html) 授權條款。
