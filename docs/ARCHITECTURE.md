# Arquitectura

## Principios

- **Servidor autoritativo.** El cliente solo envía intenciones (`Ready`, `DeviceAction`,
  `DeviceClose`, `Flashlight`, `Sprint`, `Settings`). Todo resultado (señal, objetivos, estado de
  THE ANCHOR, capturas, finales) lo decide el servidor y se publica.
- **Lógica pura separada.** Las máquinas de estado y reglas viven en `src/shared/Logic` sin tocar
  servicios de Roblox, así que se prueban offline con Lune.
- **Contenido como datos.** Cintas, eventos, frecuencias, objetivos, finales y textos están en
  `src/shared/Content`; el código los ejecuta.
- **Semilla por partida.** `SeededRandom` con flujos independientes (`State.stream(name)`) para
  cintas, paneles, eventos, frecuencia perdida y THE ANCHOR: dos partidas no se juegan igual y
  una semilla reproduce una partida.

## Red

`src/shared/Net.luau` es el contrato. El servidor crea todos los `RemoteEvent` bajo
`ReplicatedStorage.Net` al arrancar. El estado de baja frecuencia (sesión, fase, reloj, estado de
THE ANCHOR, tensión...) son atributos de `ReplicatedStorage.SessionState`, de modo que los que
entran tarde lo reciben sin código extra.

Cada remoto cliente→servidor tiene un limitador de tokens por jugador
(`Config/NetConfig.luau`); los mensajes de más se descartan. Todos los argumentos se validan por
tipo, longitud y rango (`Remotes.isString`, `Remotes.isFiniteNumber`, comprobaciones de alcance
a los dispositivos, bloqueo de dispositivo por jugador, estado de la sesión y del jugador).

## Servidor (`src/server/Services`)

`Main.server.luau` requiere los servicios en orden, los registra en `Registry` (búsqueda tardía
para evitar ciclos de `require`), llama a `init()` en todos y después a `start()`.

| Servicio | Responsabilidad |
|---|---|
| Remotes | Crea remotos, limita y valida, publica atributos de estado. |
| World | Indexa el mapa generado: dispositivos, cámaras, monitores, nodos, marcadores, zonas. |
| State | Almacén único: sesión, fase, reloj, hechos, contadores, tripulación, flujos aleatorios. |
| Data | DataStore `Channel0Profiles_v1`: solo preferencias y finales; reintentos y `UpdateAsync`. |
| Lighting, Doors | Estados de luz por zona y puertas (incluido el Estudio B tapiado). |
| Signal | Modelo de señal: calidad, fuente al aire, sintonía, paneles, deriva, aire muerto. |
| Tapes | Reparto de cintas por semilla, recogida, magnetoscopios, pistas. |
| Radio | Resolución del dial y líneas de cada frecuencia (incluida la profecía de *Night Desk*). |
| Feeds | Directivas de cámaras: en vivo, sin señal, recuerdo, desplazado (pre-eco). |
| Crew | Resistencia, linterna, captura y rescate por frecuencia, aislamiento, segunda oportunidad. |
| Phase | Reloj por fases con topes por objetivos y la secuencia de las 02:17. |
| Anchor | Cuerpo de THE ANCHOR guiado por `AnchorMachine`: poses, desplazamiento, caza con pathfinding a saltos, captura con gracia, interferencia. |
| Director | Elige eventos con `EventSelector` según tensión, fase, cooldowns y aislamiento; programa fallos con aviso previo por radio. |
| Endings | Comprueba requisitos con `EndingEvaluator` y lanza finales por elección o automáticos. |
| Devices | Paneles de dispositivos (un jugador por dispositivo), puzles de paneles, taquillas, llave. |
| Session | Ciclo Lobby → Intro → Running → Ending → Results → Resetting, bucle principal, entradas y salidas. |
| Debug | Herramientas de desarrollo con autorización en servidor (ver abajo). |

### THE ANCHOR

`Logic/AnchorMachine.luau` es una máquina determinista con estados Dormant, Broadcast,
Observing, Displacement, Manifestation, Hunt y Withdrawal. Toda transición pasa por la máquina;
el servicio solo aporta contexto y reacciona a eventos. Garantías:

- Una caza siempre va precedida de un aviso (`HuntTelegraph` en `AnchorConfig`) visible y audible.
- No hay muertes instantáneas: la captura exige estar dentro del radio un tiempo de gracia y
  lleva al jugador "al aire", de donde se le puede rescatar.
- Enfriamiento entre cazas y presión escalada por número de jugadores.
- La carta de ajuste en el aire interrumpe su avance.

### Desconexiones

Si alguien sale: se liberan sus dispositivos, la llave de Marsh vuelve a la taquilla, sus cintas
vuelven a aparecer en su ranura y se avisa al resto. Si no queda nadie en el turno, la sesión se
reinicia; si queda alguien, se reevalúa el final de "todos atrapados". Quien entra a mitad
de turno se une al equipo en `Spawn_Late`.

## Cliente (`src/client`)

`Main.client.luau` arranca `Store` y después cada controlador por separado (si uno falla no
bloquea al resto).

| Controlador | Qué hace |
|---|---|
| Store | Caché de todo lo que publica el servidor, ajustes e idioma. |
| VHS | Filtro VHS permanente: corrección de color, bloom, scanlines, grano (EditableImage o polvo), franjas cromáticas, viñeta, bandas de tracking, dropouts, OSD. Perfiles Default / Reduced / MinimalNoise y "reducir movimiento". |
| Audio | Grupos de sonido, camas de ambiente por zona, emisores, bucles de interferencia y presencia, silencios. Tolera ids vacíos. |
| HUD | Objetivos, señal, avisos, subtítulos (radio con estática), inventario, resistencia, botones táctiles. |
| Monitors | Contenido de cada CRT según su rol, con un máximo de feeds en vivo por rendimiento. |
| Devices | Paneles a pantalla completa de cada dispositivo. |
| Menu | Título, lobby, opciones, intro, pantalla de "en el aire", final y resultados. |
| Player, Prompts, StationFX | Linterna/correr/balanceo, prompts propios, animación del hardware. |
| Debug | Panel F8, solo aparece si el servidor envía estado de depuración. |

## Herramientas de depuración

- Activas en Studio, o en servidores reales solo si `DebugConfig.AllowOnLiveServers` es `true`
  **y** el UserId está en `AllowedUserIds` (ambos desactivados por defecto).
- Si no están activas, el remoto `Debug` ni siquiera se crea.
- La autorización se comprueba en cada llamada con el `Player` que entrega `OnServerEvent`;
  nunca con nombres ni ids enviados por el cliente.
- Lista cerrada de comandos (start, reset, skipPhase, anchor, event, god, giveTape, giveKey,
  fact, takeSelf). No hay ejecución arbitraria ni acceso a datos persistentes.

## Mapa

El mapa se genera offline con Lune (`tools/build`) y se guarda como `assets/Station.rbxm` y
`assets/Assets.rbxm`. El validador (`tools/validate`) comprueba solapamientos, muebles flotando,
holgura de puertas, alcanzabilidad de cada sala para un personaje de 2 studs y que existan todos
los dispositivos, cámaras, monitores, ranuras de cinta, spawns y nodos que usa el servidor.
`lune run tools/inspect/inventory` imprime ese contrato.
