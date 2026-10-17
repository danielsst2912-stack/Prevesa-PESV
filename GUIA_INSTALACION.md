# PREVESA · Inspección de Mixers con Supabase — Guía de instalación

Archivos:
- `index.html` — la plataforma (inspección + administración).
- `prevesa_supabase.sql` — tablas, seguridad y funciones para Supabase.

## 1. Crear el proyecto
1. Entra a https://supabase.com y crea un proyecto nuevo (región recomendada: São Paulo, la más cercana a Colombia).
2. Guarda la contraseña de la base de datos en un lugar seguro.

## 2. Crear las tablas
1. En el menú izquierdo abre **SQL Editor → New query**.
2. Pega todo el contenido de `prevesa_supabase.sql` y pulsa **Run**.
3. Debe terminar sin errores rojos. Los avisos tipo "does not exist, skipping" son normales.

## 3. Crear el usuario administrador
1. Ve a **Authentication → Users → Add user → Create new user**.
2. Escribe el correo y una contraseña, y marca **Auto Confirm User**.
3. Vuelve al **SQL Editor** y ejecuta (cambiando el correo):
   ```sql
   insert into public.admins (user_id, email)
   select id, email from auth.users where email = 'TU_CORREO@empresa.com';
   ```
   Repite este paso por cada persona que deba entrar a Administración.
4. Para que nadie más pueda crear cuentas: **Authentication → Sign In / Providers → Email** y desactiva **Allow new users to sign up**.

## 4. Conectar el HTML
1. En Supabase ve a **Project Settings → API** (o **Data API**).
2. Copia la **Project URL** y la clave **anon public**.
   No uses nunca la clave `service_role` en el HTML.
3. Abre `index.html` con el Bloc de notas o VS Code y busca el bloque **CONFIGURACIÓN**:
   ```js
   const SUPABASE_URL      = "PEGA_AQUI_TU_PROJECT_URL";
   const SUPABASE_ANON_KEY = "PEGA_AQUI_TU_ANON_PUBLIC_KEY";
   ```
   Reemplaza los textos entre comillas y guarda.

## 5. Publicar
Sube `index.html` a cualquier hosting de páginas estáticas, por ejemplo:
- **Netlify Drop** (https://app.netlify.com/drop): arrastra la carpeta y listo.
- Vercel, GitHub Pages o el hosting de la empresa.

También funciona abriéndolo directamente en el navegador para probar.

## 6. Primer uso
1. Abre la página → **Administración** → entra con el correo y la contraseña del paso 3.
2. En **Vehículos** registra la flota de mixers.
3. En **Ajustes** cambia el **PIN de inspectores** (viene por defecto como `2026`).
4. Comparte el enlace y el PIN con los inspectores. Ellos no necesitan cuenta: escriben el PIN una vez y el equipo lo recuerda.

## Cómo queda la seguridad
| Quién | Qué puede hacer |
|---|---|
| Inspector (con PIN) | Ver vehículos activos, ver el estado del mes de un vehículo y registrar inspecciones firmadas. No puede ver ni modificar inspecciones de otros. |
| Persona sin PIN | Nada. |
| Administrador (usuario en la tabla `admins`) | Todo: matriz, hallazgos, historial, vehículos, PIN y su contraseña. |

## Consultar los datos
En **Table Editor** verás las tablas `vehiculos`, `inspecciones` y `seguimiento`. Puedes exportarlas a CSV o conectar Power BI / Excel a la base de datos PostgreSQL.
