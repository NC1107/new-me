-- The household food library: foods saved once so the same food always has the same numbers.
-- Nutrients are per serving; alternate servings carry only a label and a weight and are
-- converted through the primary serving.
CREATE TABLE foods (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name          TEXT        NOT NULL CHECK (char_length(name) BETWEEN 1 AND 80),
    brand         TEXT        NOT NULL DEFAULT '' CHECK (char_length(brand) <= 40),
    serving_text  TEXT        NOT NULL CHECK (char_length(serving_text) BETWEEN 1 AND 60),
    serving_grams NUMERIC(8,1) NOT NULL DEFAULT 0 CHECK (serving_grams >= 0 AND serving_grams <= 5000),
    kcal          INTEGER     NOT NULL CHECK (kcal BETWEEN 0 AND 10000),
    protein_g     NUMERIC(6,1) NOT NULL DEFAULT 0 CHECK (protein_g BETWEEN 0 AND 5000),
    carbs_g       NUMERIC(6,1) NOT NULL DEFAULT 0 CHECK (carbs_g BETWEEN 0 AND 5000),
    fat_g         NUMERIC(6,1) NOT NULL DEFAULT 0 CHECK (fat_g BETWEEN 0 AND 5000),
    fiber_g       NUMERIC(6,1) NOT NULL DEFAULT 0 CHECK (fiber_g BETWEEN 0 AND 5000),
    source        TEXT        NOT NULL CHECK (source IN ('usda', 'openfoodfacts', 'manual', 'estimated')),
    source_id     TEXT        NOT NULL DEFAULT '' CHECK (char_length(source_id) <= 40),
    alt_servings  JSONB       NOT NULL DEFAULT '[]',
    created_by    BIGINT      REFERENCES users (id) ON DELETE SET NULL,
    use_count     INTEGER     NOT NULL DEFAULT 0 CHECK (use_count >= 0),
    last_used_at  TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- A database food is saved once; manual and estimated foods have no source id and may repeat.
CREATE UNIQUE INDEX foods_source_key ON foods (source, source_id) WHERE source_id <> '';
