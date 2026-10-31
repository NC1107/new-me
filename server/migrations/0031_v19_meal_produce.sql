-- v19: fruit and vegetables inside logged meals count toward the produce quest. A meal keeps the
-- grams of its produce in three buckets because the caps differ: whole fruit and vegetables are
-- uncapped, while juice and pulses each count at most one serving a day (NHS 5 A Day).
ALTER TABLE meal_logs
    ADD COLUMN produce_g NUMERIC(7, 1) NOT NULL DEFAULT 0 CHECK (produce_g >= 0 AND produce_g <= 10000),
    ADD COLUMN juice_g   NUMERIC(7, 1) NOT NULL DEFAULT 0 CHECK (juice_g >= 0 AND juice_g <= 10000),
    ADD COLUMN pulse_g   NUMERIC(7, 1) NOT NULL DEFAULT 0 CHECK (pulse_g >= 0 AND pulse_g <= 10000);

-- A saved food remembers what its database said it is, so logging it later still counts. Empty
-- means not produce or not known.
ALTER TABLE foods
    ADD COLUMN produce_kind TEXT NOT NULL DEFAULT '' CHECK (produce_kind IN ('', 'fruit', 'vegetable', 'juice', 'pulse'));
