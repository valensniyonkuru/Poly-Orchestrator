import os
import requests
from flask import Flask, render_template, jsonify

app = Flask(__name__)

BACKEND_URL = os.environ.get("BACKEND_URL", "http://backend:5000")

@app.route("/")
def index():
    return render_template("index.html")

@app.route("/health")
def health():
    return jsonify({"status": "healthy", "service": "frontend"})

@app.route("/api/products")
def products():
    try:
        resp = requests.get(f"{BACKEND_URL}/products", timeout=5)
        return jsonify(resp.json())
    except Exception as e:
        return jsonify({"error": str(e)}), 503

@app.route("/api/cart")
def cart():
    try:
        resp = requests.get(f"{BACKEND_URL}/cart", timeout=5)
        return jsonify(resp.json())
    except Exception as e:
        return jsonify({"error": str(e)}), 503

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
