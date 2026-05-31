# Docker Sandbox — Guía `sbx`

## Setup inicial

```bash
# Construir imagen base
docker build -t sbx .

# Arrancar contenedor
docker run -it --name sbx sbx bash
#           │   │          │   └─ comando a ejecutar dentro del contenedor
#           │   │          └───── imagen a usar (construida arriba)
#           │   └──────────────── nombre del contenedor (para referenciarlo después)
#           └──────────────────── -i mantiene stdin abierto, -t asigna terminal (TTY)
```

---

## Snapshots (guardar estado)

### Guardar snapshot

```bash
docker commit sbx sbx:snap-<nombre>
```

Ejemplo:

```bash
docker commit sbx sbx:snap-antes-de-romper
```

### Listar snapshots

```bash
docker images sbx
```

Output esperado:

```
REPOSITORY   TAG                  IMAGE ID       CREATED         SIZE
sbx          snap-antes-de-romper a1b2c3d4e5f6   2 minutes ago   200MB
sbx          latest               f6e5d4c3b2a1   1 hour ago      198MB
```

### Restaurar snapshot

```bash
# Detener y borrar contenedor actual
docker stop sbx && docker rm sbx

# Arrancar desde snapshot guardado
docker run -it --name sbx sbx:snap-<nombre> bash
```

### Exportar snapshot a archivo

```bash
docker save sbx:snap-<nombre> | gzip > snap-<nombre>.tar.gz
```

### Importar snapshot desde archivo

```bash
docker load < snap-<nombre>.tar.gz
```

---

## Setup C# / ASP.NET + Azure

### Opción A — usar imagen oficial de Microsoft (recomendado)

En vez de imagen base genérica, arrancar desde imagen .NET:

```bash
# .NET 8 SDK (incluye compilador, CLI dotnet, ASP.NET runtime)
docker run -it --name sbx mcr.microsoft.com/dotnet/sdk:8.0 bash
```

Guardar snapshot limpio inmediatamente:

```bash
docker commit sbx sbx:snap-dotnet8-base
```

### Opción B — instalar .NET sobre imagen existente

Dentro del contenedor:

```bash
# Descargar e instalar .NET 8 SDK
curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel 8.0

# Agregar al PATH
echo 'export PATH="$HOME/.dotnet:$PATH"' >> ~/.bashrc && source ~/.bashrc

# Verificar
dotnet --version
```

### Instalar Azure CLI

```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Verificar
az --version

# Login
az login
```

### Instalar Azure Functions Core Tools

```bash
npm install -g azure-functions-core-tools@4 --unsafe-perm true
```

### Instalar extensiones útiles de Azure (via dotnet)

```bash
# Azure SDK packages - agregar al proyecto
dotnet add package Azure.Identity
dotnet add package Azure.Storage.Blobs
dotnet add package Azure.Messaging.ServiceBus
dotnet add package Microsoft.Azure.Functions.Worker
```

### Snapshot después de instalar todo

```bash
# Salir del contenedor o desde otra terminal
docker commit sbx sbx:snap-dotnet8-azure-ready
```

### Flujo recomendado para proyectos ASP.NET

```bash
# 1. Arrancar desde snapshot limpio
docker run -it --name sbx sbx:snap-dotnet8-azure-ready bash

# 2. Crear proyecto ASP.NET
dotnet new webapi -n MiApi && cd MiApi

# 3. Snapshot antes de experimentar
docker commit sbx sbx:snap-miapi-inicial

# 4. Correr
dotnet run
```

---

## Flujo típico

```
1. sbx corriendo
2. docker commit sbx sbx:snap-checkpoint-1   # guardar antes de cambio
3. hacer cambios / experimentos
4. si todo bien -> docker commit sbx sbx:snap-checkpoint-2
5. si rompe    -> restaurar snap-checkpoint-1
```

---

## Borrar snapshots viejos

```bash
# Una imagen
docker rmi sbx:snap-<nombre>

# Todas las dangling
docker image prune
```

---

## Tips

| Situación | Comando |
|-----------|---------|
| Ver diff entre commits | `docker diff sbx` |
| Ver historial de imagen | `docker history sbx:snap-<nombre>` |
| Snapshot con timestamp auto | `docker commit sbx sbx:snap-$(date +%Y%m%d-%H%M%S)` |
