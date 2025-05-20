#!/bin/bash

# Función para formatear tablas con columnas alineadas
formatear_tabla() {
    local input="$1"
    echo "$input" | column -t -s $'\t'
}

# Función para mostrar el menú
mostrar_menu() {
    clear
    echo "=============================================="
    echo " Herramienta de Administración del Data Center"
    echo "=============================================="
    echo "1. Top 5 procesos que más CPU consumen"
    echo "2. Filesystems/discos conectados (tamaño y espacio libre)"
    echo "3. Archivo más grande en un filesystem específico"
    echo "4. Memoria libre y espacio swap en uso"
    echo "5. Conexiones de red activas (ESTABLISHED)"
    echo "6. Salir"
    echo "=============================================="
    echo -n "Seleccione una opción [1-6]: "
}

# Función para los 5 procesos que más CPU consumen
top_procesos_cpu() {
    echo -e "\nTop 5 procesos que más CPU consumen:\n"
    ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu | head -n 6 | awk '
    BEGIN {printf "%-8s %-10s %-6s %-6s %-20s\n", "PID", "USUARIO", "%CPU", "%MEM", "PROCESO"}
    NR>1 {printf "%-8d %-10s %-6.1f %-6.1f %-20s\n", $1, $2, $3, $4, $5}'
    read -p $'\nPresione Enter para continuar...'
}

# Función para mostrar filesystems/discos
mostrar_filesystems() {
    local fs_info=$(df -h --output=source,size,avail,pcent,fstype,target | awk '
    BEGIN {print "DISPOSITIVO\tTAMAÑO\tDISPONIBLE\tUSO%\tTIPO\tPUNTO DE MONTAJE"}
    NR>1 {print $1"\t"$2"\t"$3"\t"$4"\t"$5"\t"$6}')

    echo -e "\nFilesystems/discos conectados:\n"
    formatear_tabla "$fs_info"

    local fs_bytes=$(df --block-size=1 --output=source,size,avail,pcent,target | awk '
    BEGIN {print "DISPOSITIVO\tTAMAÑO(B)\tDISPONIBLE(B)\tUSO%\tPUNTO DE MONTAJE"}
    NR>1 {printf "%s\t%d\t%d\t%s\t%s\n", $1, $2, $3, $4, $5}')

    echo -e "\nInformación detallada en bytes:\n"
    formatear_tabla "$fs_bytes"

    read -p $'\nPresione Enter para continuar...'
}

archivo_mas_grande() {
    echo -e "\nFilesystems disponibles:\n"

    # Listado de filesystems con punto de montaje
    local fs_list=$(df --output=source,target | tail -n +2 | nl -w 3 -s ". " | awk -F'\t' '{printf "%-3s %-20s %-30s\n", $1, $2, $3}')
    echo -e "NÚM. DISPOSITIVO          PUNTO DE MONTAJE\n"
    echo "$fs_list"

    while true; do
        echo -e "\nIngrese número del filesystem a analizar, o escriba la ruta del punto de montaje."
        echo -e "Ingrese 0 para cancelar."
        read -p "Selección: " input

        # Cancelar
        if [[ "$input" == "0" ]]; then
            return
        fi

        # Si la entrada es un número, elegir filesystem del listado
        if [[ "$input" =~ ^[0-9]+$ ]]; then
            local total_fs=$(df --output=source | tail -n +2 | wc -l)
            if [ "$input" -lt 1 ] || [ "$input" -gt "$total_fs" ]; then
                echo "Error: Número fuera de rango. Por favor seleccione entre 1 y $total_fs."
                continue
            fi
            local mount_point=$(df --output=target | tail -n +2 | sed -n "${input}p")
        else
            # Si no es número, se asume ruta
            local mount_point="$input"

            # Validar que la ruta exista y sea un directorio
            if [ ! -d "$mount_point" ]; then
                echo "Error: La ruta '$mount_point' no existe o no es un directorio."
                continue
            fi

            # Validar que sea un punto de montaje
            if ! mountpoint -q "$mount_point"; then
                echo "Advertencia: La ruta '$mount_point' no es un punto de montaje reconocido."
                read -p "¿Desea continuar igual? (s/n): " yn
                case "$yn" in
                [Ss]*) ;;
                *) continue ;;
                esac
            fi
        fi

        # Preguntar si quiere usar sudo para evitar errores de permisos
        read -p "¿Desea ejecutar la búsqueda con sudo para evitar problemas de permisos? (s/n): " usar_sudo
        if [[ "$usar_sudo" =~ ^[Ss]$ ]]; then
            find_cmd="sudo find"
        else
            find_cmd="find"
        fi

        echo -e "\nBuscando el archivo más grande en '$mount_point'...\n"

        local largest_file=$($find_cmd "$mount_point" -xdev -type f -printf "%s\t%p\n" 2>/dev/null | sort -nr | head -n 1)

        if [ -z "$largest_file" ]; then
            echo "No se encontraron archivos accesibles o el filesystem está vacío."
        else
            local size=$(echo "$largest_file" | awk '{print $1}')
            local path=$(echo "$largest_file" | awk '{print $2}')
            local human_size=$(numfmt --to=iec --from-unit=1 $size)

            echo -e "\nArchivo más grande encontrado:"
            echo "--------------------------------"
            printf "%-12s: %s\n" "Tamaño" "$human_size ($size bytes)"
            printf "%-12s: %s\n" "Ubicación" "$path"
            echo "--------------------------------"
        fi

        read -p $'\nPresione Enter para continuar...'
        return
    done
}

# Función para mostrar memoria y swap
memoria_swap() {
    # Función para centrar texto en un ancho dado
    center_text() {
        local text="$1"
        local width="$2"
        local text_length=${#text}
        local left_padding=$(((width - text_length) / 2))
        local right_padding=$((width - text_length - left_padding))
        printf "%${left_padding}s%s%${right_padding}s" "" "$text" ""
    }

    echo -e "\nInformación de memoria y swap:\n"

    # Memoria
    local mem_info=$(free -b | awk '/Mem/ {print $2,$4,$3,$7}')
    local total_mem=$(echo $mem_info | awk '{print $1}')
    local free_mem=$(echo $mem_info | awk '{print $2}')
    local used_mem=$(echo $mem_info | awk '{print $3}')
    local avail_mem=$(echo $mem_info | awk '{print $4}')

    # Swap
    local swap_info=$(free -b | awk '/Swap/ {print $2,$3}')
    local total_swap=$(echo $swap_info | awk '{print $1}')
    local used_swap=$(echo $swap_info | awk '{print $2}')

    # Cálculos de porcentajes
    local used_mem_pct=$(awk "BEGIN {printf \"%.1f\", ($used_mem/$total_mem)*100}")
    local free_mem_pct=$(awk "BEGIN {printf \"%.1f\", ($free_mem/$total_mem)*100}")
    local avail_mem_pct=$(awk "BEGIN {printf \"%.1f\", ($avail_mem/$total_mem)*100}")

    local swap_pct=0
    [ "$total_swap" -ne 0 ] && swap_pct=$(awk "BEGIN {printf \"%.1f\", ($used_swap/$total_swap)*100}")

    # Formatear tamaños legibles
    local total_mem_h=$(numfmt --to=iec --from-unit=1 $total_mem)
    local used_mem_h=$(numfmt --to=iec --from-unit=1 $used_mem)
    local free_mem_h=$(numfmt --to=iec --from-unit=1 $free_mem)
    local avail_mem_h=$(numfmt --to=iec --from-unit=1 $avail_mem)
    local total_swap_h=$(numfmt --to=iec --from-unit=1 $total_swap)
    local used_swap_h=$(numfmt --to=iec --from-unit=1 $used_swap)

    # Definir anchos de columnas
    local col1_width=20
    local col2_width=20
    local col3_width=20
    local col4_width=15

    # Mostrar tabla de memoria con contenido centrado
    echo "MEMORIA:"
    echo "-------------------------------------------------------------------------------"
    # Encabezados centrados
    printf "%-${col1_width}s %-${col2_width}s %-${col3_width}s %-${col4_width}s\n" \
        "$(center_text "TIPO" $col1_width)" \
        "$(center_text "TOTAL" $col2_width)" \
        "$(center_text "USADO" $col3_width)" \
        "$(center_text "LIBRE" $col4_width)"

    # Datos centrados
    printf "%-${col1_width}s %-${col2_width}s %-${col3_width}s %-${col4_width}s\n" \
        "$(center_text "Física:" $col1_width)" \
        "$(center_text "$total_mem_h" $col2_width)" \
        "$(center_text "$used_mem_h ($used_mem_pct%)" $col3_width)" \
        "$(center_text "$free_mem_h ($free_mem_pct%)" $col4_width)"

    printf "%-${col1_width}s %-${col2_width}s %-${col3_width}s %-${col4_width}s\n" \
        "$(center_text "Disponible:" $col1_width)" \
        "$(center_text "-" $col2_width)" \
        "$(center_text "-" $col3_width)" \
        "$(center_text "$avail_mem_h ($avail_mem_pct%)" $col4_width)"

    echo "-------------------------------------------------------------------------------"

    # Mostrar tabla de swap si existe con contenido centrado
    if [ "$total_swap" -ne 0 ]; then
        echo -e "\nSWAP:"
        echo "-------------------------------------------------------------------------------"
        printf "%-${col1_width}s %-${col2_width}s %-${col3_width}s\n" \
            "$(center_text " " $col1_width)" \
            "$(center_text "TOTAL" $col2_width)" \
            "$(center_text "USADO" $col3_width)"

        printf "%-${col1_width}s %-${col2_width}s %-${col3_width}s\n" \
            "$(center_text " " $col1_width)" \
            "$(center_text "$total_swap_h" $col2_width)" \
            "$(center_text "$used_swap_h ($swap_pct%)" $col3_width)"

        echo "-------------------------------------------------------------------------------"
    else
        echo -e "\nNo hay espacio swap configurado."
    fi

    read -p $'\nPresione Enter para continuar...'
}

# Función para conexiones de red establecidas
conexiones_red() {
    echo -e "\nConexiones de red activas (ESTABLISHED):\n"

    # Verificar si ss o netstat está disponible
    if command -v ss &>/dev/null; then
        local conn_count=$(ss -tun state established | tail -n +2 | wc -l)
        echo "Total de conexiones ESTABLISHED: $conn_count"

        if [ "$conn_count" -eq 0 ]; then
            echo -e "\nNo hay conexiones de red activas (ESTABLISHED) en este momento."
        else
            echo -e "\nDetalles:"
            echo "------------------------------------------------------------"
            ss -tunp state established | awk '
            NR==1 {printf "%-25s %-25s %-12s %-15s\n", "ORIGEN", "DESTINO", "ESTADO", "PROCESO"}
            NR>1 {
                split($5, origen, ":");
                split($6, destino, ":");
                proc = $7;
                gsub(/users:\(/, "", proc);
                gsub(/\)/, "", proc);
                printf "%-25s %-25s %-12s %-15s\n", 
                    origen[1]":"origen[2], 
                    destino[1]":"destino[2], 
                    "ESTABLISHED", 
                    proc
            }'
        fi
    elif command -v netstat &>/dev/null; then
        local conn_count=$(netstat -tun | grep ESTABLISHED | wc -l)
        echo "Total de conexiones ESTABLISHED: $conn_count"

        if [ "$conn_count" -eq 0 ]; then
            echo -e "\nNo hay conexiones de red activas (ESTABLISHED) en este momento."
        else
            echo -e "\nDetalles:"
            echo "------------------------------------------------------------"
            netstat -tunp | grep ESTABLISHED | awk '
            {
                split($4, origen, ":");
                split($5, destino, ":");
                proc = $7;
                printf "%-25s %-25s %-12s %-15s\n", 
                    origen[1]":"origen[2], 
                    destino[1]":"destino[2], 
                    "ESTABLISHED", 
                    proc
            }'
        fi
    else
        echo "Error: No se encontró 'ss' ni 'netstat' para verificar conexiones."
    fi

    read -p $'\nPresione Enter para continuar...'
}

# Bucle principal del menú
while true; do
    mostrar_menu
    read opcion

    case $opcion in
    1) top_procesos_cpu ;;
    2) mostrar_filesystems ;;
    3) archivo_mas_grande ;;
    4) memoria_swap ;;
    5) conexiones_red ;;
    6)
        echo -e "\nSaliendo del programa..."
        exit 0
        ;;
    *)
        echo -e "\nOpción no válida. Intente nuevamente."
        read -p "Presione Enter para continuar..."
        ;;
    esac
done
