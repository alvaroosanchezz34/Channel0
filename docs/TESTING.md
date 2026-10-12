# Pruebas

## Qué se ha comprobado y cómo

Todo lo siguiente se ejecuta fuera de Roblox Studio (Linux, sin Studio). Además, una partida
individual completa se probó en Roblox Studio a través del MCP de Studio (ver
[STATUS.md](STATUS.md)); el cooperativo y un servidor real de Roblox siguen sin probar.

| Comprobación | Comando | Cubre |
|---|---|---|
| Tests de lógica y contenido | `lune run tests/run` | Ver abajo (51 tests). |
| Validador del mapa | `lune run tools/build/build -- --check` | Solapamientos, muebles flotando, holgura de puertas, alcanzabilidad de todas las salas, presencia de todo lo que usa el servidor. |
| Lint | `selene src` | Errores comunes de Luau (std propio `channel0.yml`, ver nota). |
| Formato | `stylua --check src tools tests` | Estilo uniforme. |
| Tipos | `scripts/analyze.sh` | Todo `src` en `--!strict` con luau-lsp 1.32.1 y las definiciones de Roblox correspondientes. |
| Construcción | `rojo build -o Channel0.rbxl` | El árbol de Rojo es válido y se genera el lugar. |

### Tests (`tests/specs`)

- **logic.spec**: SeededRandom (determinismo, rangos, flujos), RateLimiter, SignalModel (calidad,
  aire muerto, carta de ajuste, sintonía), PhaseClock (topes por objetivos), SessionMachine
  (transiciones legales), AnchorMachine (nunca atrapa durante el aviso de caza, el pre-eco
  siempre precede a la aparición, la caza termina por captura, pérdida, carta o tiempo, y una noche
  simulada larga solo toma transiciones legales), ObjectiveTracker, EventSelector (elegibilidad, cooldowns,
  presupuesto de tensión) y EndingEvaluator.
- **content.spec**: mismas claves y mismos `{tokens}` en inglés y español; resolución de valores
  `@clave`; toda clave citada por el contenido o por el código existe; `Settings.sanitize` ante
  basura, NaN y opciones desconocidas (el filtro VHS no se puede apagar); todo sonido citado
  existe y ningún id es inventado; todos los remotos cliente→servidor tienen límite; el remoto de
  depuración no se crea por defecto; la depuración en servidores reales viene desactivada.

Nota sobre selene: el std oficial de Roblox se genera desde el volcado de la API, que no estaba
accesible en este entorno; `channel0.yml` declara los globales de Roblox como `any`. Los tipos
reales los comprueba luau-lsp.

## Lo que falta probar en Studio

Estas partes dependen del motor y solo se pueden verificar en Studio o en un servidor real:

- Rendimiento de los monitores (ViewportFrames de cámaras) en PC y móvil; el límite de feeds en
  vivo está en `Monitors.luau`.
- El grano con `EditableImage` (hay un respaldo con partículas si la API no está disponible).
- PathfindingService en el mapa generado durante las cazas.
- Sensación de las cazas: tiempo de aviso, velocidad, gracia de captura.
- Interfaz táctil en móvil (prompts propios, botones de luz y correr, paneles).
- Guardado en DataStore (requiere un juego publicado o "Enable Studio Access to API Services").
- Partidas de 2–4 jugadores con desconexiones y entradas a mitad de turno.
- Audio una vez subidos los ids.

## Prueba manual recomendada en Studio

1. `rojo build -o Channel0.rbxl`, abrir, **Play**.
2. Pulsar F8: debe aparecer el panel de depuración (en Studio siempre está autorizado).
3. `start` para saltar el lobby. Seguir los objetivos de la fase A.
4. `skip phase` hasta Anomalía y comprobar la secuencia de las 02:17.
5. `anchor → Hunt`: debe haber aviso de luces y sonido antes de que se mueva; dejarse atrapar y
   comprobar la pantalla "en el aire" y la frecuencia.
6. Probar cada final con los botones de hechos y los dispositivos.
7. **Test → Clients and Servers** con 2–4 jugadores para el cooperativo.
