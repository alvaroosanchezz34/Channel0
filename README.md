# CHANNEL 0

Juego cooperativo de terror analógico para Roblox (1–4 jugadores, 15–25 minutos).

Octubre de 1998. Sois el turno de ingeniería nocturno de **KZRO-TV**, una pequeña emisora de
Marrow Falls (Montana). La misión parece sencilla: mantener la señal en el aire hasta las 6:00.
Pero a las 02:17 los monitores empiezan a emitir un programa que no existe, presentado por
**THE ANCHOR**, el presentador de un informativo que se canceló en 1987.

Todo gira alrededor de **la señal**: frecuencias, interferencias, cámaras de seguridad que van
unos segundos por delante, cintas VHS que cambian al reproducirse y un sintonizador con el que
podéis recuperar a compañeros atrapados "en el aire".

## Requisitos

- [Roblox Studio](https://create.roblox.com/)
- [Rokit](https://github.com/rojo-rbx/rokit) para instalar las herramientas fijadas en `rokit.toml`
  (Rojo 7.4.4, Lune 0.8.9, selene 0.27.1, StyLua 0.20.0, luau-lsp 1.32.1).
- El plugin de Rojo para Studio (versión 7.4.x).
- Python 3 con numpy y ffmpeg (solo si quieres regenerar el audio).

```sh
rokit install
```

## Abrirlo en Studio

Opción A, sincronización en vivo:

```sh
rojo serve
```

Abre Studio con una plantilla vacía (Baseplate), borra la Baseplate, conecta el plugin de Rojo a
`localhost:34872` y pulsa **Play**.

Opción B, archivo de lugar:

```sh
rojo build -o Channel0.rbxl
```

Abre `Channel0.rbxl` en Studio.

Antes de publicar:

1. Sube los sonidos de `assets/audio/` y pega sus ids en `src/shared/Config/AudioConfig.luau`
   (ver [docs/ASSETS.md](docs/ASSETS.md)). Sin ids el juego funciona igual, con subtítulos y sin
   sonido; en Studio se avisa por la salida de qué sonidos esenciales faltan.
2. Activa **Enable Studio Access to API Services** en la configuración del juego si quieres probar
   el guardado de preferencias y finales en Studio. Sin acceso a DataStore el juego sigue, sin
   guardar.
3. Revisa `src/shared/Config/DebugConfig.luau`: las herramientas de depuración están apagadas en
   servidores reales por defecto y así deben quedarse salvo que añadas tu UserId a propósito.

## Comprobaciones locales

```sh
lune run tests/run                    # tests de lógica y contenido (offline)
lune run tools/build/build -- --check # valida el mapa (colisiones, alcanzabilidad, colocación)
selene src                            # lint
stylua --check src tools tests        # formato
DEFS=globalTypes.d.luau scripts/analyze.sh  # tipos con luau-lsp
rojo build -o Channel0.rbxl           # construye el lugar
```

Detalles en [docs/TESTING.md](docs/TESTING.md).

## Documentación

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): servidor autoritativo, red, estado y sistemas.
- [docs/NARRATIVE.md](docs/NARRATIVE.md): historia, fases, cintas, frecuencias y finales.
- [docs/ASSETS.md](docs/ASSETS.md): audio original, mapa generado y cómo subir los assets.
- [docs/TESTING.md](docs/TESTING.md): qué está probado, cómo, y qué falta probar en Studio.

## Estructura

```
src/shared     lógica pura (máquinas de estado, señal, director), configuración y contenido
src/server     servicios autoritativos (sesión, fases, señal, THE ANCHOR, director, datos...)
src/client     controladores (filtro VHS, audio, HUD, monitores, paneles, menús)
tools/build    generador offline del mapa de la estación (Lune) con validadores
assets         Station.rbxm y Assets.rbxm generados, y el audio original
tests          runner offline (Lune) y specs
scripts        análisis de tipos y generador de audio
```
