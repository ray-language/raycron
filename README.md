# raycron

Un cron para tu máquina, escrito en [raylang](https://github.com/ray-language/raylang). Las
expresiones se leen **en tu zona horaria**, con una política clara para los cambios de hora. Cada
job corre como proceso con plazo, queda un historial de ejecuciones, se avisa con una notificación
de escritorio cuando algo falla y se recuperan los disparos perdidos mientras el portátil dormía.

```toml
zone = "Europe/Madrid"

[[job]]
name = "backup"
schedule = "30 2 * * *"
command = ["rsync", "-a", "notas/", "/Volumes/copia/notas/"]
timeout = "10m"
overlap = "queue"
catch_up = true
```

```
raycron check             validar la configuración y ver el próximo disparo de cada job
raycron next 5            los próximos 5 disparos de cada job
raycron explain "*/15 * * * *" Europe/Madrid 8
raycron run               el programador (SIGTERM/SIGINT lo paran, SIGHUP recarga)
raycron now backup        ejecutar un job ya, y anotarlo
raycron history [JOB]     las últimas ejecuciones (con la salida si se pide un job)
```

`-c CONFIG` elige el archivo (por defecto `./raycron.toml`). Hay un ejemplo comentado en
`examples/raycron.toml`.

## Configuración

| Clave | Qué |
|---|---|
| `zone` | zona IANA de las expresiones (por defecto, la del sistema) |
| `state` | archivo de estado: historial y último disparo de cada job (por defecto `raycron.state` junto a la configuración) |
| `notify` | notificación de escritorio cuando un job falla (por defecto `true`) |
| `[[job]] name` | nombre único |
| `schedule` | expresión de cinco campos o `@hourly`/`@daily`/`@weekly`/`@monthly`/`@yearly` |
| `command` | lista de argumentos, o un texto que se pasa a `sh -c` |
| `zone` | zona de este job, si no es la general |
| `dir` | directorio de trabajo (relativo a la configuración) |
| `timeout` | plazo, `90s`/`10m`/`2h` (por defecto 1 h): SIGTERM al grupo del proceso, y SIGKILL 3 s después |
| `overlap` | si el disparo llega con el job aún corriendo: `skip` (por defecto, queda anotado) o `queue` (corre al acabar) |
| `catch_up` | si se perdieron disparos (máquina dormida, raycron parado), ejecutar una vez al volver |

Una clave desconocida es un error (`notfy` no se ignora en silencio), y también lo es una expresión
que nunca se cumple (`0 0 31 2 *`).

## Los cambios de hora

El paquete `cron` calcula en UTC. raycron lee la expresión en la zona con el paquete `tz` y avanza
por tiempo real:

- **Una hora que no existe** (en primavera, Madrid salta de 02:00 a 03:00): el job de las 02:30 se
  lanza **en el salto**, a las 03:00 CEST, como hace Vixie cron.
- **Una hora que se repite** (en otoño, de 02:00 a 02:59 dos veces): un job fijado a una hora
  (`30 2 * * *`) corre **una vez**, en la primera pasada. Uno que corre cada hora (`*/15 * * * *`)
  corre en **las dos**, para que siga cada 15 minutos de tiempo real.
- Zonas raras incluidas: Chile cambia a medianoche (ese día no hay 00:00) y Lord Howe se mueve
  30 minutos.

`raycron explain "30 2 * * *" Europe/Madrid` enseña los disparos con su abreviatura (CET/CEST), y
`RAYCRON_CLOCK=2026-10-25T00:58:00Z raycron run` arranca el reloj del programador en ese instante (y
luego corre a velocidad real): la noche del cambio de hora en un par de minutos (`make demo`).

## Cómo

```
src/main.ray       la línea de órdenes
src/config.ray     el TOML: [[job]], duraciones, validación
src/schedule.ray   cuándo se dispara un job en su zona (cron + tz, los cambios de hora)
src/daemon.ray     el programador: una fibra dueña del estado; señales; reloj; dormir y despertar
src/runner.ray     un job: proceso hijo, plazo, cola de la salida, parada
src/history.ray    el estado en std/kv: ejecuciones (JSON) y último disparo
```

- **Una fibra programa, otra por job.** El programador duerme hasta el próximo disparo, como mucho
  30 s, en un `select_timeout` sobre su canal de eventos. Ahí llegan los jobs que terminan y las
  señales del sistema, reenviadas por una fibra.
- **Los jobs se lanzan con `.stream()`, no con `.run()`.** En un binario nativo, `process.run` deja
  bloqueado su worker hasta que el hijo termina (hallazgo #201). Un job largo congelaría el
  programador si le tocara el mismo worker. Con `stream()` + `wait()` la fibra aparca, así que
  raycron se escribe el plazo (SIGTERM, gracia, SIGKILL) y la cola de la salida.
- **Dormir y despertar.** Cada vuelta compara el reloj de pared con lo que pensaba dormir: un salto
  hacia delante (la tapa cerrada) o hacia atrás (alguien cambió la hora) se anota. Los disparos que
  se pasaron por más de un minuto se cuentan y se avisa. Con `catch_up` se ejecutan una vez, y al
  arrancar también se recupera lo perdido desde el último disparo guardado.
- **Un solo programador por estado**: un `flock` sobre `<state>.lock`.
- **Notificaciones**: `ui.notify_with` y `ui.badge` con el número de fallos. En un binario sin
  bundle, macOS las muestra con `osascript`. Windows aún no las tiene, y raycron lo dice una vez y
  sigue.

## Uso

```bash
make build         # ./raycron, binario nativo
make test          # 21 tests en la VM
make test-native   # los mismos, compilados
make demo          # el ejemplo durante la noche del cambio de hora de octubre
```

## Estado

| Qué | Estado |
|---|---|
| Horarios, configuración, lanzador, programador | **21 tests** en VM y nativo (raylang 1.27.65), también con `RAYLANG_THREADS=1` |
| Cambios de hora | probados en Madrid (los dos), Santiago (medianoche), Lord Howe (30 min), Kolkata (+5:30) |
| De punta a punta | el programador real con reloj virtual en la noche de octubre: el job de cada minuto corre a las 02:00 CET (la segunda), el fijado a las 2 no repite; fallo, plazo e historial |
| Notificación real en macOS | `ui.notify_with` da `Ok` desde el binario nativo sin bundle |
| Dormir el portátil de verdad | **sin probar** (la lógica de disparos perdidos está en tests con instantes elegidos) |
| Windows | en CI; sin zonas (no hay base de zonas, #200): todo en UTC, sin notificaciones ni SIGHUP |

Pendiente: notificación al hacer clic (abrir el historial), `overlap = "kill"`, y lanzarlo como
servicio (launchd/systemd).

## Hallazgos de dogfood

En `findings/open/raycron-1.27.65.md` del directorio de las apps:

1. **#201 [B]** `process.run` en una fibra bloquea su worker en nativo hasta que el hijo termina: 4
   jobs de 1 s tardan 4,1 s con un worker y la fibra principal no avanza. En la VM, 1 s.
   `stream()` + `wait()` sí aparcan.
2. **#202 [E]** El paquete `cron` solo calcula en UTC. La hora local, con sus cambios, la pone
   raycron sobre `tz`.

Y de rayzip, que también afecta aquí: **#200**, en Windows no hay hora local.

Lo que salió bien: `[[job]]` en `std/toml` (arrays de tablas con `toml_array_len`), `std/kv` con
`save` atómico, `tz` con `Gap`/`Ambiguous` y abreviaturas, `select_timeout` como reloj del
programador, `fs.try_lock` para el único programador, y `kill` al grupo del proceso.
