

-- ============================================
-- SISTEMA DE GESTION DE EXPEDIENTES DE CASOS
-- FASE 3: DISENO FISICO
-- SGBD: PostgreSQL
-- ============================================

-- 1. TABLAS DE CATALOGOS

CREATE TABLE tipo_caso (
    id_tipo_caso INTEGER GENERATED ALWAYS AS IDENTITY,
    nombre VARCHAR(100) NOT NULL,
    descripcion TEXT,
    activo BOOLEAN NOT NULL DEFAULT TRUE,

    CONSTRAINT pk_tipo_caso PRIMARY KEY (id_tipo_caso),
    CONSTRAINT uq_tipo_caso_nombre UNIQUE (nombre)
);

CREATE TABLE estado (
    id_estado INTEGER GENERATED ALWAYS AS IDENTITY,
    nombre VARCHAR(50) NOT NULL,
    descripcion TEXT,
    es_final BOOLEAN NOT NULL DEFAULT FALSE,

    CONSTRAINT pk_estado PRIMARY KEY (id_estado),
    CONSTRAINT uq_estado_nombre UNIQUE (nombre)
);

CREATE TABLE rol_persona (
    id_rol INTEGER GENERATED ALWAYS AS IDENTITY,
    nombre VARCHAR(80) NOT NULL,
    descripcion TEXT,

    CONSTRAINT pk_rol_persona PRIMARY KEY (id_rol),
    CONSTRAINT uq_rol_persona_nombre UNIQUE (nombre)
);

CREATE TABLE tipo_documento (
    id_tipo_documento INTEGER GENERATED ALWAYS AS IDENTITY,
    nombre VARCHAR(100) NOT NULL,
    descripcion TEXT,

    CONSTRAINT pk_tipo_documento PRIMARY KEY (id_tipo_documento),
    CONSTRAINT uq_tipo_documento_nombre UNIQUE (nombre)
);


-- 2. TABLAS PRINCIPALES

CREATE TABLE expediente (
    id_expediente INTEGER GENERATED ALWAYS AS IDENTITY,
    codigo VARCHAR(30) NOT NULL,
    titulo VARCHAR(200) NOT NULL,
    descripcion TEXT,
    fecha_apertura DATE NOT NULL DEFAULT CURRENT_DATE,
    fecha_cierre DATE,
    id_tipo_caso INTEGER NOT NULL,
    id_estado INTEGER NOT NULL,

    CONSTRAINT pk_expediente PRIMARY KEY (id_expediente),
    CONSTRAINT uq_expediente_codigo UNIQUE (codigo),

    CONSTRAINT fk_expediente_tipo_caso
        FOREIGN KEY (id_tipo_caso)
        REFERENCES tipo_caso(id_tipo_caso)
        ON DELETE RESTRICT,

    CONSTRAINT fk_expediente_estado
        FOREIGN KEY (id_estado)
        REFERENCES estado(id_estado)
        ON DELETE RESTRICT,

    CONSTRAINT chk_expediente_fechas
        CHECK (
            fecha_cierre IS NULL
            OR fecha_cierre >= fecha_apertura
        )
);

CREATE TABLE persona (
    id_persona INTEGER GENERATED ALWAYS AS IDENTITY,
    nombres VARCHAR(100) NOT NULL,
    apellidos VARCHAR(100) NOT NULL,
    tipo_documento VARCHAR(40),
    numero_documento VARCHAR(40),
    telefono VARCHAR(30),
    correo VARCHAR(150),
    direccion TEXT,

    CONSTRAINT pk_persona PRIMARY KEY (id_persona),
    CONSTRAINT uq_persona_documento UNIQUE (numero_documento)
);

CREATE TABLE funcionario (
    id_funcionario INTEGER GENERATED ALWAYS AS IDENTITY,
    nombres VARCHAR(100) NOT NULL,
    apellidos VARCHAR(100) NOT NULL,
    cargo VARCHAR(100),
    telefono VARCHAR(30),
    correo VARCHAR(150) NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,

    CONSTRAINT pk_funcionario PRIMARY KEY (id_funcionario),
    CONSTRAINT uq_funcionario_correo UNIQUE (correo)
);


-- 3. TABLAS ASOCIATIVAS

CREATE TABLE expediente_persona (
    id_expediente INTEGER NOT NULL,
    id_persona INTEGER NOT NULL,
    id_rol INTEGER NOT NULL,
    fecha_vinculacion DATE NOT NULL DEFAULT CURRENT_DATE,
    observacion TEXT,

    CONSTRAINT pk_expediente_persona
        PRIMARY KEY (id_expediente, id_persona, id_rol),

    CONSTRAINT fk_ep_expediente
        FOREIGN KEY (id_expediente)
        REFERENCES expediente(id_expediente)
        ON DELETE RESTRICT,

    CONSTRAINT fk_ep_persona
        FOREIGN KEY (id_persona)
        REFERENCES persona(id_persona)
        ON DELETE RESTRICT,

    CONSTRAINT fk_ep_rol
        FOREIGN KEY (id_rol)
        REFERENCES rol_persona(id_rol)
        ON DELETE RESTRICT
);

CREATE TABLE asignacion (
    id_asignacion INTEGER GENERATED ALWAYS AS IDENTITY,
    id_expediente INTEGER NOT NULL,
    id_funcionario INTEGER NOT NULL,
    fecha_inicio DATE NOT NULL DEFAULT CURRENT_DATE,
    fecha_fin DATE,
    es_responsable BOOLEAN NOT NULL DEFAULT FALSE,

    CONSTRAINT pk_asignacion PRIMARY KEY (id_asignacion),

    CONSTRAINT fk_asignacion_expediente
        FOREIGN KEY (id_expediente)
        REFERENCES expediente(id_expediente)
        ON DELETE RESTRICT,

    CONSTRAINT fk_asignacion_funcionario
        FOREIGN KEY (id_funcionario)
        REFERENCES funcionario(id_funcionario)
        ON DELETE RESTRICT,

    CONSTRAINT chk_asignacion_fechas
        CHECK (
            fecha_fin IS NULL
            OR fecha_fin >= fecha_inicio
        )
);


-- 4. TABLAS DE DOCUMENTOS Y SEGUIMIENTO

CREATE TABLE documento (
    id_documento INTEGER GENERATED ALWAYS AS IDENTITY,
    id_expediente INTEGER NOT NULL,
    id_tipo_documento INTEGER NOT NULL,
    nombre VARCHAR(200) NOT NULL,
    descripcion TEXT,
    ubicacion_archivo TEXT,
    fecha_documento DATE,
    fecha_registro TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_documento PRIMARY KEY (id_documento),

    CONSTRAINT fk_documento_expediente
        FOREIGN KEY (id_expediente)
        REFERENCES expediente(id_expediente)
        ON DELETE RESTRICT,

    CONSTRAINT fk_documento_tipo
        FOREIGN KEY (id_tipo_documento)
        REFERENCES tipo_documento(id_tipo_documento)
        ON DELETE RESTRICT
);

CREATE TABLE actuacion (
    id_actuacion INTEGER GENERATED ALWAYS AS IDENTITY,
    id_expediente INTEGER NOT NULL,
    id_funcionario INTEGER NOT NULL,
    titulo VARCHAR(200) NOT NULL,
    descripcion TEXT,
    fecha_actuacion TIMESTAMP NOT NULL,
    fecha_registro TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_actuacion PRIMARY KEY (id_actuacion),

    CONSTRAINT fk_actuacion_expediente
        FOREIGN KEY (id_expediente)
        REFERENCES expediente(id_expediente)
        ON DELETE RESTRICT,

    CONSTRAINT fk_actuacion_funcionario
        FOREIGN KEY (id_funcionario)
        REFERENCES funcionario(id_funcionario)
        ON DELETE RESTRICT
);

CREATE TABLE historial_estado (
    id_historial INTEGER GENERATED ALWAYS AS IDENTITY,
    id_expediente INTEGER NOT NULL,
    id_estado INTEGER NOT NULL,
    id_funcionario INTEGER,
    fecha_cambio TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    observacion TEXT,

    CONSTRAINT pk_historial_estado PRIMARY KEY (id_historial),

    CONSTRAINT fk_historial_expediente
        FOREIGN KEY (id_expediente)
        REFERENCES expediente(id_expediente)
        ON DELETE RESTRICT,

    CONSTRAINT fk_historial_estado
        FOREIGN KEY (id_estado)
        REFERENCES estado(id_estado)
        ON DELETE RESTRICT,

    CONSTRAINT fk_historial_funcionario
        FOREIGN KEY (id_funcionario)
        REFERENCES funcionario(id_funcionario)
        ON DELETE RESTRICT
);

-----------------------
-------------------------
------------------------------

-- ============================================
-- INDICES ADICIONALES
-- ============================================

-- Busqueda de expedientes por tipo y estado
CREATE INDEX idx_expediente_tipo
ON expediente(id_tipo_caso);

CREATE INDEX idx_expediente_estado
ON expediente(id_estado);

-- Busqueda de personas relacionadas
CREATE INDEX idx_ep_persona
ON expediente_persona(id_persona);

-- Busqueda de asignaciones por funcionario
CREATE INDEX idx_asignacion_funcionario
ON asignacion(id_funcionario);

-- Busqueda de documentos por expediente
CREATE INDEX idx_documento_expediente
ON documento(id_expediente);

-- Busqueda de actuaciones por expediente y fecha
CREATE INDEX idx_actuacion_expediente_fecha
ON actuacion(id_expediente, fecha_actuacion);

-- Consulta del historial cronologico
CREATE INDEX idx_historial_expediente_fecha
ON historial_estado(id_expediente, fecha_cambio DESC);


-- ============================================
-- REGLAS PARA LAS ASIGNACIONES
-- ============================================

-- Un funcionario no puede tener dos asignaciones
-- activas duplicadas en el mismo expediente.
CREATE UNIQUE INDEX uq_asignacion_activa
ON asignacion(id_expediente, id_funcionario)
WHERE fecha_fin IS NULL;

-- Solo puede existir un responsable principal activo
-- por expediente.
CREATE UNIQUE INDEX uq_responsable_activo
ON asignacion(id_expediente)
WHERE es_responsable = TRUE
AND fecha_fin IS NULL;


-- ============================================
-- VALIDAR QUE EL FUNCIONARIO ESTE ACTIVO
-- ============================================

CREATE OR REPLACE FUNCTION validar_funcionario_asignacion()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM funcionario
        WHERE id_funcionario = NEW.id_funcionario
          AND activo = TRUE
    ) THEN
        RAISE EXCEPTION
            'No se puede asignar un funcionario inactivo o inexistente';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validar_funcionario_asignacion
BEFORE INSERT OR UPDATE OF id_funcionario
ON asignacion
FOR EACH ROW
EXECUTE FUNCTION validar_funcionario_asignacion();


-- ============================================
-- ACTUALIZAR EL ESTADO DEL EXPEDIENTE
-- AL REGISTRAR UN CAMBIO EN EL HISTORIAL
-- ============================================

CREATE OR REPLACE FUNCTION actualizar_estado_expediente()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE expediente
    SET id_estado = NEW.id_estado
    WHERE id_expediente = NEW.id_expediente;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_actualizar_estado_expediente
AFTER INSERT ON historial_estado
FOR EACH ROW
EXECUTE FUNCTION actualizar_estado_expediente();

---datos de referencia
-------------------------------
----------------------------
------------------------------

-- Tipos de caso
INSERT INTO tipo_caso (nombre, descripcion) VALUES
('Administrativo', 'Tramites y solicitudes administrativas'),
('Disciplinario', 'Casos relacionados con faltas disciplinarias'),
('Reclamo', 'Reclamos y solicitudes de atencion'),
('Investigacion', 'Casos que requieren investigacion'),
('Incidencia', 'Registro de incidentes o acontecimientos');

-- Estados
INSERT INTO estado (nombre, descripcion, es_final) VALUES
('Abierto', 'Expediente registrado y pendiente de gestion', FALSE),
('En revision', 'Expediente en proceso de evaluacion', FALSE),
('En proceso', 'Expediente en gestion activa', FALSE),
('Observado', 'Expediente que requiere correcciones o informacion', FALSE),
('Cerrado', 'Expediente concluido', TRUE),
('Archivado', 'Expediente almacenado y sin actividad', TRUE);

-- Roles de personas
INSERT INTO rol_persona (nombre, descripcion) VALUES
('Solicitante', 'Persona que inicia el caso'),
('Denunciante', 'Persona que presenta una denuncia'),
('Denunciado', 'Persona señalada en una denuncia'),
('Testigo', 'Persona que aporta informacion'),
('Afectado', 'Persona afectada por el caso'),
('Otro', 'Participante con otro tipo de relacion');

-- Tipos de documentos
INSERT INTO tipo_documento (nombre, descripcion) VALUES
('Solicitud', 'Documento de solicitud'),
('Informe', 'Documento informativo o tecnico'),
('Resolucion', 'Documento que contiene una decision'),
('Notificacion', 'Documento de comunicacion formal'),
('Evidencia', 'Documento o archivo de respaldo'),
('Otro', 'Otro tipo de documento');
