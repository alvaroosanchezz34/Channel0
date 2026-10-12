# CHANNEL 0: informe de estado

Leyenda: **IMPLEMENTADO** = el código está escrito y pasa las comprobaciones estáticas.
**PROBADO** = verificado con una ejecución real (tests offline, validador, build).
**PENDIENTE** = falta hacerlo o verificarlo. **BLOQUEADO** = no se puede hacer desde aquí.

El 12/10/2026 se probó una partida individual en el Roblox Studio de Koke a través del MCP de
Studio (sin audio subido y sin cooperativo). Lo recorrido está marcado como **PROBADO EN STUDIO**;
el resto sigue sin validar jugando.

## 1. Estado real del juego

El juego está completo en código y es jugable en solitario en Studio. Pasan los 51 tests offline,
el validador del mapa, selene, StyLua, luau-lsp en modo estricto y `rojo build`.

**PROBADO EN STUDIO** (partida individual): título, opciones, lobby y "Listo", intro, fichar en
recepción, llegar al control central, encender el mezclador, sintonizar y fijar la portadora,
rearmar los cuadros A y B en su orden, coger la cinta de relleno, cargarla en el magnetoscopio y
ponerla al aire, revisar cámaras en la consola, la anomalía de las 02:17, una caza de THE ANCHOR
con captura, la segunda oportunidad en solitario, el final "Señal perdida", resultados y vuelta al
lobby. Sin errores en la consola.

Errores encontrados en Studio y corregidos: los monitores metían geometría con colisión en el
mundo y empujaban al jugador (incluso a través de paredes); el ratón quedaba bloqueado en primera
persona y no se podían pulsar los paneles; las teclas del sintonizador movían al personaje y E
reabría el dispositivo; la cámara podía quedarse congelada tras la intro; el contador de cámaras
mostraba `{progress}`; los subtítulos no caducaban fuera del turno; el panel F8 no podía forzar la
caza desde cualquier estado.

## 2. Sistemas implementados

| Sistema | Estado |
|---|---|
| Mapa de KZRO (2 plantas, exterior, 25 dispositivos, 8 cámaras, 31 monitores, 13 ranuras de cinta, 230 nodos) | IMPLEMENTADO · validador PROBADO |
| Ciclo de sesión (lobby, intro, turno, final, resultados, reinicio) | IMPLEMENTADO |
| Fases A–F con reloj que se detiene por objetivos y la anomalía de las 02:17 | IMPLEMENTADO · lógica PROBADA |
| Señal (calidad, aire muerto, fuentes, carta de ajuste, sintonía, paneles, deriva) | IMPLEMENTADO · modelo PROBADO |
| THE ANCHOR (máquina de estados, pre-eco, cazas con aviso, captura con gracia) | IMPLEMENTADO · máquina PROBADA |
| Director de eventos (18 eventos, tensión, cooldowns, fallos con profecía) | IMPLEMENTADO · selector PROBADO |
| Cintas VHS (10 cintas, pistas por semilla, magnetoscopios) | IMPLEMENTADO |
| Radio (6 frecuencias, canal cero por semilla) | IMPLEMENTADO |
| Captura y rescate por frecuencia, segunda oportunidad en solitario | IMPLEMENTADO |
| 5 finales | IMPLEMENTADO · evaluador PROBADO |
| Filtro VHS permanente con 3 perfiles y "reducir movimiento" | IMPLEMENTADO |
| Audio por capas (38 sonidos originales generados) | IMPLEMENTADO · archivos PROBADOS (sin silencios ni saturación) · ids PENDIENTES |
| Interfaz PC y móvil (HUD, paneles, menús, prompts táctiles) | IMPLEMENTADO |
| Persistencia (solo preferencias y finales) | IMPLEMENTADO |
| Remotos con límite y validación | IMPLEMENTADO · contrato PROBADO |
| Herramientas de depuración solo para autorizados | IMPLEMENTADO · valores por defecto PROBADOS |
| Inglés y español | IMPLEMENTADO · paridad PROBADA |

## 3. Arquitectura y módulos principales

Servidor autoritativo con 18 servicios registrados en orden; lógica pura en `src/shared/Logic`;
contenido como datos en `src/shared/Content`; cliente con un `Store` central y controladores
independientes. Detalle en [ARCHITECTURE.md](ARCHITECTURE.md).

## 4. Filtro VHS

Una capa de interfaz siempre activa (`src/client/Controllers/VHS.luau`): corrección de color y
tinte cálido, bloom, scanlines, grano (EditableImage con respaldo de partículas), franjas
cromáticas en los bordes, viñeta, parpadeo de luminancia, bandas de tracking y de cambio de
cabezal, dropouts y un OSD con la hora ficticia. Reacciona a la tensión, a la cercanía de THE
ANCHOR y a pulsos de eventos con un techo para que nada deje el juego injugable. Perfiles
Default, Reduced y MinimalNoise (`VHSConfig.luau`); "reducir movimiento" quita sacudidas y
destellos. No se puede apagar, solo suavizar. **PENDIENTE**: verlo en Studio y en móvil.

## 5. THE ANCHOR

Máquina determinista (`Logic/AnchorMachine.luau`): Dormant, Broadcast, Observing, Displacement,
Manifestation, Hunt y Withdrawal. En Displacement, una cámara lo muestra en un sitio y unos
segundos después aparece allí de verdad (la regla que enseña la cinta de orientación). La caza
siempre va precedida de 6,5 s de aviso (luces del estudio y zumbido), avanza a saltos con
PathfindingService y solo atrapa tras 0,35 s dentro del radio. Atrapar lleva "al aire", no mata.
La carta de ajuste fuerza la retirada. **PENDIENTE**: ajustar velocidad y tiempos jugando.

## 6. Señal y cámaras

La calidad depende de la consola, la fuente al aire, la sintonía, los paneles y los fallos. El
aire muerto prolongado sube la presión. Las cámaras se ven en el panel de seguridad y en los
monitores con geometría real clonada en ViewportFrames y figuras proxy; el servidor decide si un
feed está en vivo, sin señal, en "recuerdo" o desplazado (adelantado). Hay un límite de feeds en
vivo simultáneos por rendimiento. **PENDIENTE**: medir rendimiento en Studio y en móvil.

## 7. Mecánicas y objetivos

Fichar, llegar al control central, encender la consola, ver la orientación, sintonizar la
portadora a 55.25, restaurar los paneles A y B en el orden pegado en su puerta, cargar el relleno,
revisar cámaras (escala con el número de jugadores), presenciar la anomalía, buscar y ver cintas,
abrir el canal cero, rescatar compañeros sintonizando su frecuencia y decidir un final. Linterna,
correr con resistencia y prompts propios con soporte táctil.

## 8. Eventos y finales

18 eventos en cuatro niveles (sutiles, intermedios, críticos y fallos), elegidos según fase,
tensión, cooldowns, repeticiones y aislamiento; los fallos se anuncian antes por la radio.
Finales: La emisión completa, El nuevo presentador, Sin señal, Un momento, por favor (amanecer)
y Señal perdida. Requisitos en [NARRATIVE.md](NARRATIVE.md).

## 9. Pruebas ejecutadas y resultados reales

| Comprobación | Resultado |
|---|---|
| `lune run tests/run` | 51 pasan, 0 fallan |
| `lune run tools/build/build -- --check` | validación sin errores (2.493 piezas) |
| `selene src` | 0 errores, 0 avisos |
| `stylua --check src tools tests` | sin diferencias |
| luau-lsp 1.32.1, `--!strict` en todo `src` | 0 errores |
| `rojo build` | genera el lugar (290 KB) |
| Generador de audio | 38 archivos, ninguno en silencio ni saturado |
| Roblox Studio (MCP, partida individual) | recorrido completo de una noche hasta un final, ver sección 1 |

El test de contenido encontró 18 descripciones de eventos sin traducir al español; están
corregidas.

## 10. Errores conocidos

- Sin probar en Studio: el cooperativo, los otros cuatro finales, el resto de eventos, móvil y
  mando.
- Sin ids de audio el juego está en silencio (los textos y subtítulos funcionan).
- `EditableImage` puede no estar disponible en todas las cuentas o plataformas; entonces se usa
  el grano de respaldo, menos fino.
- Los feeds de cámara clonan geometría: en móviles modestos puede hacer falta bajar el límite de
  feeds en vivo.
- El lint de selene usa un std permisivo (globales de Roblox como `any`) porque el std oficial no
  se pudo descargar; los tipos los comprueba luau-lsp.

## 11. Assets que hay que importar o configurar

- Subir los 38 sonidos de `assets/audio/` y pegar sus ids en la tabla `Ids` de
  `src/shared/Config/AudioConfig.luau` (los 8 esenciales primero). Lista en [ASSETS.md](ASSETS.md).
- Opcional: activar "Enable Studio Access to API Services" para probar el guardado en Studio.
- No hace falta nada más: el mapa, las escenas y la interfaz están hechos con piezas y texto.

## 12. Abrir el proyecto en Studio con Rojo

1. `rokit install` en la raíz del repositorio.
2. Instalar el plugin de Rojo 7.4.x en Studio.
3. `rojo serve`, abrir una Baseplate en Studio, borrar la Baseplate y conectar el plugin a
   `localhost:34872`. O bien `rojo build -o Channel0.rbxl` y abrir el archivo.

## 13. Probar una partida individual

Pulsar **Play**, "Empezar turno de noche" y "Listo" (la cuenta atrás arranca con un jugador
listo). En Studio, F8 abre el panel de depuración para saltar fases, forzar estados de THE
ANCHOR, lanzar eventos, dar cintas o la llave y activar hechos para probar cada final.

## 14. Probar una partida cooperativa

En Studio: pestaña **Test** → **Clients and Servers**, elegir 2–4 jugadores y **Start**. Probar
listos y cuenta atrás, reparto de dispositivos (uno por jugador), captura y rescate por
frecuencia, desconectar a un cliente a mitad de turno y unirse tarde.

## 15. Qué falta para publicar

1. Probar en Studio el cooperativo (2–4 jugadores) y los demás finales.
2. Subir el audio y pegar los ids.
3. Ajustar tiempos (fases, cazas, fallos) y la intensidad del filtro tras jugar varias partidas.
4. Pruebas de rendimiento en móvil y de 4 jugadores.
5. Icono, miniaturas, descripción y cuestionario de clasificación por edad en el Creator Hub.
6. Publicar (no se ha hecho ni se hará sin tu autorización).
