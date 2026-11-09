-- ============================================================================
-- Init script for PostgreSQL (runs on first container startup)
-- ============================================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enable PostGIS for geo queries (if needed)
-- CREATE EXTENSION IF NOT EXISTS postgis;

-- Create enum types
DO $$ BEGIN
    CREATE TYPE verification_status AS ENUM ('pending', 'verified', 'conditional');
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE pick_type AS ENUM ('private', 'public');
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE edibility AS ENUM (
        'edible',
        'conditionally_edible',
        'inedible',
        'poisonous',
        'deadly_poisonous'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

-- Create tables (Supabase will manage via migrations, this is just for local dev)
-- Migrations should be run via Supabase CLI in production