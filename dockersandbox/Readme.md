# Docker Sandbox — Guía `sbx`

`sbx` crea entornos aislados para agentes de IA. El sandbox corre en una microVM separada — los cambios no afectan el host.

---

## Sesión con Claude

```bash
# Arrancar Claude en el directorio actual
sbx run claude .

# Retomar un sandbox existente
sbx run <sandbox>

# Arrancar Claude desde un template guardado
sbx run -t <repo>:<tag> claude .
```

---

## Comandos de uso diario

```bash
sbx ls                          # listar sandboxes
sbx stop <sandbox>              # detener
sbx rm <sandbox> --force        # eliminar
sbx exec <sandbox> <cmd>        # ejecutar comando dentro del sandbox
sbx exec -u root <sandbox> bash # entrar como root
```

---

## Templates — guardar y reusar entornos

El template guarda el estado del sandbox (con todo lo que instalaste) para poder recrearlo después sin reinstalar nada. Útil cuando borras o recreas el sandbox.

### Flujo completo

**1. Instalar lo que necesitas dentro del sandbox:**
```bash
sbx exec -u root <sandbox> bash -c "curl -sL https://aka.ms/InstallAzureCLIDeb | bash"
sbx exec <sandbox> bash -c "az extension add --name azure-devops"
```

**2. Detener y guardar como template:**
```bash
sbx stop <sandbox>
sbx template save <sandbox> <repo>:<tag>
```

Ejemplo:
```bash
sbx template save claude-azureboard azureboard:az-ready
```

**3. Cuando necesites recrear el sandbox (después de borrarlo):**
```bash
sbx rm <sandbox> --force
sbx run -t <repo>:<tag> claude .
```

### Gestión de templates

```bash
sbx template ls                          # listar templates guardados
sbx template rm <repo>:<tag>             # borrar template
sbx template save <sandbox> <tag> --output ./snap.tar   # exportar a archivo
sbx template load ./snap.tar             # importar desde archivo
```

---

## Copiar archivos

```bash
sbx cp ./archivo.json <sandbox>:/home/user/    # host → sandbox
sbx cp <sandbox>:/home/user/output.log ./      # sandbox → host
```

---

## Templates disponibles en este proyecto

| Template | Contiene |
|---|---|
| `azureboard:az-ready` | az CLI + extensión azure-devops |


