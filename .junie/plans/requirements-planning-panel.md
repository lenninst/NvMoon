---
sessionId: session-261116-232242-1v04
---

# Requisitos

### Overview & Goals
Crear un **panel de planificación de requisitos** en Neovim que permita documentar, organizar y desglosar requisitos del sistema en tareas accionables, con ayuda de una **skill de ingeniero de requisitos** que guía al agente en el proceso de elicitation y análisis.

### Scope
**In Scope (Etapa 1):**
- Skill de ingeniero de requisitos (`requirements-engineer`) para guiar al agente en el proceso de planificación.
- Workspace dedicado `~/requirements/` para almacenar archivos de requisitos en `.md` y `.norg`.
- Panel interactivo en Neovim para gestionar requisitos (crear, editar, organizar).
- Integración con el gestor de tareas existente (`agent-tasks.lua`): las tareas generadas incluyen un prefijo como `RF001` vinculándolas al requisito.
- Soporte para vincular archivos de referencia (PDF, Word) como adjuntos al requisito.

**Out of Scope (futuras etapas):**
- Soporte completo para norg como formato principal (por ahora markdown es el formato principal).
- Parser automático de PDF/Word para extraer contenido.
- Exportación de requisitos a formatos externos.

### User Stories
- Como desarrollador, quiero escribir mis requisitos en markdown para poder organizar mis ideas de forma estructurada.
- Como desarrollador, quiero que mi agente me ayude a desglosar requisitos en tareas para no perder detalle.
- Como desarrollador, quiero que las tareas generadas estén vinculadas al requisito original (ej. `RF001`) para poder rastrear el progreso.
- Como desarrollador, quiero vincular archivos de referencia (PDF, Word) a un requisito para tener contexto adicional.

### Functional Requirements
1. **Skill de ingeniero de requisitos**: El agente debe seguir un proceso estructurado para elicitar, documentar y desglosar requisitos.
2. **Panel de requisitos**: Interfaz en Neovim para listar, crear y editar requisitos.
3. **Generación de tareas**: Al desglosar un requisito, se crean tareas en el gestor existente con prefijo `RF001`, `RF002`, etc.
4. **Vinculación de archivos**: Posibilidad de adjuntar referencias (PDF, Word) a un requisito.

# Technical Design

### Current Implementation
- **agent-workspace.lua**: Panel unificado de agentes con tabs para threads, skills, y tareas. Usa buffers con namespaces de highlights.
- **agent-tasks.lua**: Gestor de tareas local (JSON en `stdpath("data")`) y GitHub issues. Soporta crear, completar, y verificar tareas.
- **agent-skills.lua**: Manager de skills en `~/.junie/skills/` con estado en `skills.json`.
- **skill-market.lua**: UI para descubrir e instalar skills.
- **skill-repo.lua**: Catálogo de skills descargables desde GitHub.
- **plugins/neorg.lua**: Configuración de Neorg con workspace `notes` en `~/notes/`.

### Key Decisions
- **Formato principal**: Markdown (`.md`) para requisitos, con soporte futuro para `.norg`. Esto permite compatibilidad máxima y facilidad de edición.
- **Workspace separado**: `~/requirements/` como carpeta dedicada, paralelo a `~/notes/`. Esto mantiene los requisitos de proyectos separados de las notas generales.
- **Prefijo en título**: Las tareas generadas incluyen `RF001`, `RNF001` en el título para vinculación visual simple sin modificar la estructura de datos de `agent-tasks.lua`.
- **Patrón de panel**: Seguir el mismo patrón que `agent-workspace.lua` (buffers con highlights, keymaps interactivos, tabs).

### Proposed Changes

**1. Skill de ingeniero de requisitos**
- Crear `~/.junie/skills/requirements-engineer/SKILL.md` con:
  - Frontmatter YAML: nombre, descripción.
  - Secciones: elicitation de requisitos, clasificación (funcionales/no funcionales), desglose en tareas, criterios de aceptación.
  - Flujo de trabajo paso a paso para el agente.

**2. Workspace de requisitos**
- Modificar `lua/lenn/plugins/neorg.lua`: agregar workspace `requirements` apuntando a `~/requirements/`.
- Agregar keymaps en grupo `space y` (Requirements).
- Crear `~/requirements/index.norg` como punto de entrada.

**3. Panel de planificación**
- Crear `lua/lenn/requirements-panel.lua`:
  - Buffer de lista de requisitos con tabs (Requisitos, Tareas, Referencias).
  - Comandos: crear, editar, vincular tareas, adjuntar archivos.
  - Integración con `agent-tasks.lua` para crear tareas con prefijo `RF001`.
  - Keymap `space yp` para abrir el panel.

### File Structure
```
~/.junie/skills/requirements-engineer/
  SKILL.md                          # Skill de ingeniero de requisitos

~/requirements/                     # Nuevo workspace
  index.norg                        # Índice de proyectos

lua/lenn/
  requirements-panel.lua            # Nuevo: panel de planificación
  plugins/neorg.lua                 # Modificado: agregar workspace requirements
  core/keymaps.lua                  # Modificado: agregar keymaps space y

README.md                           # Modificado: agregar sección Requirements
```

### Risks
- **Conflicto de keymaps**: `space y` podría chocar con keymaps existentes. Verificar que no haya colisiones.
- **Complejidad del panel**: El panel de requisitos podría volverse complejo. Mantenerlo simple en la primera etapa: lista de requisitos + integración con tareas.

# Delivery Steps

### ✓ Step 1: Crear skill de ingeniero de requisitos
Crear la skill `requirements-engineer` en `~/.junie/skills/requirements-engineer/SKILL.md` que guíe al agente en ingeniería de requisitos.

- Definir la estructura de la skill con frontmatter YAML (nombre, descripción, secciones).
- Incluir instrucciones para: elicitar requisitos funcionales (RF) y no funcionales (RNF), identificar actores, definir criterios de aceptación.
- Incluir el flujo de trabajo: entender la idea → escribir requisitos → desglosar en tareas → generar tareas con prefijo RF001/RNF001.
- Registrar la skill en el catálogo local para que sea detectable por el Skill Market existente (`skill-repo.lua`).

### ✓ Step 2: Configurar workspace de requisitos en Neovim
Agregar un nuevo workspace `requirements` en la configuración de Neorg y crear las keymaps correspondientes.

- Modificar `lua/lenn/plugins/neorg.lua`: agregar workspace `requirements` apuntando a `~/requirements/`.
- Agregar keymaps en el grupo `space y` (Requirements): abrir workspace, crear nuevo requisito, abrir índice.
- Crear `~/requirements/index.norg` como punto de entrada con la estructura básica de organización.
- Actualizar `README.md` con la nueva sección de Requirements y sus keymaps.

### ✓ Step 3: Crear panel de planificación de requisitos
Crear `lua/lenn/requirements-panel.lua` como un panel interactivo para gestionar requisitos, siguiendo el patrón de `agent-workspace.lua`.

- Crear el módulo con un buffer de lista de requisitos (funcionales RF, no funcionales RNF).
- Implementar la UI con tabs: Requisitos, Tareas vinculadas, Referencias (archivos adjuntos).
- Agregar comandos: crear requisito nuevo, editar, vincular a tareas, abrir en editor.
- Integrar con `agent-tasks.lua` para que al desglosar un requisito en tareas, estas se creen con el prefijo `RF001` en el título.
- Agregar keymap `space yp` para abrir el panel de requisitos.
- Soportar archivos `.md` y `.norg` como formatos de requisitos.
