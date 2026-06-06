# Taller de Informática Forense en macOS

**Autor:** Edwin Moreyra
**Script:** `taller_forense.sh`
**Requisitos:** Mac con macOS 10.15+ y Terminal (no requiere software adicional)

---

## ¿Qué hace este script?

Automatiza el flujo de adquisición, verificación e integridad de evidencia digital en macOS usando exclusivamente herramientas nativas del sistema operativo.

El flujo completo (`-m all`) sigue este orden:

1. **Módulo A — Adquisición:** Copia forense con `rsync -avE` preservando atributos extendidos, con bitácora de sesión (`script`) y log detallado.
2. **Módulo C — Hashing:** Genera y compara hashes MD5, SHA-1 y SHA-256 entre origen y destino para verificar integridad bit a bit.
3. **Bloqueo:** Protege la evidencia copiada aplicando `chflags -R uchg` (solo lectura).
4. **Módulo B — Metadatos:** Compara atributos extendidos (`xattr -l`) y metadatos de Spotlight (`mdls`) entre origen y destino, **sin forzar indexación** de Spotlight. Se ejecuta después del bloqueo para validar la evidencia ya protegida.

Todo queda registrado en un log de ejecución con marcas de tiempo (`registro_ejecucion_TIMESTAMP.log`).

---

## Uso rápido

```
# Dar permisos de ejecución (solo la primera vez)
chmod +x taller_forense.sh

# Ejecutar flujo completo con rutas por defecto
./taller_forense.sh

# Ver ayuda completa integrada
./taller_forense.sh -h
```

---

## Opciones

- `-o RUTA` — Directorio de origen (evidencia a adquirir)
- `-d RUTA` — Directorio de destino (donde se copia la evidencia)
- `-l RUTA` — Directorio de logs (bitácoras, hashes, reportes)
- `-m MÓD` — Módulo a ejecutar: `all` (defecto), `a`, `b`, `c`
- `-h` — Mostrar manual integrado

Rutas por defecto (si no se especifican):

```
Origen:  ~/Taller_Forense/Origen
Destino: ~/Taller_Forense/Destino
Logs:    ~/Taller_Forense/Logs
```

---

## Ejemplos

```
# Flujo completo con disco externo como destino
./taller_forense.sh -o /Users/sospechoso/Documents -d /Volumes/USB/Evidencia

# Solo adquisición (Módulo A)
./taller_forense.sh -m a

# Solo hashing (Módulo C) + bloqueo
./taller_forense.sh -m c

# Solo verificación de metadatos (Módulo B)
./taller_forense.sh -m b

# Personalizar todas las rutas
./taller_forense.sh -o /origen -d /destino -l /mis/logs -m all
```

---

## Estructura del proyecto

```
~/Taller_Forense/
├── taller_forense.sh       ← Script de automatización
├── MANUAL_TALLER.md        ← Este documento
├── Origen/                 ← Evidencia a adquirir
├── Destino/                ← Copia protegida (bloqueada tras validación)
└── Logs/                   ← Bitácoras, hashes, reportes
```

---

## Archivos generados en Logs/

Cada ejecución genera archivos con timestamp único (no sobrescribe anteriores):

- `registro_ejecucion_TIMESTAMP.log` — Log maestro con todos los eventos
- `bitacora_rsync_TIMESTAMP.txt` — Sesión de terminal grabada (Módulo A)
- `rsync_detalle_TIMESTAMP.log` — Log técnico de rsync (Módulo A)
- `hash_md5_origen/destino_TIMESTAMP.txt` — Hashes MD5 (Módulo C)
- `hash_sha1_origen/destino_TIMESTAMP.txt` — Hashes SHA-1 (Módulo C)
- `hash_sha256_origen/destino_TIMESTAMP.txt` — Hashes SHA-256 (Módulo C)
- `reporte_validacion_hashes_TIMESTAMP.txt` — Resultado consolidado (Módulo C)
- `reporte_xattr_TIMESTAMP.txt` — Comparación atributos extendidos (Módulo B)
- `reporte_mdls_TIMESTAMP.txt` — Comparación metadatos Spotlight (Módulo B)

---

## Herramientas nativas utilizadas

- `rsync -avE` — Copia forense preservando atributos extendidos de macOS
- `script` — Grabación auditable de sesión de terminal
- `xattr -l` — Lectura directa de atributos extendidos del archivo
- `mdls` — Lectura de metadatos del índice de Spotlight
- `md5` / `shasum` — Hashing (MD5, SHA-1, SHA-256)
- `chflags uchg` — Protección de archivos contra escritura
- `find`, `diff` — Iteración recursiva y comparación

No se requiere instalación de software adicional.

---

## Desbloquear evidencia

Si necesitas modificar archivos bloqueados en el destino:

```
chflags -R nouchg ~/Taller_Forense/Destino
```

---

## Notas importantes

- El script **no fuerza** la indexación de Spotlight (`mdimport`). La validación `mdls` lee el índice tal como está.
- Si `mdls` muestra diferencias pero `xattr` coincide, la copia es íntegra — Spotlight es asíncrono.
- El bloqueo `uchg` se aplica **antes** de la validación de metadatos para garantizar que la evidencia ya está protegida al momento de revisarla.
- Los Módulos B y C requieren que el Módulo A se haya ejecutado primero.
