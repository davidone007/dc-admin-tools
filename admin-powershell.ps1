<#
.SYNOPSIS
Herramienta de Administración de Data Center que muestra información del sistema.

.DESCRIPTION
Este script permite monitorear y administrar aspectos clave de un sistema Windows, incluyendo:
- Procesos con mayor uso de CPU.
- Información de discos conectados y su uso.
- Búsqueda del archivo más grande en una ruta especificada.
- Información sobre memoria RAM y uso de swap.
- Conexiones de red activas en estado ESTABLISHED.

Permite ejecutarse en modo interactivo mediante un menú, o pasando una opción como parámetro para ejecución directa.

.PARAMETER Option
Opción a ejecutar directamente al iniciar el script:
  0 - Salir
  1 - Mostrar los 5 procesos que más CPU consumen (en %)
  2 - Mostrar discos conectados con tamaño, libre, usado y porcentaje
  3 - Mostrar el archivo más grande en un disco o ruta especificada
  4 - Mostrar memoria libre y uso de swap (en unidades legibles y %)
  5 - Mostrar número de conexiones activas y detalles (ESTABLISHED)

.EXAMPLE
.\admin-powershell.ps1
Inicia la herramienta en modo interactivo mostrando el menú.

.EXAMPLE
.\admin-powershell.ps1 -Option 2
Muestra directamente información de los discos conectados.

.EXAMPLE
.\admin-powershell.ps1 -Option 0
Sale inmediatamente del script.

#>

# Activamos binding de cmdlets para definir parámetros y validaciones
[CmdletBinding()]
param(
    # Parámetro de entrada llamado Option que solo acepta valores específicos de string "0" a "5"
    [ValidateSet("0","1","2","3","4","5")]
    [string]$Option = ""  # Valor por defecto vacío (modo interactivo)
)

# Función para formatear bytes en unidades legibles (KB, MB, GB, TB, PB)
function Format-Bytes {
    param([long]$bytes)

    # Convertimos el número de bytes a la unidad más grande posible y devolvemos string formateado con 2 decimales
    switch ($bytes) {
        {$_ -ge 1PB} { return "{0:N2} PB" -f ($bytes / 1PB) }
        {$_ -ge 1TB} { return "{0:N2} TB" -f ($bytes / 1TB) }
        {$_ -ge 1GB} { return "{0:N2} GB" -f ($bytes / 1GB) }
        {$_ -ge 1MB} { return "{0:N2} MB" -f ($bytes / 1MB) }
        {$_ -ge 1KB} { return "{0:N2} KB" -f ($bytes / 1KB) }
        default     { return "$bytes B" }
    }
}

# Función que limpia la pantalla y muestra el menú principal con opciones disponibles
function Show-Menu {
    Clear-Host
    Write-Host "=== Herramienta de Administración de Data Center ===`n"
    Write-Host "1. Mostrar los 5 procesos que más CPU consumen (en %)"
    Write-Host "2. Mostrar discos conectados con tamaño, libre, usado y porcentaje"
    Write-Host "3. Mostrar el archivo más grande en un disco o ruta especificada"
    Write-Host "4. Mostrar memoria libre y uso de swap (en unidades legibles y %)"
    Write-Host "5. Mostrar número de conexiones activas y detalles (ESTABLISHED)"
    Write-Host "0. Salir"
}

# Función para pausar la ejecución y esperar que el usuario presione ENTER antes de continuar
function Pause-AndContinue {
    Write-Host ""
    Read-Host "Presione ENTER para continuar..."
}

function Top-CPUProcesses {
    Clear-Host
    Write-Host "`n>> Procesos que más CPU consumen:`n"

    Write-Host "Seleccione el método para mostrar el uso de CPU:"
    Write-Host "1. CPU acumulado desde el inicio del proceso (menos preciso, más rápido)"
    Write-Host "2. CPU actual en porcentaje (medición instantánea en tiempo real)"
    $metodo = Read-Host "Ingrese 1 o 2"

    if ($metodo -eq "1") {
        # Método 1: CPU acumulado desde el inicio
        $top = Get-Process |
            Sort-Object -Property CPU -Descending |
            Select-Object -First 5 |
            Select-Object `
                @{Name='PID';Expression={$_.Id}},
                @{Name='Proceso';Expression={$_.ProcessName}},
                @{Name='CPU Acumulado (s)';Expression={[math]::Round($_.CPU, 4)}},
                @{Name='Memoria (MB)';Expression={[math]::Round($_.WorkingSet64 / 1MB, 2)}},
                @{Name='Estado';Expression={if ($_.Responding) {'Activo'} else {'No responde'}}}

        Write-Host "`nTop 5 procesos por CPU acumulado desde el inicio:`n"
        $top | Format-Table -AutoSize

    } elseif ($metodo -eq "2") {
    Write-Host "`nObteniendo uso actual de CPU por proceso (medición instantánea)...`n"

    $cpuData = Get-WmiObject Win32_PerfFormattedData_PerfProc_Process |
        Where-Object { $_.Name -notmatch '_Total|Idle' -and $_.PercentProcessorTime -ne $null } |
        Sort-Object {[double]($_.PercentProcessorTime)} -Descending |
        Select-Object -First 5 |
        ForEach-Object {
            $procInfo = Get-Process -Id $_.IDProcess -ErrorAction SilentlyContinue
            $memoria = if ($procInfo) { [math]::Round($procInfo.WorkingSet64 / 1MB, 2) } else { "N/A" }

            

            [PSCustomObject]@{
                "PID"           = $_.IDProcess
                "Proceso"       = $_.Name
                "CPU (%)"       = "{0:N4}" -f $_.PercentProcessorTime
                "Memoria (MB)"  = $memoria
             
            }
        }

    if ($cpuData.Count -eq 0) {
        Write-Host "⚠️ No se detectó uso de CPU significativo en este instante."
    } else {
        Write-Host "`nTop 5 procesos por uso actual de CPU:`n"
        $cpuData | Format-Table -AutoSize
    }
}


    Pause-AndContinue
}





# Función que muestra información de discos conectados (tamaño total, usado, libre y % usado)
function Show-Disks {
    Write-Host "`n>> Discos conectados:`n"

    # Obtenemos las unidades que tengan sistema de archivos y espacio libre definido
    $disks = Get-PSDrive -PSProvider 'FileSystem' | Where-Object { $_.Free -ne $null }

    # Validamos si hay discos
    if ($disks.Count -eq 0) {
        Write-Host "No se encontraron discos o sistemas de archivos."
    } else {
        # Para cada disco calculamos y mostramos información formateada
        $formatted = $disks | ForEach-Object {
            $total = $_.Used + $_.Free      # Total = usado + libre
            $used = $_.Used
            $percent = if ($total -gt 0) { [math]::Round(($used / $total) * 100, 2) } else { 0 }

            # Retornamos un objeto personalizado para mejor visualización
            [PSCustomObject]@{
                "Disco"     = "$($_.Name):\"
                "Total (Bytes)"    = $total
                "Total (Legible)"  = Format-Bytes $total
                "Usado (Bytes)"    = $used
                "Usado (Legible)"  = Format-Bytes $used
                "Libre (Bytes)"    = $_.Free
                "Libre (Legible)"  = Format-Bytes $_.Free
                "Usado (%)" = "$percent %"
            }
        }
        # Mostramos en tabla con ancho automático para mejor lectura
        $formatted | Format-Table -AutoSize
    }
    Pause-AndContinue
}

# Función para buscar y mostrar el archivo más grande dentro de un disco o ruta ingresada
function Largest-File {
    Write-Host "`n>> Buscar archivo más grande"

    # Listamos los discos para que el usuario pueda elegir
    $disks = Get-PSDrive -PSProvider 'FileSystem' | Where-Object { $_.Free -ne $null }

    # Validamos si hay discos
    if ($disks.Count -eq 0) {
        Write-Host "No hay discos disponibles para explorar."
        Pause-AndContinue
        return
    }

    # Mostramos opciones para que el usuario elija un disco o ingrese ruta manual
    Write-Host "`nSeleccione una unidad de la lista o escriba una ruta personalizada:"
    $i = 1
    foreach ($d in $disks) {
        Write-Host "$i. $($d.Name):\"
        $i++
    }
    Write-Host "$i. Ingresar ruta personalizada"

    # Leemos opción del usuario
    $option = Read-Host "Ingrese el número de su elección"

    # Validamos entrada como número
    if ($option -match '^\d+$') {
        $index = [int]$option
        # Si eligió un disco válido
        if ($index -ge 1 -and $index -le $disks.Count) {
            $path = "$($disks[$index - 1].Root)"
        # Si eligió la opción para ingresar ruta
        } elseif ($index -eq $disks.Count + 1) {
            $path = Read-Host "Ingrese la ruta completa a buscar (ej. C:\Carpeta)"
        } else {
            Write-Host "Opción inválida."
            Pause-AndContinue
            return
        }
    } else {
        Write-Host "Entrada inválida. Debe ser un número."
        Pause-AndContinue
        return
    }

    # Verificamos que la ruta exista y sea accesible
    if (-Not (Test-Path $path)) {
        Write-Host "La ruta '$path' no existe o no es accesible."
        Pause-AndContinue
        return
    }

    Write-Host "`nBuscando archivo más grande en $path (esto puede tardar)...`n"

    try {
        # Buscamos recursivamente el archivo con mayor tamaño
        $file = Get-ChildItem -Path $path -Recurse -File -ErrorAction SilentlyContinue |
            Sort-Object Length -Descending | Select-Object -First 1

        # Mostramos resultados si lo encontramos
        if ($file) {
            Write-Host "Archivo más grande encontrado:`n"
            Write-Host "Ruta: $($file.FullName)"
            Write-Host "Tamaño: $($file.Length) bytes ($(Format-Bytes $file.Length))"
        } else {
            Write-Host "No se encontraron archivos en la ruta especificada."
        }
    } catch {
        # Capturamos y mostramos error en caso de problemas de acceso o permisos
        Write-Host "Error al acceder a los archivos: $_"
    }

    Pause-AndContinue
}

# Función que muestra la información de memoria RAM y swap, tanto en bytes como en porcentaje
function Show-MemoryAndSwap {
    Write-Host "`n>> Información de memoria y swap:`n"
    try {
        # Obtenemos información del sistema operativo para memoria
        $os = Get-CimInstance Win32_OperatingSystem
        # Memoria física libre en bytes (FreePhysicalMemory está en KB)
        $free = [int64]$os.FreePhysicalMemory * 1KB
        # Memoria física total en bytes (TotalVisibleMemorySize en KB)
        $total = [int64]$os.TotalVisibleMemorySize * 1KB
        # Memoria usada es total menos libre
        $used = $total - $free
        # Calculamos porcentaje de uso de RAM
        $usedPercent = [math]::Round(($used / $total) * 100, 2)

        # Para swap se usa memoria virtual total y libre en KB
        $swapTotal = [int64]$os.TotalVirtualMemorySize * 1KB
        $swapFree = [int64]$os.FreeVirtualMemory * 1KB
        $swapUsed = $swapTotal - $swapFree
        $swapPercent = [math]::Round(($swapUsed / $swapTotal) * 100, 2)

        # Creamos objetos para mostrar RAM y swap con sus datos
        $info = [PSCustomObject]@{
            "Tipo"       = "RAM"
            "Total (Bytes)" = $total
            "Total (Legible)" = Format-Bytes $total
            "Usada (Bytes)" = $used
            "Usada (Legible)" = Format-Bytes $used
            "Libre (Bytes)" = $free
            "Libre (Legible)" = Format-Bytes $free
            "Uso (%)"    = "$usedPercent %"
        }, [PSCustomObject]@{
            "Tipo"       = "Swap"
            "Total (Bytes)" = $swapTotal
            "Total (Legible)" = Format-Bytes $swapTotal
            "Usada (Bytes)" = $swapUsed
            "Usada (Legible)" = Format-Bytes $swapUsed
            "Libre (Bytes)" = $swapFree
            "Libre (Legible)" = Format-Bytes $swapFree
            "Uso (%)"    = "$swapPercent %"
        }

        # Mostramos en tabla para fácil lectura
        $info | Format-Table -AutoSize

    } catch {
        Write-Host "Error al obtener información de memoria: $_"
    }
    Pause-AndContinue
}

# Función que muestra las conexiones activas TCP en estado ESTABLISHED
function Show-ActiveConnections {
    Write-Host "`n>> Conexiones activas (TCP ESTABLISHED):`n"

    try {
        # Obtenemos todas las conexiones TCP activas
        $connections = Get-NetTCPConnection -State Established -ErrorAction Stop
        # Contamos cuántas conexiones hay
        $count = $connections.Count

        # Mostramos cantidad total de conexiones establecidas
        Write-Host "Número de conexiones activas: $count`n"

        # Si hay conexiones, mostramos una tabla con detalles relevantes
        if ($count -gt 0) {
            $connections | Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State |
                Format-Table -AutoSize
        }
    } catch {
        # En caso de error probable por permisos o comandos no disponibles
        Write-Host "Error al obtener conexiones de red. Asegúrese de ejecutar con privilegios adecuados."
    }
    Pause-AndContinue
}

# Función que ejecuta la opción seleccionada, llamando a la función correspondiente
function Execute-Option {
    param([string]$opt)

    switch ($opt) {
        "0" { Write-Host "Saliendo..."; exit }
        "1" { Top-CPUProcesses }
        "2" { Show-Disks }
        "3" { Largest-File }
        "4" { Show-MemoryAndSwap }
        "5" { Show-ActiveConnections }
        default {
            Write-Host "Opción inválida."
            Pause-AndContinue
        }
    }
}

# Bloque principal del script
# Si se pasó una opción en línea de comandos, se ejecuta directamente esa opción y luego termina
if ($Option -ne "") {
    Execute-Option -opt $Option
    exit
}

# Si no se pasó opción, se inicia modo interactivo con menú en un ciclo infinito
while ($true) {
    Show-Menu
    $choice = Read-Host "Seleccione una opción"
    Execute-Option -opt $choice
}
