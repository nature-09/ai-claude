CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE departments (
    id          BIGSERIAL PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,
    parent_id   BIGINT REFERENCES departments (id) ON DELETE SET NULL,
    sort_order  INT NOT NULL DEFAULT 0
);

CREATE TABLE users (
    id              BIGSERIAL PRIMARY KEY,
    username        VARCHAR(50)  NOT NULL UNIQUE,
    password_hash   VARCHAR(100) NOT NULL,
    name            VARCHAR(50)  NOT NULL,
    email           VARCHAR(100),
    phone           VARCHAR(30),
    position        VARCHAR(50),
    department_id   BIGINT REFERENCES departments (id) ON DELETE SET NULL,
    role            VARCHAR(10)  NOT NULL DEFAULT 'USER',
    status_message  VARCHAR(100),
    active          BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX idx_users_department ON users (department_id);
CREATE INDEX idx_users_name_trgm ON users USING gin (name gin_trgm_ops);

CREATE TABLE chat_rooms (
    id               BIGSERIAL PRIMARY KEY,
    type             VARCHAR(10)  NOT NULL,
    name             VARCHAR(100),
    direct_key       VARCHAR(50) UNIQUE,
    created_by       BIGINT REFERENCES users (id),
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    last_message_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE room_members (
    room_id               BIGINT NOT NULL REFERENCES chat_rooms (id) ON DELETE CASCADE,
    user_id               BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    last_read_message_id  BIGINT NOT NULL DEFAULT 0,
    joined_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (room_id, user_id)
);
CREATE INDEX idx_room_members_user ON room_members (user_id);

CREATE TABLE attachments (
    id             BIGSERIAL PRIMARY KEY,
    room_id        BIGINT NOT NULL REFERENCES chat_rooms (id) ON DELETE CASCADE,
    uploader_id    BIGINT NOT NULL REFERENCES users (id),
    original_name  VARCHAR(255) NOT NULL,
    content_type   VARCHAR(100) NOT NULL,
    size           BIGINT NOT NULL,
    storage_key    VARCHAR(255) NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE messages (
    id             BIGSERIAL PRIMARY KEY,
    room_id        BIGINT NOT NULL REFERENCES chat_rooms (id) ON DELETE CASCADE,
    sender_id      BIGINT REFERENCES users (id),
    type           VARCHAR(10) NOT NULL,
    content        TEXT,
    attachment_id  BIGINT REFERENCES attachments (id),
    deleted        BOOLEAN NOT NULL DEFAULT FALSE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_messages_room_id ON messages (room_id, id DESC);
CREATE INDEX idx_messages_content_trgm ON messages USING gin (content gin_trgm_ops);
