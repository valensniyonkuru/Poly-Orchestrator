"""Unit tests for GET /health."""


class TestHealthStatus:
    def test_returns_200(self, client, mock_redis, mock_db):
        response = client.get("/health")
        assert response.status_code == 200

    def test_response_is_json(self, client, mock_redis, mock_db):
        response = client.get("/health")
        assert response.content_type == "application/json"

    def test_contains_status_healthy(self, client, mock_redis, mock_db):
        data = client.get("/health").get_json()
        assert data["status"] == "healthy"

    def test_contains_service_name(self, client, mock_redis, mock_db):
        data = client.get("/health").get_json()
        assert data["service"] == "backend"

    def test_contains_timestamp(self, client, mock_redis, mock_db):
        data = client.get("/health").get_json()
        assert "timestamp" in data


class TestHealthDependencies:
    def test_redis_connected_when_available(self, client, mock_redis, mock_db):
        data = client.get("/health").get_json()
        assert data["redis"] == "connected"

    def test_postgres_connected_when_available(self, client, mock_redis, mock_db):
        data = client.get("/health").get_json()
        assert data["postgres"] == "connected"

    def test_redis_disconnected_when_unavailable(self, client, mocker, mock_db):
        mocker.patch("app.get_redis", return_value=None)
        data = client.get("/health").get_json()
        assert data["redis"] == "disconnected"

    def test_postgres_disconnected_when_unavailable(self, client, mock_redis, mocker):
        mocker.patch("app.get_db", return_value=None)
        data = client.get("/health").get_json()
        assert data["postgres"] == "disconnected"

    def test_still_returns_200_when_both_dependencies_down(self, client, mocker):
        mocker.patch("app.get_redis", return_value=None)
        mocker.patch("app.get_db", return_value=None)
        response = client.get("/health")
        assert response.status_code == 200
        data = response.get_json()
        assert data["status"] == "healthy"
        assert data["redis"] == "disconnected"
        assert data["postgres"] == "disconnected"
