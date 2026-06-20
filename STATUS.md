# Estado de la Versión 1

## ✅ Fase 1: Completada
- **Panel de Ajustes**: Implementado. Podés filtrar qué calendarios ver.
- **Auto-Start**: Implementado con `SMAppService`. Podés activarlo en Ajustes.
- **UI Polished**:
    - Estilo `.window` para un look moderno tipo Notion Calendar.
    - Fondo con efecto translúcido (`VisualEffectView`).
    - ScrollView para eventos y estados vacíos ("No hay más eventos").
    - Hover effects en los eventos.
    - Botón rápido para unirse a llamadas (Zoom/Meet/etc).

## 🚀 Próximos Pasos (Fase 2 y 3)

### 1. Ícono de la App
Para que la app se vea profesional, necesitás un ícono. 
- En Xcode, abrí `Assets.xcassets`.
- Buscá `AppIcon`.
- Arrastrá tu diseño (un .png de 1024x1024 es ideal para empezar).

### 2. Publicación en el App Store
El código está listo para el **Sandbox**. Recordá:
- En la pestaña **Signing & Capabilities**, verificá que **App Sandbox** esté ON y **Calendars** marcado.
- Necesitás una cuenta de Apple Developer ($99/año).
- En Xcode, elegí `Product > Archive` para generar el build de subida.

---
**Nota**: Moví el proyecto a `~/Downloads/MenuBarCalendar_working` para poder editar los archivos. Cuando termines, podés moverlo de vuelta a tu carpeta de Code.
