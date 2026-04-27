-- ShopNow Database Schema
CREATE TABLE IF NOT EXISTS products (
    id          SERIAL PRIMARY KEY,
    name        VARCHAR(255) NOT NULL,
    description TEXT,
    price       DECIMAL(10,2) NOT NULL,
    stock       INT DEFAULT 0,
    created_at  TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS orders (
    id           SERIAL PRIMARY KEY,
    product_name VARCHAR(255),
    quantity     INT DEFAULT 1,
    total        DECIMAL(10,2),
    status       VARCHAR(50) DEFAULT 'pending',
    created_at   TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS cart_sessions (
    id         SERIAL PRIMARY KEY,
    session_id VARCHAR(255) UNIQUE,
    data       JSONB,
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Seed products
INSERT INTO products (name, description, price, stock) VALUES
    ('Wireless Headphones', 'Premium sound quality with ANC', 79.99, 50),
    ('Smart Watch',         'Health & fitness tracking',      199.99, 30),
    ('Laptop Stand',        'Ergonomic aluminium design',     39.99, 100),
    ('Mechanical Keyboard', 'Tactile RGB backlit keyboard',   129.99, 25),
    ('USB-C Hub',           '7-in-1 multiport hub',           49.99, 75),
    ('Webcam 4K',           'Ultra HD streaming camera',      89.99, 40)
ON CONFLICT DO NOTHING;
