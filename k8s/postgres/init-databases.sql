-- SPDX-License-Identifier: Apache-2.0
--
-- PostgreSQL Database Initialization for Tazama
--
-- This script creates all required databases for Tazama v3.0.0
-- Replacing the ArangoDB multi-database setup with PostgreSQL
--
-- Based on: https://github.com/tazama-lf/postgres-poc
--
-- Usage:
--   kubectl exec -i postgres-postgresql-0 -n infrastructure -- \
--     psql -U postgres < k8s/postgres/init-databases.sql

\echo 'Creating Tazama Databases...'

-- Create tazama user if not exists
DO
$$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_user WHERE usename = 'tazama') THEN
    CREATE USER tazama WITH PASSWORD 'CHANGE_ME_IN_PRODUCTION';
    \echo 'Created user: tazama'
  ELSE
    \echo 'User tazama already exists'
  END IF;
END
$$;

-- Grant necessary permissions
ALTER USER tazama WITH CREATEDB;

-- ============================================
-- 1. Configuration Database
-- ============================================
\echo 'Creating configuration database...'

-- Drop and recreate if exists (development only!)
-- DROP DATABASE IF EXISTS configuration;

CREATE DATABASE configuration
  WITH OWNER = tazama
  ENCODING = 'UTF8'
  LC_COLLATE = 'en_US.UTF-8'
  LC_CTYPE = 'en_US.UTF-8'
  TEMPLATE = template0;

\c configuration

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE configuration TO tazama;
GRANT ALL ON SCHEMA public TO tazama;

-- Configuration tables
CREATE TABLE IF NOT EXISTS networkMap (
  id SERIAL PRIMARY KEY,
  messages JSONB NOT NULL,
  active BOOLEAN DEFAULT true,
  cfg VARCHAR(255),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS typologyExpression (
  id SERIAL PRIMARY KEY,
  cfg VARCHAR(255),
  id_name VARCHAR(255),
  expression JSONB NOT NULL,
  rules JSONB NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Add indexes
CREATE INDEX idx_networkMap_cfg ON networkMap(cfg);
CREATE INDEX idx_networkMap_active ON networkMap(active);
CREATE INDEX idx_typologyExpression_cfg ON typologyExpression(cfg);

\echo 'Configuration database created'

-- ============================================
-- 2. Transaction History Database
-- ============================================
\c postgres

\echo 'Creating transactionHistory database...'

CREATE DATABASE "transactionHistory"
  WITH OWNER = tazama
  ENCODING = 'UTF8'
  LC_COLLATE = 'en_US.UTF-8'
  LC_CTYPE = 'en_US.UTF-8'
  TEMPLATE = template0;

\c transactionHistory

GRANT ALL PRIVILEGES ON DATABASE "transactionHistory" TO tazama;
GRANT ALL ON SCHEMA public TO tazama;

-- Transaction storage with JSONB
-- Based on postgres-poc notes: store full transaction as JSONB with generated columns
CREATE TABLE IF NOT EXISTS transactions (
  id SERIAL PRIMARY KEY,
  transaction_id VARCHAR(255) UNIQUE NOT NULL,

  -- Full transaction as JSONB
  transaction_data JSONB NOT NULL,

  -- Generated columns for efficient querying (from JSONB)
  amount NUMERIC GENERATED ALWAYS AS ((transaction_data->>'amount')::NUMERIC) STORED,
  transaction_type VARCHAR(50) GENERATED ALWAYS AS (transaction_data->>'transactionType') STORED,
  creditor_id VARCHAR(255) GENERATED ALWAYS AS (transaction_data->'creditor'->>'id') STORED,
  debtor_id VARCHAR(255) GENERATED ALWAYS AS (transaction_data->'debtor'->>'id') STORED,

  -- Note: 'to' and 'from' are SQL reserved words, using sender/receiver instead
  sender_account VARCHAR(255) GENERATED ALWAYS AS (transaction_data->'payer'->>'account') STORED,
  receiver_account VARCHAR(255) GENERATED ALWAYS AS (transaction_data->'payee'->>'account') STORED,

  -- Timestamps
  transaction_timestamp TIMESTAMP GENERATED ALWAYS AS (
    (transaction_data->>'timestamp')::TIMESTAMP
  ) STORED,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for common queries (from postgres-poc performance notes)
CREATE INDEX idx_transactions_id ON transactions(transaction_id);
CREATE INDEX idx_transactions_timestamp ON transactions(transaction_timestamp);
CREATE INDEX idx_transactions_type ON transactions(transaction_type);
CREATE INDEX idx_transactions_creditor ON transactions(creditor_id);
CREATE INDEX idx_transactions_debtor ON transactions(debtor_id);
CREATE INDEX idx_transactions_amount ON transactions(amount);

-- GIN index for JSONB queries
CREATE INDEX idx_transactions_data_gin ON transactions USING GIN(transaction_data);

\echo 'Transaction History database created'

-- ============================================
-- 3. Pseudonyms Database
-- ============================================
\c postgres

\echo 'Creating pseudonyms database...'

CREATE DATABASE pseudonyms
  WITH OWNER = tazama
  ENCODING = 'UTF8'
  LC_COLLATE = 'en_US.UTF-8'
  LC_CTYPE = 'en_US.UTF-8'
  TEMPLATE = template0;

\c pseudonyms

GRANT ALL PRIVILEGES ON DATABASE pseudonyms TO tazama;
GRANT ALL ON SCHEMA public TO tazama;

-- Pseudonym mappings
CREATE TABLE IF NOT EXISTS pseudonymMappings (
  id SERIAL PRIMARY KEY,
  actual_value VARCHAR(255) UNIQUE NOT NULL,
  pseudonym_value VARCHAR(255) UNIQUE NOT NULL,
  entity_type VARCHAR(50) NOT NULL, -- 'account', 'person', etc.
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  expires_at TIMESTAMP
);

-- Indexes
CREATE INDEX idx_pseudonyms_actual ON pseudonymMappings(actual_value);
CREATE INDEX idx_pseudonyms_pseudo ON pseudonymMappings(pseudonym_value);
CREATE INDEX idx_pseudonyms_type ON pseudonymMappings(entity_type);

\echo 'Pseudonyms database created'

-- ============================================
-- 4. Evaluations Database (CADProc results)
-- ============================================
\c postgres

\echo 'Creating evaluations database...'

CREATE DATABASE evaluations
  WITH OWNER = tazama
  ENCODING = 'UTF8'
  LC_COLLATE = 'en_US.UTF-8'
  LC_CTYPE = 'en_US.UTF-8'
  TEMPLATE = template0;

\c evaluations

GRANT ALL PRIVILEGES ON DATABASE evaluations TO tazama;
GRANT ALL ON SCHEMA public TO tazama;

-- Evaluation results
CREATE TABLE IF NOT EXISTS transaction_evaluations (
  id SERIAL PRIMARY KEY,
  transaction_id VARCHAR(255) NOT NULL,
  evaluation_result JSONB NOT NULL,
  typology_id VARCHAR(100),
  rule_id VARCHAR(100),
  score NUMERIC,
  status VARCHAR(50),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes
CREATE INDEX idx_evaluations_transaction ON transaction_evaluations(transaction_id);
CREATE INDEX idx_evaluations_typology ON transaction_evaluations(typology_id);
CREATE INDEX idx_evaluations_rule ON transaction_evaluations(rule_id);
CREATE INDEX idx_evaluations_timestamp ON transaction_evaluations(created_at);

-- GIN index for JSONB
CREATE INDEX idx_evaluations_result_gin ON transaction_evaluations USING GIN(evaluation_result);

\echo 'Evaluations database created'

-- ============================================
-- Summary
-- ============================================
\c postgres

\echo ''
\echo '========================================='
\echo 'Database initialization complete!'
\echo '========================================='
\echo ''
\echo 'Created databases:'
\echo '  - configuration       (network maps, typology expressions)'
\echo '  - transactionHistory  (transaction storage with JSONB)'
\echo '  - pseudonyms          (pseudonym mappings)'
\echo '  - evaluations         (evaluation results)'
\echo ''
\echo 'User: tazama'
\echo ''
\echo 'IMPORTANT: Change the default password!'
\echo '  ALTER USER tazama WITH PASSWORD '\''your-secure-password'\'';'
\echo ''
\echo 'Connection strings:'
\echo '  Configuration:  postgresql://tazama:password@postgres-postgresql.infrastructure.svc:5432/configuration'
\echo '  Transactions:   postgresql://tazama:password@postgres-postgresql.infrastructure.svc:5432/transactionHistory'
\echo '  Pseudonyms:     postgresql://tazama:password@postgres-postgresql.infrastructure.svc:5432/pseudonyms'
\echo '  Evaluations:    postgresql://tazama:password@postgres-postgresql.infrastructure.svc:5432/evaluations'
\echo ''

-- List all databases
\l
