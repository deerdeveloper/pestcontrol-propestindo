-- Skema awal MVP fase 1: pengguna, data master, kunjungan, dan laporan.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ===== Pengguna & pelanggan =====
CREATE TABLE customers (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name          TEXT NOT NULL,
    tax_id        TEXT,
    billing_address TEXT,
    active        BOOLEAN NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE users (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email         TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    name          TEXT NOT NULL,
    phone         TEXT,
    role          TEXT NOT NULL CHECK (role IN ('super_admin','admin','supervisor','technician','customer')),
    technician_code TEXT UNIQUE,
    customer_id   UUID REFERENCES customers(id) ON DELETE CASCADE,
    active        BOOLEAN NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK ((role = 'customer') = (customer_id IS NOT NULL))
);

-- ===== Data master =====
CREATE TABLE building_types (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name          TEXT NOT NULL UNIQUE,
    default_areas TEXT[] NOT NULL DEFAULT '{}'
);

CREATE TABLE sites (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id   UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    building_type_id UUID REFERENCES building_types(id),
    name          TEXT NOT NULL,
    address       TEXT NOT NULL,
    latitude      DOUBLE PRECISION,
    longitude     DOUBLE PRECISION,
    active        BOOLEAN NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ON sites(customer_id);

CREATE TABLE site_contacts (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    site_id       UUID NOT NULL REFERENCES sites(id) ON DELETE CASCADE,
    name          TEXT NOT NULL,
    position      TEXT,
    phone         TEXT,
    email         TEXT,
    is_primary    BOOLEAN NOT NULL DEFAULT FALSE
);
CREATE INDEX ON site_contacts(site_id);

CREATE TABLE areas (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    site_id       UUID NOT NULL REFERENCES sites(id) ON DELETE CASCADE,
    name          TEXT NOT NULL,
    zone          TEXT NOT NULL DEFAULT 'internal' CHECK (zone IN ('internal','external')),
    active        BOOLEAN NOT NULL DEFAULT TRUE,
    UNIQUE (site_id, name)
);

CREATE TABLE pest_types (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name_id       TEXT NOT NULL UNIQUE,
    name_en       TEXT NOT NULL,
    pest_group    TEXT NOT NULL,
    icon          TEXT,
    active        BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE treatment_methods (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name_id       TEXT NOT NULL UNIQUE,
    name_en       TEXT NOT NULL,
    active        BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE chemicals (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trade_name    TEXT NOT NULL,
    active_ingredient TEXT NOT NULL,
    chemical_class TEXT,
    registration_no TEXT,
    unit          TEXT NOT NULL DEFAULT 'ml',
    active        BOOLEAN NOT NULL DEFAULT TRUE,
    UNIQUE (trade_name, active_ingredient)
);

CREATE TABLE chemical_doses (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chemical_id   UUID NOT NULL REFERENCES chemicals(id) ON DELETE CASCADE,
    method_id     UUID REFERENCES treatment_methods(id) ON DELETE CASCADE,
    dose_text     TEXT NOT NULL
);

CREATE TABLE equipment_types (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name          TEXT NOT NULL UNIQUE,
    code_prefix   TEXT NOT NULL UNIQUE
);

CREATE TABLE stations (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    site_id       UUID NOT NULL REFERENCES sites(id) ON DELETE CASCADE,
    area_id       UUID REFERENCES areas(id) ON DELETE SET NULL,
    equipment_type_id UUID NOT NULL REFERENCES equipment_types(id),
    code          TEXT NOT NULL,
    qr_value      TEXT NOT NULL UNIQUE DEFAULT encode(gen_random_bytes(9), 'hex'),
    active        BOOLEAN NOT NULL DEFAULT TRUE,
    UNIQUE (site_id, code)
);

-- ===== Kunjungan & laporan =====
CREATE TABLE visits (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    site_id       UUID NOT NULL REFERENCES sites(id),
    technician_id UUID REFERENCES users(id),
    visit_type    TEXT NOT NULL CHECK (visit_type IN ('routine_monthly','routine_biweekly','emergency','initial_inspection')),
    scheduled_date DATE NOT NULL,
    status        TEXT NOT NULL DEFAULT 'scheduled'
                  CHECK (status IN ('scheduled','in_progress','pending_review','revision','published','cancelled')),
    notes         TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ON visits(technician_id, scheduled_date);
CREATE INDEX ON visits(site_id, scheduled_date);

CREATE SEQUENCE report_number_seq;

CREATE TABLE visit_reports (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    visit_id      UUID NOT NULL UNIQUE REFERENCES visits(id) ON DELETE CASCADE,
    report_no     TEXT UNIQUE,
    started_at    TIMESTAMPTZ,
    finished_at   TIMESTAMPTZ,
    checkin_lat   DOUBLE PRECISION,
    checkin_lng   DOUBLE PRECISION,
    pic_name      TEXT,
    general_notes TEXT,
    review_notes  TEXT,
    submitted_at  TIMESTAMPTZ,
    published_at  TIMESTAMPTZ,
    published_by  UUID REFERENCES users(id),
    pdf_path      TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE report_findings (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id     UUID NOT NULL REFERENCES visit_reports(id) ON DELETE CASCADE,
    pest_type_id  UUID NOT NULL REFERENCES pest_types(id),
    area_id       UUID REFERENCES areas(id),
    area_text     TEXT,
    level         TEXT NOT NULL CHECK (level IN ('none','low','medium','high')),
    is_active     BOOLEAN NOT NULL DEFAULT TRUE,
    remarks       TEXT,
    sort_order    INT NOT NULL DEFAULT 0
);

CREATE TABLE report_treatments (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id     UUID NOT NULL REFERENCES visit_reports(id) ON DELETE CASCADE,
    method_id     UUID NOT NULL REFERENCES treatment_methods(id),
    area_id       UUID REFERENCES areas(id),
    area_text     TEXT,
    chemical_id   UUID REFERENCES chemicals(id),
    dose_text     TEXT,
    quantity_used TEXT,
    equipment     TEXT,
    sort_order    INT NOT NULL DEFAULT 0
);

CREATE TABLE report_recommendations (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id     UUID NOT NULL REFERENCES visit_reports(id) ON DELETE CASCADE,
    category      TEXT NOT NULL CHECK (category IN ('exclusion','sanitation','storage','habitual')),
    risk_finding  TEXT NOT NULL,
    recommendation TEXT NOT NULL,
    customer_status TEXT NOT NULL DEFAULT 'open' CHECK (customer_status IN ('open','done')),
    customer_note TEXT,
    sort_order    INT NOT NULL DEFAULT 0
);

CREATE TABLE report_station_checks (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id     UUID NOT NULL REFERENCES visit_reports(id) ON DELETE CASCADE,
    station_id    UUID NOT NULL REFERENCES stations(id),
    status        TEXT NOT NULL CHECK (status IN ('ok','check','replace')),
    bait_consumption TEXT NOT NULL DEFAULT 'none' CHECK (bait_consumption IN ('none','partial','total')),
    finding       TEXT,
    UNIQUE (report_id, station_id)
);

CREATE TABLE attachments (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id     UUID NOT NULL REFERENCES visit_reports(id) ON DELETE CASCADE,
    owner_type    TEXT NOT NULL CHECK (owner_type IN ('report','finding','recommendation')),
    owner_id      UUID,
    file_path     TEXT NOT NULL,
    content_type  TEXT NOT NULL,
    caption       TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ON attachments(report_id);

CREATE TABLE signatures (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id     UUID NOT NULL REFERENCES visit_reports(id) ON DELETE CASCADE,
    signer_role   TEXT NOT NULL CHECK (signer_role IN ('technician','pic')),
    signer_name   TEXT NOT NULL,
    file_path     TEXT NOT NULL,
    signed_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (report_id, signer_role)
);

CREATE TABLE audit_logs (
    id            BIGSERIAL PRIMARY KEY,
    user_id       UUID REFERENCES users(id),
    action        TEXT NOT NULL,
    entity        TEXT NOT NULL,
    entity_id     UUID,
    detail        JSONB,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
