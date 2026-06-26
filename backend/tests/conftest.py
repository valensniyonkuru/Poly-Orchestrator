import os
import json
import pytest

# Must be set before app.py is imported — the module exits at startup if absent.
os.environ.setdefault("DB_PASSWORD", "testpassword")

from app import app as flask_app  # noqa: E402  (import after env setup is intentional)


@pytest.fixture
def app():
    flask_app.config.update({"TESTING": True})
    yield flask_app


@pytest.fixture
def client(app):
    return app.test_client()


@pytest.fixture
def mock_redis(mocker):
    """Patches app.get_redis with a MagicMock that simulates an available Redis.

    Default behaviour:
      - ping()      → True  (connection succeeds)
      - get()       → None  (cache miss)
      - lrange()    → []    (empty cart)
    Tests that need different behaviour can override individual attributes.
    """
    mock_r = mocker.MagicMock()
    mock_r.ping.return_value = True
    mock_r.get.return_value = None
    mock_r.lrange.return_value = []
    mocker.patch("app.get_redis", return_value=mock_r)
    return mock_r


@pytest.fixture
def mock_db(mocker):
    """Patches app.get_db with a MagicMock that simulates an available Postgres.

    Default behaviour:
      - cursor()        → mock cursor
      - fetchone()      → (1,)   (e.g. RETURNING id from INSERT)
      - fetchall()      → []     (empty result set for SELECT)
    Returns (mock_conn, mock_cur) for tests that need to assert on DB calls.
    """
    mock_cur = mocker.MagicMock()
    mock_cur.fetchone.return_value = (1,)
    mock_cur.fetchall.return_value = []

    mock_conn = mocker.MagicMock()
    mock_conn.cursor.return_value = mock_cur

    mocker.patch("app.get_db", return_value=mock_conn)
    return mock_conn, mock_cur
