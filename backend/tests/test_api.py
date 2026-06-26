"""Integration tests for the main API routes.

All tests use the Flask test client with Redis and Postgres mocked out,
so no real AWS infrastructure is required.
"""
import json


# ── Products ──────────────────────────────────────────────────────────────────

class TestProducts:
    def test_list_products_returns_200(self, client, mock_redis):
        response = client.get("/products")
        assert response.status_code == 200

    def test_list_products_returns_all_six_items(self, client, mock_redis):
        data = client.get("/products").get_json()
        assert "products" in data
        assert len(data["products"]) == 6

    def test_list_products_source_is_db_on_cache_miss(self, client, mock_redis):
        mock_redis.get.return_value = None
        data = client.get("/products").get_json()
        assert data["source"] == "db"

    def test_list_products_source_is_cache_on_cache_hit(self, client, mock_redis):
        from app import PRODUCTS
        mock_redis.get.return_value = json.dumps(PRODUCTS)
        data = client.get("/products").get_json()
        assert data["source"] == "cache"

    def test_list_products_writes_to_cache_on_miss(self, client, mock_redis):
        mock_redis.get.return_value = None
        client.get("/products")
        mock_redis.setex.assert_called_once()

    def test_product_detail_returns_200(self, client):
        response = client.get("/products/1")
        assert response.status_code == 200

    def test_product_detail_returns_correct_product(self, client):
        data = client.get("/products/1").get_json()
        assert data["id"] == 1
        assert data["name"] == "Wireless Headphones"
        assert data["price"] == 79.99

    def test_product_detail_returns_404_for_unknown_id(self, client):
        response = client.get("/products/999")
        assert response.status_code == 404

    def test_product_detail_404_body_contains_error_key(self, client):
        data = client.get("/products/999").get_json()
        assert "error" in data


# ── Cart ──────────────────────────────────────────────────────────────────────

class TestCart:
    def test_add_to_cart_with_valid_data_returns_201(self, client, mock_redis):
        response = client.post(
            "/cart/add",
            json={"product_id": 1, "name": "Wireless Headphones", "price": 79.99},
        )
        assert response.status_code == 201

    def test_add_to_cart_response_contains_item(self, client, mock_redis):
        payload = {"product_id": 1, "name": "Wireless Headphones", "price": 79.99}
        data = client.post("/cart/add", json=payload).get_json()
        assert data["message"] == "Added to cart"
        assert data["item"]["product_id"] == 1

    def test_add_to_cart_with_empty_body_returns_400(self, client, mock_redis):
        response = client.post("/cart/add", json={})
        assert response.status_code == 400

    def test_add_to_cart_with_no_json_returns_400(self, client, mock_redis):
        response = client.post("/cart/add", content_type="application/json")
        assert response.status_code == 400

    def test_add_to_cart_400_body_contains_error_key(self, client, mock_redis):
        data = client.post("/cart/add", json={}).get_json()
        assert "error" in data

    def test_add_to_cart_pushes_to_redis(self, client, mock_redis):
        client.post(
            "/cart/add",
            json={"product_id": 2, "name": "Smart Watch", "price": 199.99},
        )
        mock_redis.lpush.assert_called_once()

    def test_add_to_cart_sets_expiry_on_cart_key(self, client, mock_redis):
        client.post(
            "/cart/add",
            json={"product_id": 2, "name": "Smart Watch", "price": 199.99},
        )
        mock_redis.expire.assert_called_once_with("cart:default", 3600)

    def test_add_to_cart_returns_503_when_redis_unavailable(self, client, mocker):
        mocker.patch("app.get_redis", return_value=None)
        response = client.post(
            "/cart/add",
            json={"product_id": 1, "name": "Test", "price": 9.99},
        )
        assert response.status_code == 503

    def test_get_cart_returns_200(self, client, mock_redis):
        response = client.get("/cart")
        assert response.status_code == 200

    def test_get_cart_returns_items_and_count(self, client, mock_redis):
        mock_redis.lrange.return_value = []
        data = client.get("/cart").get_json()
        assert "items" in data
        assert "count" in data

    def test_get_cart_empty_by_default(self, client, mock_redis):
        data = client.get("/cart").get_json()
        assert data["items"] == []
        assert data["count"] == 0

    def test_get_cart_returns_items_when_present(self, client, mock_redis):
        item = {"product_id": 3, "name": "Laptop Stand", "price": 39.99}
        mock_redis.lrange.return_value = [json.dumps(item)]
        data = client.get("/cart").get_json()
        assert len(data["items"]) == 1
        assert data["items"][0]["product_id"] == 3

    def test_get_cart_reports_redis_unavailable(self, client, mocker):
        mocker.patch("app.get_redis", return_value=None)
        data = client.get("/cart").get_json()
        assert data["redis"] == "unavailable"
        assert data["items"] == []


# ── Orders ────────────────────────────────────────────────────────────────────

class TestOrders:
    def test_create_order_returns_201(self, client, mock_db):
        response = client.post(
            "/orders",
            json={"product_name": "Wireless Headphones", "quantity": 1, "total": 79.99},
        )
        assert response.status_code == 201

    def test_create_order_response_contains_order_id(self, client, mock_db):
        data = client.post(
            "/orders",
            json={"product_name": "Wireless Headphones", "quantity": 1, "total": 79.99},
        ).get_json()
        assert "order_id" in data
        assert data["order_id"] == 1

    def test_create_order_response_status_is_created(self, client, mock_db):
        data = client.post(
            "/orders",
            json={"product_name": "Wireless Headphones", "quantity": 1, "total": 79.99},
        ).get_json()
        assert data["status"] == "created"

    def test_create_order_commits_to_db(self, client, mock_db):
        mock_conn, _ = mock_db
        client.post(
            "/orders",
            json={"product_name": "Wireless Headphones", "quantity": 1, "total": 79.99},
        )
        mock_conn.commit.assert_called_once()

    def test_create_order_returns_503_when_db_unavailable(self, client, mocker):
        mocker.patch("app.get_db", return_value=None)
        response = client.post(
            "/orders",
            json={"product_name": "Test", "quantity": 1, "total": 9.99},
        )
        assert response.status_code == 503

    def test_list_orders_returns_200(self, client, mock_db):
        response = client.get("/orders")
        assert response.status_code == 200

    def test_list_orders_returns_orders_key(self, client, mock_db):
        data = client.get("/orders").get_json()
        assert "orders" in data

    def test_list_orders_empty_when_no_orders_exist(self, client, mock_db):
        data = client.get("/orders").get_json()
        assert data["orders"] == []

    def test_list_orders_returns_503_when_db_unavailable(self, client, mocker):
        mocker.patch("app.get_db", return_value=None)
        response = client.get("/orders")
        assert response.status_code == 503
