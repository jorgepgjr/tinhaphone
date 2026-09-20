[CmdletBinding()]
param(
    [string]$Emulator = 'Pixel9'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Join-Path $PSScriptRoot 'tinhaphone'

# O Gradle usa um canal local cujo caminho excede o limite do Windows quando
# TEMP aponta para a pasta profunda do perfil do usuário. Um diretório curto
# evita "Unable to establish loopback connection" durante o build Android.
$gradleTemp = 'C:\tmp'
New-Item -ItemType Directory -Force -Path $gradleTemp | Out-Null
$env:TEMP = $gradleTemp
$env:TMP = $gradleTemp

function Get-AndroidDevice {
    $devices = flutter devices --machine | ConvertFrom-Json
    return $devices | Where-Object { $_.targetPlatform -like 'android*' } | Select-Object -First 1
}

Push-Location $projectRoot
try {
    $androidDevice = Get-AndroidDevice
    if (-not $androidDevice) {
        flutter emulators --launch $Emulator
        if ($LASTEXITCODE -ne 0) {
            throw "Não foi possível abrir o emulador '$Emulator'."
        }

        Write-Host 'Aguardando o Android terminar de iniciar...'
        $deadline = (Get-Date).AddMinutes(3)
        do {
            Start-Sleep -Seconds 5
            $androidDevice = Get-AndroidDevice
        } while (-not $androidDevice -and (Get-Date) -lt $deadline)
    }

    if (-not $androidDevice) {
        throw 'Nenhum dispositivo Android ficou disponível em até 3 minutos.'
    }

    flutter run -d $androidDevice.id
}
finally {
    Pop-Location
}
