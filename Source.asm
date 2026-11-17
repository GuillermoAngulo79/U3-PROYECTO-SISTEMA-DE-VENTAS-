; ==========================================================================
; ==========================================================================
; VERSION UNIDAD 3 (COMPLETA): macros, procedimientos y USES.
; Mitad 1 (HECHA): menu, submenu, alta, busqueda, listado, resumen, captura,
;                  conversiones, validadores y busqueda de codigos.
; Mitad 2 (HECHA): Recibir, Vender, salidas y archivos (Guardar/Cargar/
;                  ValidarBufferArchivo) con macros, USES y procedimientos.
; ==========================================================================
; Author: Arnoldo Y Guillermo
; Program Name: Sistema de componentes de PC y hardware
; Program Description: Inventario y ventas en consola (MASM x86 32 bits, Irvine32)
; Date:
;
; RESUMEN DE LA ARQUITECTURA
;  - Datos: 4 arreglos paralelos (codigos, nombres, precios, stock). El producto
;    numero i usa la posicion i de cada arreglo. ESI se usa como INDICE i:
;        codigo = codigos + i*8      nombre = nombres + i*26
;        precio = precios[i*4]       stock  = stock[i*4]
;  - Dinero: siempre en CENTAVOS enteros (185.50 MXN = 18550).
;  - Convertidores propios: ParseMXN / ParseStock (cadena -> numero),
;    PrintMXN / PrintUInt (numero -> cadena). No se usa ReadDec/WriteDec/etc.
;  - Regla de negocio: DESCUENTO POR CANTIDAD (10% desde 10 unidades).
;  - Archivo "inventario.dat" (formato fijo de 428 bytes):
;        offset   0 : firma "INV1" (4 bytes)
;        offset   4 : numero de productos (DWORD)
;        offset   8 : arreglo codigos  (10 x 8  = 80 bytes)
;        offset  88 : arreglo nombres  (10 x 26 = 260 bytes)
;        offset 348 : arreglo precios  (10 x 4  = 40 bytes)
;        offset 388 : arreglo stock    (10 x 4  = 40 bytes)
; ==========================================================================

INCLUDE Irvine32.inc

; --- MostrarMsg -----------------------------------------------------------
; Muestra una cadena terminada en 00h.
; Parametro : texto = etiqueta de la cadena en .data
; Modifica  : EDX
MostrarMsg MACRO texto
    mov  edx, OFFSET texto
    call WriteString
ENDM

; --- MostrarYPausa --------------------------------------------------------
; Muestra un mensaje y espera una tecla (patron de todos los errores).
; Parametro : texto = etiqueta de la cadena
; Modifica  : EDX (Pausa conserva EAX)
MostrarYPausa MACRO texto
    MostrarMsg texto
    call Pausa
ENDM

; --- PedirCadena ----------------------------------------------------------
; Lee una cadena con ReadString dejando espacio para el 00h (SIZEOF - 1).
; Parametro : buffer = nombre del arreglo BYTE donde se guarda la entrada
; Salida    : EAX = numero de caracteres leidos
; Modifica  : EAX, ECX, EDX
PedirCadena MACRO buffer
    mov  edx, OFFSET buffer
    mov  ecx, SIZEOF buffer - 1
    call ReadString
ENDM

; --- LeerOpcion -----------------------------------------------------------
; Lee una opcion de menu de EXACTAMENTE 1 caracter y la deja en AL.
; Parametro : invalida = etiqueta a la que se salta si no mide 1 caracter
; Salida    : AL = caracter tecleado
; Modifica  : EAX, ECX, EDX
LeerOpcion MACRO invalida
    PedirCadena opcion_str
    cmp  eax, 1
    jne  invalida
    mov  al, opcion_str[0]
ENDM

; --- MostrarCampoUInt -----------------------------------------------------
; Muestra "etiqueta valor" y salto de linea (valor como entero sin signo).
; Parametros: etiqueta = cadena de .data ; valor = registro o variable DWORD
; Modifica  : EAX, EDX
MostrarCampoUInt MACRO etiqueta, valor
    MostrarMsg etiqueta
    mov  eax, valor
    call PrintUInt
    call Crlf
ENDM

; --- MostrarCampoMXN ------------------------------------------------------
; Muestra "etiqueta importe MXN" (PrintMXN ya agrega la etiqueta y el salto).
; Parametros: etiqueta = cadena de .data ; valor = centavos (registro/variable)
; Modifica  : EAX, EDX
MostrarCampoMXN MACRO etiqueta, valor
    MostrarMsg etiqueta
    mov  eax, valor
    call PrintMXN
ENDM

; --- MostrarElemento ------------------------------------------------------
; Muestra la cadena del producto cuyo indice esta en ESI.
; Direccion = OFFSET arreglo + ESI * tam
; Parametros: arreglo = codigos o nombres ; tam = LONG_COD o LONG_NOM
; Entrada   : ESI = indice del producto
; Modifica  : EDX
MostrarElemento MACRO arreglo, tam
    imul edx, esi, tam
    add  edx, OFFSET arreglo
    call WriteString
ENDM

; --- EnRango --------------------------------------------------------------
; Comparacion sin signo: salta a "fuera" si reg < minimo o reg > maximo.
; Sustituye el par cmp/jb + cmp/ja que se repetia en validaciones.
; Parametros: reg = registro ; minimo, maximo = constantes ; fuera = etiqueta
; Modifica  : solo banderas
EnRango MACRO reg, minimo, maximo, fuera
    cmp  reg, minimo
    jb   fuera
    cmp  reg, maximo
    ja   fuera
ENDM

; --- MostrarSiNo (con LOCAL) ---------------------------------------------
; Muestra SI o NO segun una variable sea distinta de 0 o igual a 0.
; Lleva etiquetas internas: se declaran con LOCAL para que cada expansion
; genere nombres distintos (si no, 2 usos darian "etiqueta duplicada").
; Parametro : bandera = variable o registro
; Modifica  : EDX y banderas
MostrarSiNo MACRO bandera
    LOCAL esNo, fin
    cmp  bandera, 0
    je   esNo
    MostrarMsg txtSi
    jmp  fin
esNo:
    MostrarMsg txtNo
fin:
ENDM

; --- ExigirProductos ------------------------------------------------------
; Salta a "sinProductos" si el catalogo esta vacio. Se repetia al inicio de
; Recibir y Vender (cmp total_prods, 0 / je ...).
; Parametro : sinProductos = etiqueta donde se avisa que no hay productos
; Modifica  : solo banderas
ExigirProductos MACRO sinProductos
    cmp  total_prods, 0
    je   sinProductos
ENDM

; --- LimpiarBloque --------------------------------------------------------
; Pone en 00h 'cantidad' BYTES a partir de OFFSET destino (REP STOSB).
; Parametros: destino = etiqueta (o etiqueta+desplazamiento) ;
;             cantidad = numero de bytes (constante o registro)
; Requiere  : DF = 0 (CLD hecho antes)
; Modifica  : EAX, ECX, EDI
LimpiarBloque MACRO destino, cantidad
    mov  edi, OFFSET destino
    mov  ecx, cantidad
    xor  eax, eax
    rep  stosb
ENDM

; --- CopiarRegistros ------------------------------------------------------
; Copia 'cuenta' registros de 'tam' bytes cada uno, de origen a destino
; (REP MOVSB; copiar DWORDs byte por byte da exactamente el mismo resultado).
; Parametros: origen, destino = etiquetas (si llevan "+desplazamiento" se
;             escriben entre < > para que MASM las tome como UN argumento) ;
;             cuenta = constante o registro ; tam = bytes por registro
; Requiere  : DF = 0 (CLD hecho antes)
; Modifica  : ECX, ESI, EDI (EAX no se toca: puede ser la 'cuenta')
CopiarRegistros MACRO origen, destino, cuenta, tam
    mov  esi, OFFSET origen
    mov  edi, OFFSET destino
    mov  ecx, cuenta
    imul ecx, tam                ; bytes totales = cuenta * tam
    rep  movsb
ENDM


.data
; ---------------------------- CONSTANTES ----------------------------------
MAX_PRODS     = 10          ; maximo de productos
LONG_COD      = 8           ; 7 caracteres (ABC-123) + 00h
LONG_NOM      = 26          ; 25 caracteres + 00h
TAM_DWORD     = 4           ; bytes de un DWORD (precios y stock)
MAX_STOCK     = 100         ; existencia maxima por producto
MAX_CENT      = 999999      ; $9999.99 expresado en centavos
DESC_MIN_CANT = 10          ; regla de negocio: desde 10 unidades hay descuento
DESC_DIVISOR  = 10          ; descuento = importe / 10  (equivale al 10%)
FIRMA         = 31564E49h   ; "INV1" en little-endian (49h 4Eh 56h 31h)

; Posiciones dentro del archivo / buffer de archivo
POS_CUENTA    = 4
POS_CODIGOS   = 8
POS_NOMBRES   = POS_CODIGOS + MAX_PRODS * LONG_COD
POS_PRECIOS   = POS_NOMBRES + MAX_PRODS * LONG_NOM
POS_STOCK     = POS_PRECIOS + MAX_PRODS * 4
TAM_ARCHIVO   = POS_STOCK + MAX_PRODS * 4          ; 428 bytes

; ------------------------ ARREGLOS PARALELOS ------------------------------
; Empiezan vacios: los datos reales vienen de inventario.dat (o de las altas).
codigos     BYTE (MAX_PRODS * LONG_COD) DUP(0)
nombres     BYTE (MAX_PRODS * LONG_NOM) DUP(0)
precios     DWORD MAX_PRODS DUP(0)       ; centavos enteros
stock       DWORD MAX_PRODS DUP(0)       ; 0 a 100 unidades
total_prods DWORD 0                      ; productos activos

; --------------------- VARIABLES DE LA SESION -----------------------------
cambios_sin_guardar DWORD 0     ; 1 = hay cambios que no estan en el archivo
ingresos            DWORD 0     ; suma de importes finales de ventas aceptadas
unidades_vendidas   DWORD 0
ventas_ok           DWORD 0     ; ventas aceptadas
descuentos_total    DWORD 0     ; centavos descontados en la sesion
valor_inv           DWORD 0     ; acumulador del resumen

; Variables de trabajo (se guardan en memoria para no depender de registros)
idx_sel      DWORD 0
cant_sel     DWORD 0
base_sel     DWORD 0
dcto_sel     DWORD 0
final_sel    DWORD 0
nuevo_precio DWORD 0
nuevo_stock  DWORD 0
nuevo_len    DWORD 0
handle_arch  DWORD 0
bytes_io     DWORD 0
cuenta_tmp   DWORD 0

; ----------------------------- ARCHIVO ------------------------------------
nombreArchivo BYTE "inventario.dat", 0
; Capacidad = TAM_ARCHIVO + 2: 1 byte extra para detectar archivos demasiado
; grandes y 1 byte para el terminador 00h que se agrega tras los bytes leidos.
bufArchivo    BYTE (TAM_ARCHIVO + 2) DUP(0)

; ------------------------ BUFFERS DE CAPTURA ------------------------------
; Cada buffer es mas grande que lo que se lee: ReadString escribe el 00h
; DESPUES de los ECX caracteres, por eso se lee SIZEOF - 1.
opcion_str  BYTE 8  DUP(0)
codigo_str  BYTE 16 DUP(0)
nombre_str  BYTE 40 DUP(0)
precio_str  BYTE 16 DUP(0)
stock_str   BYTE 8  DUP(0)
cant_str    BYTE 8  DUP(0)

; --------------------------- MENSAJES -------------------------------------
msgMenu    BYTE "=== SISTEMA DE INVENTARIO: COMPONENTES PC ===", 13, 10
           BYTE "1. Registrar y consultar inventario", 13, 10
           BYTE "2. Recibir mercancia", 13, 10
           BYTE "3. Vender producto", 13, 10
           BYTE "4. Mostrar resumen de sesion", 13, 10
           BYTE "5. Guardar y salir", 13, 10
           BYTE "6. Salir sin guardar", 13, 10
           BYTE "Elige una opcion (1-6): ", 0

msgSubmenu BYTE "=== REGISTRAR Y CONSULTAR ===", 13, 10
           BYTE "1. Dar de alta un producto", 13, 10
           BYTE "2. Mostrar inventario", 13, 10
           BYTE "3. Buscar producto por codigo", 13, 10
           BYTE "4. Volver al menu principal", 13, 10
           BYTE "Elige una opcion (1-4): ", 0

msgError    BYTE "Opcion no valida.", 13, 10, 0
msgPausa    BYTE 13, 10, "Presiona una tecla para continuar...", 0
lblMXN      BYTE " MXN", 13, 10, 0

; Altas y busqueda
msgLleno       BYTE "Error: El inventario esta lleno (Maximo 10 productos).", 13, 10, 0
msgPideCodigo  BYTE "Ingresa el codigo del producto (Ej. GPU-123): ", 0
msgErrCodigo   BYTE "Error: Formato invalido. Deben ser 3 letras mayusculas, un guion y 3 digitos.", 13, 10, 0
msgErrDuplicado BYTE "Error: El codigo ya esta registrado en el sistema.", 13, 10, 0
msgNoExiste    BYTE "Error: No existe un producto con ese codigo.", 13, 10, 0
msgPideNombre  BYTE "Ingresa el nombre del producto (1 a 25 caracteres): ", 0
msgErrNombre   BYTE "Error: El nombre debe tener entre 1 y 25 caracteres.", 13, 10, 0
msgPidePrecio  BYTE "Ingresa el precio en MXN (Ej. 185.50): ", 0
msgErrPrecio   BYTE "Error: Precio invalido. Solo digitos y un punto, maximo 2 decimales, de 0.01 a 9999.99.", 13, 10, 0
msgPideStock   BYTE "Ingresa la existencia inicial (0 a 100): ", 0
msgErrStock    BYTE "Error: Cantidad invalida o fuera de limite (0 a 100, solo digitos).", 13, 10, 0
msgAltaExito   BYTE "Producto registrado con exito en el sistema!", 13, 10, 0
msgVacio       BYTE "No hay productos registrados.", 13, 10, 0

; Mostrar productos
msgTituloInv   BYTE "=== INVENTARIO ===", 13, 10, 0
lblCodigo      BYTE "Codigo     : ", 0
lblNombre      BYTE "Nombre     : ", 0
lblPrecio      BYTE "Precio     : ", 0
lblExist       BYTE "Existencia : ", 0
sepNum         BYTE ") ", 0
sepGuion       BYTE " - ", 0
lblExistLinea  BYTE "    Existencia: ", 0
lblPrecioLinea BYTE "    Precio: ", 0

; Recibir y vender
msgPideCantR   BYTE "Unidades recibidas (1-100): ", 0
msgPideCantV   BYTE "Unidades a vender (1-100): ", 0
msgErrCant     BYTE "Error: Cantidad invalida. Solo digitos enteros mayores que cero (maximo 100).", 13, 10, 0
msgExcede      BYTE "Error: La existencia no puede exceder 100 unidades. No se hizo ningun cambio.", 13, 10, 0
msgRecibido    BYTE "Mercancia recibida. Nueva existencia: ", 0
msgSinExist    BYTE "Error: Existencias insuficientes. Venta rechazada, no se modifico nada.", 13, 10, 0
msgDesborda    BYTE "Error: El acumulado de ingresos desbordaria el limite del sistema. Venta rechazada.", 13, 10, 0
msgReglaVenta  BYTE "Regla del negocio: 10% de descuento al comprar 10 o mas unidades.", 13, 10, 0
msgVentaOk     BYTE 13, 10, "=== VENTA ACEPTADA ===", 13, 10, 0
lblBase        BYTE "Importe base                : ", 0
lblDcto        BYTE "Descuento por cantidad (10%): ", 0
lblFinal       BYTE "IMPORTE FINAL               : ", 0
msgSinDcto     BYTE "Sin descuento (se aplica desde 10 unidades).", 13, 10, 0

; Resumen
msgTituloRes   BYTE "=== RESUMEN DE LA SESION ===", 13, 10, 0
lblResProd     BYTE "Productos registrados : ", 0
lblResUnid     BYTE "Unidades disponibles  : ", 0
lblResValor    BYTE "Valor del inventario  : ", 0
lblResVentas   BYTE "Ventas aceptadas      : ", 0
lblResVendidas BYTE "Unidades vendidas     : ", 0
lblResDcto     BYTE "Descuentos otorgados  : ", 0
lblResIngresos BYTE "INGRESOS DE LA SESION : ", 0
lblResCambios  BYTE "Cambios sin guardar   : ", 0
txtSi          BYTE "SI", 13, 10, 0
txtNo          BYTE "NO", 13, 10, 0

; Archivos y salida
msgAusente     BYTE "No se encontro inventario.dat. Se inicia con un catalogo vacio.", 13, 10, 0
msgInvalido    BYTE "ATENCION: inventario.dat esta danado o no tiene el formato esperado.", 13, 10
               BYTE "No se cargo; el catalogo en memoria no se modifico.", 13, 10, 0
msgCargado     BYTE "Inventario cargado desde inventario.dat. Productos: ", 0
msgGuardado    BYTE "Inventario guardado en inventario.dat correctamente.", 13, 10, 0
msgErrCrear    BYTE "Error: no se pudo crear inventario.dat.", 13, 10, 0
msgErrEscribir BYTE "Error: no se escribieron todos los bytes solicitados al archivo.", 13, 10, 0
msgNoSalio     BYTE "No se salio del programa porque el guardado fallo.", 13, 10, 0
msgAvisoCamb   BYTE "ATENCION: hay cambios sin guardar. Salir de todos modos? (S/N): ", 0
msgAdios       BYTE "Hasta luego.", 13, 10, 0

.code
; ==========================================================================
; main: carga el archivo y repite el menu hasta que el usuario sale.
; ==========================================================================
main PROC
    call CargarCatalogo       ; recupera inventario.dat (valida antes de reemplazar)
    call Pausa

MenuLoop:
    call Clrscr
    MostrarMsg msgMenu
    LeerOpcion MenuInvalido   ; AL = opcion (exactamente 1 caracter)

    cmp  al, '1'
    je   OpcionAlta
    cmp  al, '2'
    je   OpcionRecibir
    cmp  al, '3'
    je   OpcionVender
    cmp  al, '4'
    je   OpcionResumen
    cmp  al, '5'
    je   OpcionSalir
    cmp  al, '6'
    je   OpcionSalirSin

MenuInvalido:
    MostrarYPausa msgError
    jmp  MenuLoop

; ==========================================================================
; OPCION 1: REGISTRAR Y CONSULTAR (submenu: alta / mostrar / buscar)
; ==========================================================================
OpcionAlta:
SubMenuLoop:
    call Clrscr
    MostrarMsg msgSubmenu
    LeerOpcion SubInvalida
    cmp  al, '1'
    je   AltaProducto
    cmp  al, '2'
    je   MostrarLista
    cmp  al, '3'
    je   BuscarProducto
    cmp  al, '4'
    je   MenuLoop
SubInvalida:
    MostrarYPausa msgError
    jmp  SubMenuLoop

MostrarLista:
    call Clrscr
    call MostrarInventario
    call Pausa
    jmp  SubMenuLoop

BuscarProducto:
    call Clrscr
    call PedirProducto        ; CF=0 -> EAX = indice ; CF=1 -> error ya mostrado
    jc   BP_Fin
    mov  esi, eax             ; ESI = indice del producto encontrado
    MostrarMsg msgTituloInv
    call MostrarProducto
BP_Fin:
    call Pausa
    jmp  SubMenuLoop

; --------------------------------------------------------------------------
; ALTA DE PRODUCTO: cada procedimiento Pedir... captura y
; valida UN dato y avisa el error por CF. Solo si los cuatro datos son
; correctos, RegistrarProducto escribe en los arreglos.
; --------------------------------------------------------------------------
AltaProducto:
    call Clrscr
    cmp  total_prods, MAX_PRODS
    jae  AP_Lleno             ; total_prods >= 10 -> sin capacidad

    call PedirCodigoNuevo     ; formato ABC-123 y no repetido
    jc   AP_Fin
    call PedirNombre          ; EAX = longitud (1..25)
    jc   AP_Fin
    mov  nuevo_len, eax
    call PedirPrecio          ; EAX = centavos
    jc   AP_Fin
    mov  nuevo_precio, eax
    call PedirStock           ; EAX = 0..100
    jc   AP_Fin
    mov  nuevo_stock, eax

    call RegistrarProducto    ; unico punto donde se escribe en los arreglos
    jc   AP_Lleno
    MostrarMsg msgAltaExito
    jmp  AP_Fin
AP_Lleno:
    MostrarMsg msgLleno
AP_Fin:
    call Pausa
    jmp  SubMenuLoop

; ==========================================================================
; OPCION 2: RECIBIR MERCANCIA (suma unidades sin pasar de 100)
; Usa: ExigirProductos (macro), PedirProducto y PedirCantidad (procedimientos
; que ya muestran su propio error y avisan por CF), MostrarMsg.
; ==========================================================================
OpcionRecibir:
    call Clrscr
    ExigirProductos RC_Vacio  ; sin productos -> aviso
    call PedirProducto        ; CF=0 -> EAX = indice
    jc   RC_Fin               ; (el error ya se mostro)
    mov  idx_sel, eax         ; guardamos el indice en memoria
    mov  esi, eax
    call MostrarProducto

    mov  edx, OFFSET msgPideCantR
    call PedirCantidad        ; CF=0 -> EAX = unidades (1..100)
    jc   RC_Fin               ; (el error ya se mostro)
    mov  ebx, eax             ; EBX = unidades recibidas

    mov  esi, idx_sel
    mov  eax, stock[esi*4]
    add  eax, ebx             ; EAX = nueva existencia (maximo 200: no desborda)
    cmp  eax, MAX_STOCK
    ja   RC_Excede            ; pasaria de 100 -> rechazar SIN modificar nada
    mov  stock[esi*4], eax    ; unico punto donde se escribe
    mov  cambios_sin_guardar, 1
    MostrarMsg msgRecibido    ; (WriteString conserva EAX)
    call PrintUInt            ; EAX = nueva existencia
    call Crlf
    jmp  RC_Fin

RC_Vacio:
    MostrarMsg msgVacio
    jmp  RC_Fin
RC_Excede:
    MostrarMsg msgExcede
RC_Fin:
    call Pausa
    jmp  MenuLoop

; ==========================================================================
; OPCION 3: VENDER (un solo producto por venta) + REGLA DE NEGOCIO
; Importe base = precio * cantidad. Si cantidad >= 10: descuento = base / 10
; (division entera: el residuo = fraccion de centavo se DESCARTA).
; Importe final = base - descuento.
; Solo despues de pasar TODAS las validaciones se modifican stock e ingresos.
; Los calculos viven en CalcularImporte y CalcularDescuento.
; ==========================================================================
OpcionVender:
    call Clrscr
    ExigirProductos VT_Vacio
    call PedirProducto
    jc   VT_Fin
    mov  idx_sel, eax
    mov  esi, eax
    call MostrarProducto
    cmp  stock[esi*4], 0
    je   VT_SinExist          ; no hay nada que vender

    MostrarMsg msgReglaVenta
    mov  edx, OFFSET msgPideCantV
    call PedirCantidad        ; CF=0 -> EAX = unidades (1..100)
    jc   VT_Fin               ; (el error ya se mostro)
    mov  cant_sel, eax

    mov  esi, idx_sel
    cmp  eax, stock[esi*4]
    ja   VT_SinExist          ; pide mas de lo que hay -> rechazar

    ; ---- calculos (todavia NO se modifica nada) ----
    call CalcularImporte      ; ESI = indice, EAX = cantidad -> EAX = importe base
    mov  base_sel, eax
    mov  ecx, cant_sel
    call CalcularDescuento    ; EAX = base, ECX = cantidad  -> EAX = descuento
    mov  dcto_sel, eax
    mov  eax, base_sel
    sub  eax, dcto_sel        ; importe final = base - descuento
    mov  final_sel, eax
    add  eax, ingresos        ; ingresos + importe final
    jc   VT_Desborda          ; CF=1 -> no cabe en 32 bits: rechazar

    ; ---- venta aceptada: ahora SI se actualizan los registros ----
    mov  ingresos, eax
    mov  eax, stock[esi*4]
    sub  eax, cant_sel
    mov  stock[esi*4], eax    ; nunca baja de 0 porque cant <= stock
    mov  eax, cant_sel
    add  unidades_vendidas, eax
    mov  eax, dcto_sel
    add  descuentos_total, eax
    inc  ventas_ok
    mov  cambios_sin_guardar, 1

    ; ---- recibo ----
    MostrarMsg msgVentaOk
    MostrarCampoMXN lblBase, base_sel
    cmp  dcto_sel, 0
    je   VT_NoDcto
    MostrarCampoMXN lblDcto, dcto_sel
    jmp  VT_Final
VT_NoDcto:
    MostrarMsg msgSinDcto
VT_Final:
    MostrarCampoMXN lblFinal, final_sel
    jmp  VT_Fin

VT_Vacio:
    MostrarMsg msgVacio
    jmp  VT_Fin
VT_SinExist:
    MostrarMsg msgSinExist
    jmp  VT_Fin
VT_Desborda:
    MostrarMsg msgDesborda
VT_Fin:
    call Pausa
    jmp  MenuLoop

; ==========================================================================
; OPCION 4: RESUMEN (unidades, valor del inventario, ingresos de la sesion)
; ==========================================================================
OpcionResumen:
    call Clrscr
    MostrarMsg msgTituloRes
    call CalcularTotales      ; EAX = unidades, EDX = valor del inventario
    mov  ebx, eax             ; EBX = unidades (WriteString/PrintUInt conservan EBX)
    mov  valor_inv, edx

    MostrarCampoUInt lblResProd, total_prods
    MostrarCampoUInt lblResUnid, ebx
    MostrarCampoMXN  lblResValor, valor_inv
    MostrarCampoUInt lblResVentas, ventas_ok
    MostrarCampoUInt lblResVendidas, unidades_vendidas
    MostrarCampoMXN  lblResDcto, descuentos_total
    MostrarCampoMXN  lblResIngresos, ingresos
    MostrarMsg lblResCambios
    MostrarSiNo cambios_sin_guardar     ; macro con LOCAL
    call Pausa
    jmp  MenuLoop

; ==========================================================================
; OPCION 5: GUARDAR Y SALIR (si el guardado falla, NO se sale)
; ==========================================================================
OpcionSalir:
    call Clrscr
    call GuardarCatalogo      ; CF=1 si hubo error (el mensaje ya se mostro)
    jc   OS_Fallo
    MostrarMsg msgAdios
    exit
OS_Fallo:
    MostrarYPausa msgNoSalio
    jmp  MenuLoop

; ==========================================================================
; OPCION 6: SALIR SIN GUARDAR (avisa si hay cambios pendientes)
; ==========================================================================
OpcionSalirSin:
    cmp  cambios_sin_guardar, 0
    je   OSS_Salir            ; sin cambios -> salir directo
    MostrarMsg msgAvisoCamb
    PedirCadena opcion_str    ; macro: ReadString con SIZEOF - 1
    mov  al, opcion_str[0]
    cmp  al, 'S'
    je   OSS_Salir
    cmp  al, 's'
    je   OSS_Salir
    jmp  MenuLoop             ; cualquier otra respuesta = cancelar
OSS_Salir:
    exit
main ENDP

; ==========================================================================
; ParseMXN
; Convierte una cadena como "185.50", "12.5" o "300" a centavos.
; ENTRADA : EDX = OFFSET de la cadena terminada en 0
; SALIDA  : EAX = valor en centavos (ej. 18550)
;           CF = 0 -> conversion correcta ; CF = 1 -> cadena invalida (EAX = 0)
; REGISTROS: USES conserva EBX ECX EDX ESI EDI. EAX queda FUERA de USES
;            porque es el resultado.
; IDEA: acumulador = acumulador*10 + digito, ignorando el punto y contando los
; decimales; al final se completa con ceros hasta tener siempre 2 decimales.
; ==========================================================================
ParseMXN PROC USES ebx ecx edx esi edi
    mov  esi, edx        ; ESI = puntero que recorre la cadena
    xor  eax, eax        ; EAX = acumulador en centavos = 0
    xor  ebx, ebx        ; BL  = bandera "ya vi el punto" (0 = no)
    xor  ecx, ecx        ; ECX = cantidad de decimales leidos
    xor  edi, edi        ; EDI = cantidad total de digitos leidos

PM_Leer:
    movzx edx, BYTE PTR [esi] ; EDX = caracter actual (limpia bits altos)
    cmp  dl, 0                ; 0 = fin de la cadena
    je   PM_Fin
    cmp  dl, '.'
    je   PM_Punto

    EnRango dl, '0', '9', PM_Invalido   ; solo digitos

    sub  dl, '0'              ; ASCII -> valor numerico
    imul eax, 10              ; IMUL de 2 operandos NO usa EDX
    add  eax, edx
    cmp  eax, MAX_CENT        ; maximo permitido $9999.99 = 999999 centavos
    ja   PM_Invalido          ; asi evitamos desbordamientos
    inc  edi                  ; un digito mas

    cmp  bl, 1                ; ya paso el punto?
    jne  PM_Siguiente         ; no: era parte entera
    inc  ecx                  ; si: es un decimal mas
    cmp  ecx, 2
    ja   PM_Invalido          ; mas de 2 decimales -> rechazar
    jmp  PM_Siguiente

PM_Punto:
    cmp  bl, 1
    je   PM_Invalido          ; segundo punto -> rechazar
    cmp  edi, 0
    je   PM_Invalido          ; punto sin digitos antes (".50") -> rechazar
    mov  bl, 1                ; marcamos que ya vimos el punto

PM_Siguiente:
    inc  esi
    jmp  PM_Leer

PM_Fin:
    cmp  edi, 0
    je   PM_Invalido          ; cadena vacia -> rechazar
    cmp  bl, 1
    jne  PM_Escalar           ; sin punto: pasar a escalar
    cmp  ecx, 0
    je   PM_Invalido          ; "185." (punto sin decimales) -> rechazar

PM_Escalar:
    neg  ecx
    add  ecx, 2               ; ECX = 2 - decimales (veces que se multiplica x10)
    jz   PM_Rango
PM_Bucle:
    imul eax, 10
    loop PM_Bucle

PM_Rango:
    EnRango eax, 1, MAX_CENT, PM_Invalido   ; de $0.01 a $9999.99
    clc                       ; CF = 0 -> exito
    ret                       ; (USES agrega aqui los POP en orden inverso)

PM_Invalido:
    xor  eax, eax
    stc                       ; CF = 1 -> error
    ret
ParseMXN ENDP

; ==========================================================================
; PrintMXN
; Muestra centavos como pesos con 2 decimales, " MXN" y salto de linea.
; ENTRADA : EAX = valor en centavos
; SALIDA  : ninguna (imprime en consola)
; REGISTROS: USES conserva EAX EBX ECX EDX (aqui EAX es entrada, no resultado).
; NOTA    : el PUSH EDX del medio guarda un DATO (los centavos); no es un
;           respaldo de registro y por eso se queda escrito a mano.
; ==========================================================================
PrintMXN PROC USES eax ebx ecx edx
    ; 1. Separar pesos y centavos dividiendo entre 100
    xor  edx, edx      ; DIV usa EDX:EAX como dividendo
    mov  ebx, 100
    div  ebx           ; EAX = pesos, EDX = centavos (residuo)
    push edx           ; guardar centavos (dato) para despues

    ; 2. Convertir los pesos: dividir entre 10 y apilar cada digito
    mov  ecx, 0        ; contador de digitos
    mov  ebx, 10
PMXN_DivPesos:
    xor  edx, edx
    div  ebx           ; EAX = cociente, EDX = digito (0-9)
    push edx           ; LIFO: el ultimo digito sale primero
    inc  ecx
    cmp  eax, 0
    jne  PMXN_DivPesos
PMXN_ImprimePesos:
    pop  eax
    add  al, 30h       ; digito -> ASCII
    call WriteChar
    loop PMXN_ImprimePesos

    ; 3. Punto decimal
    mov  al, '.'
    call WriteChar

    ; 4. Centavos: SIEMPRE 2 digitos (05 y no 5)
    pop  eax           ; centavos 0..99
    xor  edx, edx
    mov  ebx, 10
    div  ebx           ; EAX = decenas, EDX = unidades
    add  al, 30h
    call WriteChar
    mov  al, dl
    add  al, 30h
    call WriteChar

    ; 5. Etiqueta
    MostrarMsg lblMXN
    ret
PrintMXN ENDP

; ==========================================================================
; PrintUInt
; Muestra un entero sin signo en decimal (sin salto de linea), con DIV entre 10.
; ENTRADA : EAX = numero
; SALIDA  : ninguna (imprime en consola)
; REGISTROS: USES conserva EAX EBX ECX EDX.
; ==========================================================================
PrintUInt PROC USES eax ebx ecx edx
    mov  ebx, 10
    xor  ecx, ecx      ; ECX = cantidad de digitos
PU_Div:
    xor  edx, edx
    div  ebx           ; EDX = ultimo digito
    push edx
    inc  ecx
    cmp  eax, 0
    jne  PU_Div
PU_Print:
    pop  eax           ; sale primero el digito mas significativo
    add  al, 30h
    call WriteChar
    loop PU_Print
    ret
PrintUInt ENDP

; ==========================================================================
; ParseStock
; Convierte una cadena de solo digitos a entero y valida el rango 0..100.
; ENTRADA : EDX = puntero a la cadena
; SALIDA  : EAX = entero, CF = 0 exito ; CF = 1 error (EAX = 0)
; REGISTROS: USES conserva ESI EBX ECX. EAX queda FUERA (es el resultado).
; Rechaza: cadena vacia, caracteres que no sean digitos y valores > 100
; (el rango se revisa en CADA digito para que nunca haya desbordamiento).
; ==========================================================================
ParseStock PROC USES esi ebx ecx
    mov  esi, edx
    xor  eax, eax        ; acumulador
    xor  ecx, ecx        ; ECX = cantidad de digitos leidos
PS_Loop:
    movzx ebx, BYTE PTR [esi]
    cmp  bl, 0           ; fin de cadena
    je   PS_Fin
    EnRango bl, '0', '9', PS_Error      ; solo digitos

    sub  bl, '0'         ; ASCII -> valor
    imul eax, 10
    add  eax, ebx
    cmp  eax, MAX_STOCK
    ja   PS_Error        ; ya paso de 100 -> no seguir acumulando
    inc  ecx
    inc  esi
    jmp  PS_Loop

PS_Fin:
    cmp  ecx, 0
    je   PS_Error        ; cadena vacia -> rechazar
    clc
    ret

PS_Error:
    xor  eax, eax
    stc
    ret
ParseStock ENDP

; ==========================================================================
; ValidarFormatoCodigo
; Valida que el codigo tenga el formato "ABC-123".
; ENTRADA : EDX = puntero a la cadena
; SALIDA  : CF = 0 valido, CF = 1 invalido
; REGISTROS: USES conserva EAX ECX ESI (aqui EAX es de trabajo; el resultado
;            va en CF, no en EAX).
; ==========================================================================
ValidarFormatoCodigo PROC USES eax ecx esi
    mov  esi, edx

    ; Longitud exacta de 7: el caracter 8 debe ser el terminador 00h
    cmp  BYTE PTR [esi+7], 0
    jne  VFC_Error

    ; Posiciones 0, 1 y 2: letras mayusculas
    mov  ecx, 3
VFC_Letras:
    mov  al, [esi]
    EnRango al, 'A', 'Z', VFC_Error
    inc  esi
    loop VFC_Letras

    ; Posicion 3: guion
    mov  al, [esi]
    cmp  al, '-'
    jne  VFC_Error
    inc  esi

    ; Posiciones 4, 5 y 6: digitos
    mov  ecx, 3
VFC_Digitos:
    mov  al, [esi]
    EnRango al, '0', '9', VFC_Error
    inc  esi
    loop VFC_Digitos

    clc
    ret
VFC_Error:
    stc
    ret
ValidarFormatoCodigo ENDP

; ==========================================================================
; BuscarCodigo
; Busca un codigo en el arreglo 'codigos' (solo los productos activos).
; ENTRADA : EDX = puntero al codigo a buscar
; SALIDA  : CF = 1 si lo encuentra (EAX = indice) ; CF = 0 si no existe
; REGISTROS: USES conserva EBX ECX ESI EDI. EAX queda FUERA (es el indice).
; NOTA    : los PUSH/POP dentro del ciclo guardan el ESTADO de la busqueda
;           (contador y punteros) mientras se compara un codigo; no son
;           respaldo de registros del llamador.
; ==========================================================================
BuscarCodigo PROC USES ebx ecx esi edi
    mov  edi, edx            ; EDI = codigo buscado
    mov  esi, OFFSET codigos ; ESI = inicio del arreglo
    mov  ecx, total_prods
    cmp  ecx, 0
    je   BC_NoEncontrado

    mov  eax, 0              ; EAX = indice actual

BC_CicloProductos:
    push ecx
    push esi
    push edi

    mov  ecx, LONG_COD
BC_ComparaChars:
    mov  bl, [esi]
    mov  bh, [edi]
    cmp  bl, bh
    jne  BC_SiguienteProd    ; un caracter distinto -> siguiente producto
    cmp  bl, 0               ; ambos llegaron a 00h y eran iguales
    je   BC_EncontradoPop
    inc  esi
    inc  edi
    loop BC_ComparaChars

BC_EncontradoPop:
    pop  edi
    pop  esi
    pop  ecx
    stc                      ; CF = 1: encontrado
    ret

BC_SiguienteProd:
    pop  edi
    pop  esi
    pop  ecx
    add  esi, LONG_COD       ; siguiente codigo (8 bytes mas adelante)
    inc  eax
    loop BC_CicloProductos

BC_NoEncontrado:
    clc                      ; CF = 0: no existe
    ret
BuscarCodigo ENDP

; ==========================================================================
; Pausa
; Muestra un mensaje y espera una tecla.
; ENTRADA/SALIDA: ninguna. REGISTROS: USES conserva EAX EDX.
; ==========================================================================
Pausa PROC USES eax edx
    MostrarMsg msgPausa
    call ReadChar
    ret
Pausa ENDP

; ==========================================================================
; PROCEDIMIENTOS DE CAPTURA (NUEVOS EN LA UNIDAD 3)
; Antes, cada Pedir... era un bloque de 6 a 10 lineas copiado dentro de
; AltaProducto, PedirProducto, Recibir y Vender. Ahora cada tarea se escribe
; UNA vez; quien la llama solo revisa CF.
; ==========================================================================

; --- PedirCodigo ----------------------------------------------------------
; Pide un codigo y valida su formato ABC-123. El texto queda en codigo_str.
; ENTRADA : ninguna
; SALIDA  : CF = 0 formato correcto ; CF = 1 incorrecto (mensaje ya mostrado)
; REGISTROS: USES conserva ECX EDX. EAX queda modificado por ReadString.
PedirCodigo PROC USES ecx edx
    MostrarMsg msgPideCodigo
    PedirCadena codigo_str
    mov  edx, OFFSET codigo_str
    call ValidarFormatoCodigo        ; CF=1 si no cumple
    jnc  PCo_Fin
    MostrarMsg msgErrCodigo
    stc                              ; CF=1 despues del mensaje (los CALL cambian banderas)
PCo_Fin:
    ret
PedirCodigo ENDP

; --- PedirCodigoNuevo -----------------------------------------------------
; Igual que PedirCodigo, pero ademas exige que el codigo NO exista todavia.
; ENTRADA : ninguna
; SALIDA  : CF = 0 codigo valido y libre ; CF = 1 error (mensaje ya mostrado)
; REGISTROS: USES conserva EAX EDX (BuscarCodigo modifica EAX; aqui se respalda).
PedirCodigoNuevo PROC USES eax edx
    call PedirCodigo
    jc   PCN_Fin                     ; formato invalido: CF=1 sigue activo
    mov  edx, OFFSET codigo_str
    call BuscarCodigo                ; CF=1 si ya existe
    jnc  PCN_Libre
    MostrarMsg msgErrDuplicado
    stc
    jmp  PCN_Fin
PCN_Libre:
    clc
PCN_Fin:
    ret
PedirCodigoNuevo ENDP

; --- PedirProducto --------------------------------------------------------
; Pide un codigo y lo busca en el catalogo (para ventas, entradas y consultas).
; ENTRADA : ninguna
; SALIDA  : CF = 0 -> EAX = indice del producto ; CF = 1 -> error mostrado
; REGISTROS: USES conserva EDX. EAX queda FUERA (es el indice).
PedirProducto PROC USES edx
    call PedirCodigo
    jc   PP_Fin                      ; formato invalido (mensaje ya mostrado)
    mov  edx, OFFSET codigo_str
    call BuscarCodigo                ; CF=1 si existe (EAX = indice)
    jnc  PP_NoExiste
    clc                              ; encontrado: CF=0 y EAX conserva el indice
    ret
PP_NoExiste:
    MostrarMsg msgNoExiste
    stc
PP_Fin:
    ret
PedirProducto ENDP

; --- PedirNombre ----------------------------------------------------------
; Pide el nombre (1 a 25 caracteres). El texto queda en nombre_str.
; ENTRADA : ninguna
; SALIDA  : CF = 0 -> EAX = longitud ; CF = 1 -> error mostrado
; REGISTROS: USES conserva ECX EDX. EAX queda FUERA (es la longitud).
PedirNombre PROC USES ecx edx
    MostrarMsg msgPideNombre
    PedirCadena nombre_str           ; EAX = longitud
    EnRango eax, 1, LONG_NOM-1, PN_Mala
    clc
    ret
PN_Mala:
    MostrarMsg msgErrNombre
    stc
    ret
PedirNombre ENDP

; --- PedirPrecio ----------------------------------------------------------
; Pide un precio en MXN (ej. 185.50) y lo convierte a centavos.
; ENTRADA : ninguna
; SALIDA  : CF = 0 -> EAX = centavos ; CF = 1 -> error mostrado (EAX = 0)
; REGISTROS: USES conserva ECX EDX. EAX queda FUERA (es el resultado).
PedirPrecio PROC USES ecx edx
    MostrarMsg msgPidePrecio
    PedirCadena precio_str
    mov  edx, OFFSET precio_str
    call ParseMXN                    ; EAX = centavos, CF=1 si es invalido
    jnc  PPr_Fin
    MostrarMsg msgErrPrecio          ; (EDX cambia, EAX sigue en 0)
    stc
PPr_Fin:
    ret
PedirPrecio ENDP

; --- PedirStock -----------------------------------------------------------
; Pide la existencia inicial (0 a 100).
; ENTRADA : ninguna
; SALIDA  : CF = 0 -> EAX = existencia ; CF = 1 -> error mostrado (EAX = 0)
; REGISTROS: USES conserva ECX EDX. EAX queda FUERA (es el resultado).
PedirStock PROC USES ecx edx
    MostrarMsg msgPideStock
    PedirCadena stock_str
    mov  edx, OFFSET stock_str
    call ParseStock
    jnc  PSt_Fin
    MostrarMsg msgErrStock
    stc
PSt_Fin:
    ret
PedirStock ENDP

; --- PedirCantidad --------------------------------------------------------
; Pide una cantidad ENTERA MAYOR QUE CERO (1 a 100). Sirve para Recibir y
; Vender: es el bloque que estaba repetido en las dos opciones.
; ENTRADA : EDX = OFFSET del mensaje que se muestra al usuario
; SALIDA  : CF = 0 -> EAX = cantidad (1..100) ; CF = 1 -> error mostrado, EAX = 0
; REGISTROS: USES conserva ECX EDX. EAX queda FUERA (es el resultado).
PedirCantidad PROC USES ecx edx
    call WriteString                 ; EDX ya trae el mensaje que paso quien llama
    PedirCadena cant_str
    mov  edx, OFFSET cant_str
    call ParseStock                  ; solo digitos, 0..100
    jc   PCa_Mala
    cmp  eax, 0
    je   PCa_Mala                    ; la cantidad debe ser mayor que cero
    clc
    ret
PCa_Mala:
    MostrarMsg msgErrCant
    xor  eax, eax
    stc
    ret
PedirCantidad ENDP

; --- RegistrarProducto ----------------------------------------------------
; Escribe un producto nuevo en el primer espacio libre de los arreglos, usando
; codigo_str, nombre_str, nuevo_len, nuevo_precio y nuevo_stock (ya validados).
; ENTRADA : las variables anteriores
; SALIDA  : CF = 0 registrado (total_prods + 1, cambios_sin_guardar = 1)
;           CF = 1 no hay espacio libre (no se escribe nada)
; REGISTROS: USES conserva EAX EBX ECX ESI EDI (aqui EAX es de trabajo).
RegistrarProducto PROC USES eax ebx ecx esi edi
    mov  esi, OFFSET codigos     ; ESI recorre 'codigos' de 8 en 8 bytes
    xor  ebx, ebx                ; EBX = indice del espacio actual
RP_Busca:
    cmp  BYTE PTR [esi], 0       ; primer byte 00h = espacio libre
    je   RP_Libre
    add  esi, LONG_COD
    inc  ebx
    cmp  ebx, MAX_PRODS
    jb   RP_Busca
    stc                          ; no hay espacio
    ret

RP_Libre:
    cld                          ; las cadenas se copian hacia adelante
    mov  edi, esi                ; destino = espacio libre en 'codigos'
    mov  esi, OFFSET codigo_str
    mov  ecx, LONG_COD
    rep  movsb                   ; copia el codigo (7 caracteres + 00h)

    imul edi, ebx, LONG_NOM      ; EDI = indice * 26
    add  edi, OFFSET nombres     ; EDI = direccion del nombre en el arreglo
    push edi                     ; (dato) STOSB mueve EDI; hay que recuperarlo
    xor  eax, eax
    mov  ecx, LONG_NOM
    rep  stosb                   ; limpia los 26 bytes con 00h
    pop  edi
    mov  esi, OFFSET nombre_str
    mov  ecx, nuevo_len          ; solo los caracteres; el 00h ya esta
    rep  movsb

    mov  eax, nuevo_precio
    mov  precios[ebx*4], eax
    mov  eax, nuevo_stock
    mov  stock[ebx*4], eax

    inc  total_prods
    mov  cambios_sin_guardar, 1
    clc
    ret
RegistrarProducto ENDP

; ==========================================================================
; CalcularImporte
; Importe base de una venta = precio del producto * cantidad.
; ENTRADA : ESI = indice del producto ; EAX = cantidad (1..100)
; SALIDA  : EAX = importe base en centavos
; REGISTROS: no modifica ningun otro registro, por eso no lleva USES.
; NOTA    : maximo 999999 * 100 = 99,999,900: cabe en 32 bits.
; ==========================================================================
CalcularImporte PROC
    imul eax, precios[esi*4]
    ret
CalcularImporte ENDP

; ==========================================================================
; CalcularDescuento
; Regla de negocio: desde DESC_MIN_CANT unidades el descuento es el 10% del
; importe base (division entera entre DESC_DIVISOR; el residuo, que es una
; fraccion de centavo, se DESCARTA). Con menos unidades el descuento es 0.
; ENTRADA : EAX = importe base (centavos) ; ECX = cantidad
; SALIDA  : EAX = descuento en centavos
; REGISTROS: USES conserva EBX EDX (DIV los usa). EAX queda FUERA (resultado).
; ==========================================================================
CalcularDescuento PROC USES ebx edx
    cmp  ecx, DESC_MIN_CANT
    jb   CD_Sin                      ; menos de 10 unidades -> sin descuento
    xor  edx, edx                    ; DIV usa EDX:EAX como dividendo
    mov  ebx, DESC_DIVISOR
    div  ebx                         ; EAX = base / 10
    ret
CD_Sin:
    xor  eax, eax                    ; descuento = 0
    ret
CalcularDescuento ENDP

; ==========================================================================
; CalcularTotales
; Recorre con ESI los productos activos y acumula unidades y valor.
; ENTRADA : ninguna (usa total_prods, stock y precios)
; SALIDA  : EAX = unidades disponibles ; EDX = valor del inventario (centavos)
; REGISTROS: USES conserva EBX ESI. EAX y EDX quedan FUERA (son resultados).
; ==========================================================================
CalcularTotales PROC USES ebx esi
    xor  eax, eax                ; unidades
    xor  edx, edx                ; valor
    xor  esi, esi                ; ESI = indice
    cmp  total_prods, 0
    je   CT_Fin
CT_Ciclo:
    mov  ebx, stock[esi*4]
    add  eax, ebx                ; unidades += existencia[i]
    imul ebx, precios[esi*4]     ; EBX = precio[i] * existencia[i]
    add  edx, ebx                ; (maximo 10 * 99,999,900: cabe en 32 bits)
    inc  esi
    cmp  esi, total_prods
    jb   CT_Ciclo
CT_Fin:
    ret
CalcularTotales ENDP

; ==========================================================================
; MostrarProducto
; Muestra codigo, nombre, precio y existencia de un producto.
; ENTRADA : ESI = indice del producto
; SALIDA  : ninguna. REGISTROS: USES conserva EAX EDX.
; ==========================================================================
MostrarProducto PROC USES eax edx
    MostrarMsg lblCodigo
    MostrarElemento codigos, LONG_COD
    call Crlf
    MostrarMsg lblNombre
    MostrarElemento nombres, LONG_NOM
    call Crlf
    MostrarCampoMXN  lblPrecio, precios[esi*4]
    MostrarCampoUInt lblExist, stock[esi*4]
    ret
MostrarProducto ENDP

; ==========================================================================
; MostrarInventario
; Recorre con ESI todos los productos activos y los lista.
; ENTRADA/SALIDA: ninguna. REGISTROS: USES conserva EAX EDX ESI.
; ==========================================================================
MostrarInventario PROC USES eax edx esi
    MostrarMsg msgTituloInv
    cmp  total_prods, 0
    jne  MI_Hay
    MostrarMsg msgVacio
    ret

MI_Hay:
    xor  esi, esi                ; ESI = indice del producto (0..total-1)
MI_Ciclo:
    mov  eax, esi
    inc  eax                     ; numero de lista = indice + 1
    call PrintUInt
    MostrarMsg sepNum
    MostrarElemento codigos, LONG_COD
    MostrarMsg sepGuion
    MostrarElemento nombres, LONG_NOM
    call Crlf

    MostrarMsg lblExistLinea
    mov  eax, stock[esi*4]
    call PrintUInt               ; existencia (sin salto: el precio va en la misma linea)
    MostrarCampoMXN lblPrecioLinea, precios[esi*4]

    inc  esi
    cmp  esi, total_prods
    jb   MI_Ciclo
    ret
MostrarInventario ENDP

; ==========================================================================
; GuardarCatalogo
; Arma una imagen de 428 bytes en bufArchivo y la escribe en inventario.dat.
; ENTRADA : ninguna
; SALIDA  : CF = 0 guardado correcto ; CF = 1 error (mensaje ya mostrado)
; REGISTROS: USES conserva EAX ECX EDX ESI EDI. La salida va solo en CF, y
;            los POP del epilogo de USES no cambian las banderas.
; ==========================================================================
GuardarCatalogo PROC USES eax ecx edx esi edi
    cld                              ; copiar hacia adelante

    ; --- 1. limpiar el buffer completo ---
    LimpiarBloque bufArchivo, TAM_ARCHIVO+2

    ; --- 2. encabezado: firma + numero de productos ---
    mov  DWORD PTR bufArchivo, FIRMA
    mov  eax, total_prods
    mov  DWORD PTR bufArchivo[POS_CUENTA], eax

    ; --- 3. copiar los 4 arreglos completos (10 registros cada uno) ---
    CopiarRegistros codigos, <bufArchivo+POS_CODIGOS>, MAX_PRODS, LONG_COD
    CopiarRegistros nombres, <bufArchivo+POS_NOMBRES>, MAX_PRODS, LONG_NOM
    CopiarRegistros precios, <bufArchivo+POS_PRECIOS>, MAX_PRODS, TAM_DWORD
    CopiarRegistros stock,   <bufArchivo+POS_STOCK>,   MAX_PRODS, TAM_DWORD

    ; --- 4. crear el archivo (EAX = handle o INVALID_HANDLE_VALUE) ---
    mov  edx, OFFSET nombreArchivo
    call CreateOutputFile
    cmp  eax, INVALID_HANDLE_VALUE
    je   GC_ErrCrear
    mov  handle_arch, eax            ; guardar el handle en memoria

    ; --- 5. escribir: EAX = handle, EDX = buffer, ECX = bytes a escribir ---
    mov  edx, OFFSET bufArchivo
    mov  ecx, TAM_ARCHIVO
    call WriteToFile                 ; al regresar EAX = bytes REALMENTE escritos
    mov  bytes_io, eax

    mov  eax, handle_arch
    call CloseFile                   ; siempre cerrar el archivo

    cmp  bytes_io, TAM_ARCHIVO       ; escribio todo lo solicitado?
    jne  GC_ErrEscribir

    mov  cambios_sin_guardar, 0
    MostrarMsg msgGuardado
    clc                              ; CF=0 despues de los CALL: asi sale limpio
    ret

GC_ErrCrear:
    MostrarMsg msgErrCrear
    stc
    ret

GC_ErrEscribir:
    MostrarMsg msgErrEscribir
    stc
    ret
GuardarCatalogo ENDP

; ==========================================================================
; CargarCatalogo
; Lee inventario.dat a un buffer temporal, lo VALIDA y solo si es correcto
; reemplaza el catalogo en memoria.
; ENTRADA : ninguna
; SALIDA  : CF = 0 catalogo cargado ; CF = 1 no se cargo (archivo ausente o
;           invalido). En ese caso el catalogo en memoria NO se modifica.
; REGISTROS: USES conserva EAX ECX EDX ESI EDI (la salida va solo en CF).
; NOTA    : el PUSHFD/POPFD guarda las BANDERAS (el CF de ReadFromFile) mientras
;           CloseFile las cambia; es un dato, no un respaldo de registro.
; ==========================================================================
CargarCatalogo PROC USES eax ecx edx esi edi
    ; --- 1. abrir el archivo ---
    mov  edx, OFFSET nombreArchivo
    call OpenInputFile               ; EAX = handle o INVALID_HANDLE_VALUE
    cmp  eax, INVALID_HANDLE_VALUE
    je   CC_Ausente
    mov  handle_arch, eax

    ; --- 2. leer al buffer temporal ---
    ; Se piden TAM_ARCHIVO+1 bytes: si llegan mas de TAM_ARCHIVO el archivo
    ; es demasiado grande. (Capacidad del buffer = TAM_ARCHIVO+2).
    mov  edx, OFFSET bufArchivo
    mov  ecx, TAM_ARCHIVO + 1
    call ReadFromFile                ; CF=0: EAX = bytes leidos ; CF=1: error
    pushfd                           ; guardar CF antes de llamar a CloseFile
    mov  bytes_io, eax
    mov  eax, handle_arch
    call CloseFile
    popfd
    jc   CC_Invalido                 ; fallo la lectura

    ; --- 3. agregar 00h despues del ultimo byte leido (hay espacio reservado) ---
    mov  eax, bytes_io
    mov  BYTE PTR bufArchivo[eax], 0

    ; --- 4. validar tamano exacto y contenido ---
    cmp  eax, TAM_ARCHIVO
    jne  CC_Invalido
    call ValidarBufferArchivo        ; CF=1 si algo no cumple
    jc   CC_Invalido

    ; --- 5. todo valido: ahora SI se reemplaza el catalogo ---
    cld
    LimpiarBloque codigos, MAX_PRODS*LONG_COD
    LimpiarBloque nombres, MAX_PRODS*LONG_NOM
    LimpiarBloque precios, MAX_PRODS*TAM_DWORD
    LimpiarBloque stock,   MAX_PRODS*TAM_DWORD

    mov  eax, DWORD PTR bufArchivo[POS_CUENTA]   ; EAX = numero de productos
    mov  total_prods, eax

    ; solo se copian 'count' registros de cada arreglo (EAX es la cuenta)
    CopiarRegistros <bufArchivo+POS_CODIGOS>, codigos, eax, LONG_COD
    CopiarRegistros <bufArchivo+POS_NOMBRES>, nombres, eax, LONG_NOM
    CopiarRegistros <bufArchivo+POS_PRECIOS>, precios, eax, TAM_DWORD
    CopiarRegistros <bufArchivo+POS_STOCK>,   stock,   eax, TAM_DWORD

    mov  cambios_sin_guardar, 0
    MostrarCampoUInt msgCargado, total_prods     ; "...Productos: N" + salto
    clc
    ret

CC_Ausente:
    MostrarMsg msgAusente
    stc
    ret

CC_Invalido:
    MostrarMsg msgInvalido
    stc
    ret
CargarCatalogo ENDP

; ==========================================================================
; ValidarBufferArchivo
; Revisa la imagen del archivo que esta en bufArchivo (sin tocar el catalogo).
; Comprueba: firma "INV1", numero de productos 0..10 y, para cada producto:
;   - codigo con formato ABC-123 y sin repetirse,
;   - nombre de 1 a 25 caracteres, terminado en 00h, sin caracteres de control,
;   - precio de 1 a 999999 centavos,
;   - existencia de 0 a 100.
; ENTRADA : bufArchivo con TAM_ARCHIVO bytes
; SALIDA  : CF = 0 valido ; CF = 1 invalido
; REGISTROS: USES conserva EAX EBX ECX EDX ESI EDI (la salida va solo en CF).
; NOTA    : los PUSH/POP dentro de VB_Dup guardan el ESTADO de la comparacion
;           (CMPSB mueve ESI y EDI); no son respaldo de registros del llamador.
; ==========================================================================
ValidarBufferArchivo PROC USES eax ebx ecx edx esi edi
    cmp  DWORD PTR bufArchivo, FIRMA
    jne  VB_Malo                     ; firma incorrecta

    mov  eax, DWORD PTR bufArchivo[POS_CUENTA]
    EnRango eax, 0, MAX_PRODS, VB_Malo   ; 0 a 10 productos
    mov  cuenta_tmp, eax

    xor  ebx, ebx                    ; EBX = indice del registro a revisar
VB_Registro:
    cmp  ebx, cuenta_tmp
    jae  VB_Bien                     ; ya se revisaron todos

    ; --- codigo: formato ABC-123 ---
    imul edx, ebx, LONG_COD
    add  edx, OFFSET bufArchivo + POS_CODIGOS   ; EDX = codigo del registro i
    call ValidarFormatoCodigo
    jc   VB_Malo

    ; --- codigo: no debe repetirse en los registros anteriores ---
    mov  edi, edx                    ; EDI = codigo actual
    mov  esi, OFFSET bufArchivo + POS_CODIGOS   ; ESI = codigo del registro 0
    mov  eax, ebx                    ; EAX = cuantos anteriores faltan por comparar
VB_Dup:
    cmp  eax, 0
    je   VB_Nombre
    push esi
    push edi
    mov  ecx, LONG_COD
    cld
    repe cmpsb                       ; ZF=1 si los 8 bytes son iguales
    pop  edi                         ; (POP no cambia las banderas)
    pop  esi
    je   VB_Malo                     ; iguales -> codigo duplicado
    add  esi, LONG_COD
    dec  eax
    jmp  VB_Dup

    ; --- nombre: 1 a 25 caracteres con 00h dentro de sus 26 bytes ---
VB_Nombre:
    imul esi, ebx, LONG_NOM
    add  esi, OFFSET bufArchivo + POS_NOMBRES
    cmp  BYTE PTR [esi], 0
    je   VB_Malo                     ; nombre vacio
    mov  ecx, LONG_NOM
VB_Chars:
    mov  al, [esi]
    cmp  al, 0
    je   VB_Precio                   ; encontro el terminador a tiempo
    cmp  al, 20h
    jb   VB_Malo                     ; caracter de control
    inc  esi
    dec  ecx
    jnz  VB_Chars
    jmp  VB_Malo                     ; 26 bytes sin 00h -> invalido

    ; --- precio y existencia ---
VB_Precio:
    mov  eax, DWORD PTR bufArchivo[POS_PRECIOS + ebx*4]
    EnRango eax, 1, MAX_CENT, VB_Malo    ; de 1 a 999999 centavos
    mov  eax, DWORD PTR bufArchivo[POS_STOCK + ebx*4]
    EnRango eax, 0, MAX_STOCK, VB_Malo   ; de 0 a 100 unidades

    inc  ebx
    jmp  VB_Registro

VB_Bien:
    clc
    ret
VB_Malo:
    stc
    ret
ValidarBufferArchivo ENDP

END main
