import os
import sys
import json
import redis
import psycopg2
from flask import Flask, jsonify, request
from datetime import datetime, timezone

app = Flask(__name__)

# Redis connection
REDIS_HOST = os.environ.get("REDIS_HOST", "localhost")
REDIS_PORT = int(os.environ.get("REDIS_PORT", 6379))

# Postgres connection
DB_HOST = os.environ.get("DB_HOST", "postgres")
DB_NAME = os.environ.get("DB_NAME", "shopnow")
DB_USER = os.environ.get("DB_USER", "shopnow")
DB_PASSWORD = os.environ.get("DB_PASSWORD")
if not DB_PASSWORD:
    print("ERROR: DB_PASSWORD environment variable is not set", file=sys.stderr)
    sys.exit(1)

PRODUCTS = [
    {"id": 1, "name": "Wireless Headphones", "price": 79.99, "description": "Premium sound quality", "stock": 50},
    {"id": 2, "name": "Smart Watch",         "price": 199.99, "description": "Health & fitness tracking", "stock": 30},
    {"id": 3, "name": "Laptop Stand",        "price": 39.99, "description": "Ergonomic aluminium stand", "stock": 100},
    {"id": 4, "name": "Mechanical Keyboard", "price": 129.99, "description": "Tactile RGB keyboard", "stock": 25},
    {"id": 5, "name": "USB-C Hub",           "price": 49.99, "description": "7-in-1 multiport hub", "stock": 75},
    {"id": 6, "name": "Webcam 4K",           "price": 89.99, "description": "Ultra HD streaming cam", "stock": 40},
]

def get_redis():
    try:
        r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True, socket_timeout=3)
        r.ping()
        return r
    except Exception:
        return None

def get_db():
    try:
        conn = psycopg2.connect(host=DB_HOST, dbname=DB_NAME, user=DB_USER, password=DB_PASSWORD, connect_timeout=3)
        return conn
    except Exception:
        return None

def init_db():
    conn = get_db()
    if not conn:
        return
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS orders (
            id SERIAL PRIMARY KEY,
            product_name VARCHAR(255),
            quantity INT,
            total DECIMAL(10,2),
            created_at TIMESTAMP DEFAULT NOW()
        )
    """)
    conn.commit()
    cur.close()
    conn.close()

@app.route("/health")
def health():
    redis_ok = get_redis() is not None
    db_ok = get_db() is not None
    return jsonify({
        "status": "healthy",
        "service": "backend",
        "redis": "connected" if redis_ok else "disconnected",
        "postgres": "connected" if db_ok else "disconnected",
        "timestamp": datetime.now(timezone.utc).isoformat()
    })

@app.route("/products")
def products():
    r = get_redis()
    cache_key = "products:all"
    if r:
        cached = r.get(cache_key)
        if cached:
            return jsonify({"products": json.loads(cached), "source": "cache"})
    result = {"products": PRODUCTS, "source": "db"}
    if r:
        r.setex(cache_key, 300, json.dumps(PRODUCTS))
    return jsonify(result)

@app.route("/products/<int:product_id>")
def product_detail(product_id):
    product = next((p for p in PRODUCTS if p["id"] == product_id), None)
    if not product:
        return jsonify({"error": "Product not found"}), 404
    return jsonify(product)

@app.route("/cart")
def cart():
    r = get_redis()
    if not r:
        return jsonify({"items": [], "redis": "unavailable"})
    items = r.lrange("cart:default", 0, -1)
    return jsonify({"items": [json.loads(i) for i in items], "count": len(items)})

@app.route("/cart/add", methods=["POST"])
def add_to_cart():
    data = request.get_json(silent=True)
    if not data or "product_id" not in data:
        return jsonify({"error": "product_id is required"}), 400
    r = get_redis()
    if not r:
        return jsonify({"error": "Cache unavailable"}), 503
    r.lpush("cart:default", json.dumps(data))
    r.expire("cart:default", 3600)
    return jsonify({"message": "Added to cart", "item": data}), 201

@app.route("/orders", methods=["POST"])
def create_order():
    data = request.get_json()
    conn = get_db()
    if not conn:
        return jsonify({"error": "Database unavailable"}), 503
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO orders (product_name, quantity, total) VALUES (%s, %s, %s) RETURNING id",
        (data.get("product_name"), data.get("quantity", 1), data.get("total", 0))
    )
    order_id = cur.fetchone()[0]
    conn.commit()
    cur.close()
    conn.close()
    return jsonify({"order_id": order_id, "status": "created"}), 201

@app.route("/orders")
def list_orders():
    conn = get_db()
    if not conn:
        return jsonify({"error": "Database unavailable"}), 503
    cur = conn.cursor()
    cur.execute("SELECT id, product_name, quantity, total, created_at FROM orders ORDER BY created_at DESC LIMIT 20")
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return jsonify({"orders": [
        {"id": r[0], "product_name": r[1], "quantity": r[2], "total": float(r[3]), "created_at": r[4].isoformat()}
        for r in rows
    ]})

if __name__ == "__main__":
    init_db()
    app.run(host="0.0.0.0", port=5000, debug=False)
