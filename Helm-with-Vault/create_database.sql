-- Создание пользователя
CREATE USER vault WITH PASSWORD 'keiShee4';

-- Создание базы данных
CREATE DATABASE vault OWNER vault;

-- Подключение к базе данных
\connect vault;

-- Создание таблиц
CREATE TABLE vault_kv_store (
  parent_path TEXT COLLATE "C" NOT NULL,
  path        TEXT COLLATE "C",
  key         TEXT COLLATE "C",
  value       BYTEA,
  CONSTRAINT pkey PRIMARY KEY (path, key)
);

CREATE INDEX parent_path_idx ON vault_kv_store (parent_path);

CREATE TABLE vault_ha_locks (
  ha_key      TEXT COLLATE "C" NOT NULL,
  ha_identity TEXT COLLATE "C" NOT NULL,
  ha_value    TEXT COLLATE "C",
  valid_until TIMESTAMP WITH TIME ZONE NOT NULL,
  CONSTRAINT ha_key PRIMARY KEY (ha_key)
);

-- Предоставление прав доступа
GRANT ALL PRIVILEGES ON DATABASE vault TO vault;
GRANT ALL PRIVILEGES ON TABLE vault_kv_store TO vault;
GRANT ALL PRIVILEGES ON TABLE vault_ha_locks TO vault;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO vault;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO vault;
