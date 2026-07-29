# snuhai-cli — Usar Codex CLI en redes aisladas

[한국어](README.md) · [中文](README.zh-CN.md) · **Español**

Herramienta para usar **[OpenAI Codex CLI](https://github.com/openai/codex)** en equipos de
una red interna **sin acceso a Internet** (red aislada / air-gapped), conectándolo a un
**servidor LLM interno**.

Se creó para la red interna del Hospital Universitario Nacional de Seúl (SNUH), pero funciona
con **cualquier servidor LLM interno que exponga una API compatible con OpenAI**.

---

## Solo dos pasos

```
① En un equipo con Internet  →  ejecute make_snuhai.bat  (una sola vez)
                                 └→ se crea la carpeta snuhai-cli

② Copie esa carpeta entera al equipo aislado  →  doble clic en snuhai.bat
                                                  └→ listo, ya puede usarlo.
```

En el equipo aislado **no hace falta instalar nada de antemano**, ni siquiera Node.js
(se incluye un Node portátil dentro de la carpeta).

---

## ① Crear el paquete (equipo con Internet, una sola vez)

```bat
git clone https://github.com/<usuario>/snuhai-cli.git
cd snuhai-cli
make_snuhai.bat
```

```bash
./make_snuhai.sh          # para crearlo desde Linux/macOS
```

- `make_snuhai.bat` genera por defecto la versión de Windows. Puede cambiar el destino con
  `make_snuhai.bat linux` / `both` (`make_snuhai.sh` usa `both` por defecto).
- Codex CLI se descarga **sin modificar** del registro público de npm y se **verifica su
  integridad** contra el hash publicado por npm (el comprobante queda en
  `.snuhai/packages/PROVENANCE.txt`).

Al terminar se crea la carpeta `snuhai-cli`. Copie **la carpeta completa** (por ejemplo, en una memoria USB).

```
snuhai-cli/
├── snuhai.bat        ← Windows: ejecute solo esto
├── snuhai.sh         ← Linux
├── 읽어보세요.txt     ← instrucciones (en coreano)
└── .snuhai/          ← archivos necesarios (no los borre)
```

## ② Usarlo en el equipo aislado

Haga doble clic en `snuhai.bat`. Solo la primera vez se le preguntará:

```
Dirección del servidor: https://llm.example.org/v1
Clave API:              ****
Modelo a usar:          (muestra la lista obtenida del servidor)
```

A partir de ahí todo es automático:

- Instala Codex CLI **sin conexión** (solo la primera vez).
- Comprueba **si el servidor admite la Responses API**: si la admite se conecta directamente;
  si no, **inicia la pasarela automáticamente** (véase más abajo).
- La configuración se guarda en `%USERPROFILE%\.snuhai`, así que las siguientes veces arranca directo.

Los argumentos se pasan tal cual a codex:

```bat
snuhai.bat                                       :: modo interactivo
snuhai.bat exec "explica qué hace este repositorio"
```

---

## Por qué hace falta la pasarela

Las versiones recientes de Codex CLI solo admiten la **Responses API**
(`wire_api = "chat"` se eliminó en febrero de 2026). Sin embargo, vLLM o litellm —lo que se
suele desplegar internamente— a menudo solo ofrecen **Chat Completions**.

`.snuhai/gateway.js` traduce entre ambas. Es un único archivo de Node **sin dependencias**,
**no almacena claves** y reenvía la cabecera `Authorization` tal cual al servidor.
Escucha solo en `127.0.0.1` y se cierra junto con codex.

Además, algunos modelos devuelven `System message must be at the beginning`; la pasarela
**normaliza el mensaje de sistema al principio** y evita ese error.

---

## Cambiar la configuración

| Objetivo | Cómo |
|---|---|
| Volver a configurar servidor/clave/modelo | Borre `%USERPROFILE%\.snuhai\conf.bat` (Linux: `~/.snuhai/conf.sh`) y vuelva a ejecutar |
| Cambiar solo el modelo | Edite el valor de `MODEL=` en ese mismo archivo |
| Reinstalar | Borre `.snuhai\installed.flag` y vuelva a ejecutar |

## Solución de problemas

| Síntoma | Acción |
|---|---|
| `401` | Clave incorrecta: borre el archivo de configuración y vuelva a ejecutar |
| `400 System message must be at the beginning` | La pasarela está desactivada. Ponga `GW=1` en la configuración y reinicie |
| `Model metadata ... not found` | **Inofensivo**, puede ignorarlo |
| No aparece la lista de modelos | Compruebe que la dirección termina en `/v1` y que la clave es correcta |
| Dice que falta la carpeta `.snuhai` | No copió la carpeta completa; cópiela de nuevo |

---

## Seguridad

- **No suba claves de API al repositorio.** La configuración se guarda solo en `~/.snuhai` de cada equipo.
- La pasarela escucha únicamente en `127.0.0.1`. No la exponga al exterior.
- Indique siempre un **servidor LLM interno** para que los datos internos no salgan al exterior.

## Licencia

- Código propio de este repositorio (`gateway.js`, scripts, documentación): **Apache-2.0** (`LICENSE`)
- **Este repositorio no incluye OpenAI Codex CLI.** `make_snuhai` lo descarga **sin modificar**
  desde el registro público de npm (Apache-2.0; véase `NOTICE`).
- Tampoco incluye Node.js: se descarga desde nodejs.org (MIT y otras).
- «OpenAI» y «Codex» son marcas de OpenAI. Este proyecto no está afiliado a OpenAI ni cuenta con su respaldo.
