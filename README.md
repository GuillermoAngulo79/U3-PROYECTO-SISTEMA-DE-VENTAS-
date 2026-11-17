Sistema de componentes de PC y hardware (MASM x86 + Irvine32)

Sistema de consola de ventas e inventario para una tienda de componentes de PC, escrito en ensamblador MASM x86 de 32 bits con la biblioteca Irvine32.

Autores: Arnoldo y Guillermo
Versión: Unidad 3 (macros, procedimientos y USES)
Regla de negocio: descuento por cantidad (10 % desde 10 unidades)
Contenido del repositorio
.
|-- README.md                    <- este archivo (instrucciones de compilación)
|-- .gitignore
|-- ProyectoVentas.sln           <- solución de Visual Studio
|-- ProyectoVentas/
|   |-- ProyectoVentas.vcxproj
|   |-- ProyectoVentas.vcxproj.filters
|   |-- Source.asm               <- código de la Unidad 3 (el que se compila)
|   `-- inventario.dat           <- inventario de prueba (3 productos)
|-- U2/
|   `-- Source.asm               <- versión de la Unidad 2 (solo para comparar, NO se compila)
|-- datos_prueba/
|   |-- inventario.dat           <- copia del inventario válido
|   `-- inventario_invalido.dat  <- archivo dañado (100 bytes) para probar el rechazo
`-- reporte/
    `-- Reporte_U3.pdf           <- reporte actualizado

Solo ProyectoVentas/Source.asm forma parte del proyecto. Si se agregaran los dos .asm, el enlazador marcaría main duplicado.

Requisitos
Windows con Visual Studio (2019 o 2022) con la carga de trabajo Desarrollo para el escritorio con C++, que incluye el ensamblador MASM (ml.exe).
Biblioteca Irvine32 instalada (por ejemplo en C:\Irvine). Debe existir Irvine32.inc y Irvine32.lib en esa carpeta.
El programa es de 32 bits: se compila siempre para la plataforma x86 (Win32).
Compilación en Visual Studio
Clona el repositorio y abre ProyectoVentas.sln.
Selecciona la plataforma x86 (no x64) en la barra superior.
Verifica la configuración del proyecto (clic derecho en el proyecto, Propiedades, Todas las configuraciones, plataforma Win32):
Sección	Opción	Valor
Microsoft Macro Assembler > General	Include Paths	C:\Irvine
Vinculador > General	Directorios de bibliotecas adicionales	C:\Irvine
Vinculador > Entrada	Dependencias adicionales	irvine32.lib;kernel32.lib;user32.lib
Vinculador > Sistema	Subsistema	Consola (/SUBSYSTEM:CONSOLE)
Vinculador > Avanzadas	Imagen con controladores de excepciones seguros	No (/SAFESEH:NO)
Comprueba que Proyecto > Personalizaciones de compilación tenga marcado masm, y que Source.asm tenga como Tipo de elemento Microsoft Macro Assembler.
Si Irvine32 está en otra carpeta, cambia C:\Irvine por tu ruta en los dos primeros valores.
Compila con Ctrl + Shift + B y ejecuta con Ctrl + F5.
Compilación por línea de comandos (alternativa)

Abre x86 Native Tools Command Prompt for VS (debe ser la de 32 bits) y, dentro de la carpeta ProyectoVentas:

ml /c /coff /Zi /I C:\Irvine Source.asm
link /SUBSYSTEM:CONSOLE /DEBUG /SAFESEH:NO /LIBPATH:C:\Irvine Source.obj irvine32.lib kernel32.lib user32.lib /OUT:ProyectoVentas.exe
ProyectoVentas.exe
Dónde debe estar inventario.dat

El programa busca inventario.dat en el directorio de trabajo al iniciar:

Al ejecutar desde Visual Studio, el directorio de trabajo es la carpeta del proyecto (ProyectoVentas/), donde ya está inventario.dat.
Al ejecutar el .exe directamente (doble clic o consola), copia inventario.dat junto al .exe.

Si el archivo no existe, el programa avisa e inicia con el catálogo vacío. Si existe pero está dañado, avisa y no modifica el catálogo en memoria.

Formato de inventario.dat (428 bytes, fijo)
Offset	Tamaño	Contenido
0	4	Firma INV1
4	4	Número de productos (DWORD)
8	80	Códigos (10 x 8 bytes, 7 caracteres + 00h)
88	260	Nombres (10 x 26 bytes, 25 caracteres + 00h)
348	40	Precios en centavos (10 DWORD)
388	40	Existencias (10 DWORD)

Al cargar, el programa valida: tamaño exacto, firma, número de productos (0 a 10), formato de código ABC-123 sin repetirse, nombre de 1 a 25 caracteres, precio de 1 a 999999 centavos y existencia de 0 a 100. Solo si todo es válido reemplaza el catálogo.

Productos de prueba incluidos
Código	Producto	Precio	Existencia
GPU-001	RX 5700 XT Gigabyte	4,500.00 MXN	12
CPU-001	AMD Ryzen 5 5600T	3,200.50 MXN	5
MOT-001	AORUS B450 Elite V2	2,100.00 MXN	8
Menú del programa
Registrar y consultar: alta de productos, mostrar inventario, buscar por código.
Recibir mercancía: suma unidades sin pasar de 100.
Vender producto: un producto por venta; con 10 o más unidades aplica 10 % de descuento (la fracción de centavo se descarta).
Resumen de sesión: unidades, valor del inventario e ingresos.
Guardar y salir: escribe inventario.dat.
Salir sin guardar: avisa si hay cambios pendientes.

Los importes se capturan en pesos (por ejemplo 185.50), se guardan en centavos enteros y se muestran siempre con dos decimales y la etiqueta MXN. No se usan ReadDec, ReadInt, ParseDecimal32, WriteDec ni WriteHex.

Demostración sugerida
Iniciar con inventario.dat en su sitio: debe decir Productos: 3.
Alta válida y alta con código duplicado (rechazada).
Búsqueda de GPU-001.
Entrada válida y entrada que pase de 100 unidades (rechazada).
Venta de 3 unidades (sin descuento), venta de 10 (con descuento) y venta mayor a las existencias (rechazada).
Resumen.
Opción 5 (guardar y salir), volver a ejecutar y comprobar que el catálogo se recupera.
Reemplazar inventario.dat por datos_prueba/inventario_invalido.dat (rechazo) y probar también sin el archivo (catálogo vacío).
Cambios de la Unidad 3
Macros: MostrarMsg, MostrarYPausa, PedirCadena, LeerOpcion, MostrarCampoUInt, MostrarCampoMXN, MostrarElemento, EnRango, MostrarSiNo (con LOCAL), ExigirProductos, LimpiarBloque y CopiarRegistros.
Procedimientos nuevos: PedirCodigo, PedirCodigoNuevo, PedirNombre, PedirPrecio, PedirStock, PedirCantidad, RegistrarProducto, CalcularTotales, CalcularImporte y CalcularDescuento.
USES: en 22 de los 24 procedimientos. CalcularImporte no lo necesita porque solo modifica EAX, que es su resultado. main no es un procedimiento llamado.
Líneas de código fuente (no vacías y sin comentarios puros): 1123 en la Unidad 2 y 938 en la Unidad 3. Los push/pop escritos a mano bajaron de 117 a 21.
El detalle, con tabla de antes y después y tabla de pruebas, está en reporte/Reporte_U3.pdf.# U3-PROYECTO-SISTEMA-DE-VENTAS-
