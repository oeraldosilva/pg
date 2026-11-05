$ErrorActionPreference = "Stop"
$ImageUrl = "https://raw.githubusercontent.com/oeraldosilva/pg/main/wallpaper.jpg"
$Dir  = "C:\ProgramData\ICMP"
$Img  = "$Dir\wallpaper_pg.jpg"
$Log  = "$Dir\wallpaper_log.txt"

New-Item -ItemType Directory -Path $Dir -Force | Out-Null
function Log($m) { "$(Get-Date -Format s) | $m" | Out-File $Log -Append }

try {
    $isSystem = ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq "S-1-5-18")
    Log "iniciou | whoami=$(whoami) | system=$isSystem"

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $ImageUrl -OutFile $Img -UseBasicParsing
    Log "imagem baixada"

    if ($isSystem) {
        $exp = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" | Select-Object -First 1
        if (-not $exp) { Log "nenhum usuario logado; nada aplicado"; return }
        $sid  = (Invoke-CimMethod -InputObject $exp -MethodName GetOwnerSid).Sid
        $hive = "Registry::HKEY_USERS\$sid"
    } else {
        $hive = "HKCU:"
    }

    $desk = "$hive\Control Panel\Desktop"
    Set-ItemProperty -Path $desk -Name Wallpaper -Value $Img
    Set-ItemProperty -Path $desk -Name WallpaperStyle -Value "10"
    Set-ItemProperty -Path $desk -Name TileWallpaper -Value "0"
    Log "registro do usuario atualizado"

    if ($isSystem) {
        $pol1 = "$hive\Software\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop"
        $pol2 = "$hive\Software\Microsoft\Windows\CurrentVersion\Policies\System"
        foreach ($p in $pol1, $pol2) { if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null } }
        Set-ItemProperty -Path $pol1 -Name NoChangingWallPaper -Value 1 -Type DWord
        Set-ItemProperty -Path $pol2 -Name Wallpaper -Value $Img -Type String
        Set-ItemProperty -Path $pol2 -Name WallpaperStyle -Value "10" -Type String
        Log "bloqueio de alteracao aplicado"
    }

    $apply = @'
Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public class WP { [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int SystemParametersInfo(int a, int b, string c, int d); }'
[WP]::SystemParametersInfo(20, 0, 'C:\ProgramData\ICMP\wallpaper_pg.jpg', 3) | Out-Null
'@
    $applyFile = "$Dir\apply_wallpaper.ps1"
    Set-Content -Path $applyFile -Value $apply -Encoding ASCII

    if ($isSystem) {
        $user = (Get-CimInstance Win32_ComputerSystem).UserName
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$applyFile`""
        $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive
        Register-ScheduledTask -TaskName "ICMP_ApplyWallpaper" -Action $action -Principal $principal -Force | Out-Null
        Start-ScheduledTask -TaskName "ICMP_ApplyWallpaper"
        Start-Sleep -Seconds 5
        Unregister-ScheduledTask -TaskName "ICMP_ApplyWallpaper" -Confirm:$false
        Log "atualizacao imediata disparada para $user"
    } else {
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File $applyFile
        Log "atualizacao imediata aplicada"
    }
    Log "concluido"
} catch {
    Log "ERRO: $($_.Exception.Message)"
    exit 1
}