# Assets

## Regla

Este proyecto no usa ids de assets inventados ni recursos de terceros. Todo lo visual se
construye con piezas y texto (mapa generado, escenas de las cintas, interfaz) y todo el sonido se
sintetiza con `scripts/generate_audio.py`.

## Mapa y escenas

`assets/Station.rbxm` (la emisora) y `assets/Assets.rbxm` (escenas de las cintas, el rig de THE
ANCHOR) se generan con:

```sh
lune run tools/build/build
```

El generador usa solo piezas básicas, materiales de Roblox, luces y `SurfaceGui` con texto. No
hay mallas, texturas ni decals externos.

## Audio

`scripts/generate_audio.py` crea 38 sonidos originales (numpy + ffmpeg/libvorbis) en
`assets/audio/`, con los nombres de archivo de `src/shared/Config/AudioConfig.luau`. Son
deterministas: regenerarlos da los mismos archivos.

```sh
python3 scripts/generate_audio.py        # .ogg
python3 scripts/generate_audio.py --wav  # .wav, sin ffmpeg
```

### Subirlos a Roblox

Roblox no carga archivos locales. Para cada archivo:

1. Creator Hub → Creations → Development Items → Audio → Import (o Asset Manager en Studio →
   Bulk Import).
2. Copia el id del asset subido.
3. Pégalo en la tabla `Ids` de `AudioConfig.luau`, una línea por sonido:
   `StationHum = "rbxassetid://<número>",`

Hasta entonces el juego funciona: los sonidos sin id se omiten y todas las líneas habladas
también salen como subtítulo. En Studio, el controlador de audio avisa por la salida de los
sonidos **esenciales** que faltan (8 marcados abajo). El test `AudioConfig` rechaza cualquier
id que no tenga la forma `rbxassetid://<número>`.

| Nombre | Archivo | Grupo | Bucle | Esencial |
|---|---|---|---|---|
| StationHum | `assets/audio/amb_station_hum.ogg` | Ambience | sí | **sí** |
| Ventilation | `assets/audio/amb_ventilation.ogg` | Ambience | sí | **sí** |
| BasementDrone | `assets/audio/amb_basement_drone.ogg` | Ambience | sí | no |
| ExteriorWind | `assets/audio/amb_exterior_wind.ogg` | Ambience | sí | no |
| StudioRoomTone | `assets/audio/amb_studio_tone.ogg` | Ambience | sí | no |
| TapeHiss | `assets/audio/amb_tape_hiss.ogg` | Ambience | sí | no |
| FluorescentBuzz | `assets/audio/pos_fluorescent_buzz.ogg` | World | sí | no |
| CRTWhine | `assets/audio/pos_crt_whine.ogg` | World | sí | no |
| RackFans | `assets/audio/pos_rack_fans.ogg` | World | sí | no |
| Generator | `assets/audio/pos_generator.ogg` | World | sí | no |
| PhoneRing | `assets/audio/pos_phone_ring.ogg` | World | no | no |
| Footstep | `assets/audio/pos_footstep.ogg` | World | no | no |
| DoorOpen | `assets/audio/pos_door_open.ogg` | World | no | no |
| DoorClose | `assets/audio/pos_door_close.ogg` | World | no | no |
| BreakerFlip | `assets/audio/pos_breaker_flip.ogg` | World | no | no |
| BreakerSpark | `assets/audio/pos_breaker_spark.ogg` | World | no | no |
| VTRInsert | `assets/audio/pos_vtr_insert.ogg` | World | no | no |
| VTREject | `assets/audio/pos_vtr_eject.ogg` | World | no | no |
| LightFail | `assets/audio/pos_light_fail.ogg` | World | no | no |
| Static | `assets/audio/sig_static.ogg` | Signal | sí | **sí** |
| TestTone | `assets/audio/sig_tone_1k.ogg` | Signal | sí | no |
| EASAttention | `assets/audio/sig_eas_attention.ogg` | Signal | no | no |
| Dropout | `assets/audio/sig_dropout.ogg` | Signal | no | **sí** |
| TuneSweep | `assets/audio/sig_tune_sweep.ogg` | Signal | sí | no |
| CarrierLock | `assets/audio/sig_carrier_lock.ogg` | Signal | no | no |
| Interference | `assets/audio/sig_interference.ogg` | Signal | sí | **sí** |
| AnchorHum | `assets/audio/anchor_keylight_hum.ogg` | Anchor | sí | **sí** |
| AnchorPresence | `assets/audio/anchor_presence.ogg` | Anchor | sí | **sí** |
| AnchorStep | `assets/audio/anchor_step.ogg` | Anchor | no | no |
| AnchorSkip | `assets/audio/anchor_skip.ogg` | Anchor | no | no |
| HuntSting | `assets/audio/anchor_hunt_sting.ogg` | Anchor | no | **sí** |
| UIClick | `assets/audio/ui_click.ogg` | Interface | no | no |
| UISwitch | `assets/audio/ui_switch.ogg` | Interface | no | no |
| UIConfirm | `assets/audio/ui_confirm.ogg` | Interface | no | no |
| TapePickup | `assets/audio/ui_tape_pickup.ogg` | Interface | no | no |
| ObjectiveUpdate | `assets/audio/ui_objective.ogg` | Interface | no | no |
| StingerLow | `assets/audio/sting_low.ogg` | Stinger | no | no |
| StingerReveal | `assets/audio/sting_reveal.ogg` | Stinger | no | no |
