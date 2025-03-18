import pytest
import os
import requests
from unittest.mock import patch, MagicMock
from scripts.verify_security import verify_sonarqube, verify_snyk
from scripts.verify_system import verify_security_config, verify_tools


@pytest.fixture
def mock_env_vars():
    """Фікстура для тестових змінних оточення"""
    os.environ["SONAR_HOST_URL"] = "http://localhost:9000"
    os.environ["SONAR_TOKEN"] = "test-token"
    os.environ["SNYK_TOKEN"] = "test-snyk-token"
    os.environ["GITHUB_TOKEN"] = "test-github-token"
    yield
    del os.environ["SONAR_HOST_URL"]
    del os.environ["SONAR_TOKEN"]
    del os.environ["SNYK_TOKEN"]
    del os.environ["GITHUB_TOKEN"]


@pytest.mark.asyncio
async def test_sonarqube_connection(mock_env_vars):
    """Тест підключення до SonarQube"""
    with patch("requests.get") as mock_get:
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {"version": "9.0", "status": "UP"}
        mock_get.return_value = mock_response

        success, message = verify_sonarqube()
        assert success
        assert "SonarQube 9.0" in message


@pytest.mark.asyncio
async def test_snyk_configuration(mock_env_vars):
    """Тест конфігурації Snyk"""
    with patch("pathlib.Path.exists") as mock_exists:
        mock_exists.return_value = True
        success, errors = verify_snyk()
        assert success
        assert len(errors) == 0


@pytest.mark.asyncio
async def test_security_tools():
    """Тест наявності інструментів безпеки"""
    tools = verify_tools()
    required_tools = {"sonar-scanner", "docker", "python", "pip"}
    installed_tools = {tool["tool"] for tool in tools if tool["installed"]}
    assert required_tools.issubset(installed_tools)


@pytest.mark.asyncio
async def test_security_config(mock_env_vars):
    """Тест конфігурації безпеки"""
    with patch("pathlib.Path.exists") as mock_exists:
        mock_exists.return_value = True
        success, errors = verify_security_config()
        assert success
        assert len(errors) == 0


@pytest.mark.asyncio
async def test_failed_sonarqube_connection():
    """Тест помилки підключення до SonarQube"""
    with patch("requests.get") as mock_get:
        mock_get.side_effect = requests.exceptions.ConnectionError()
        success, message = verify_sonarqube()
        assert not success
        assert "Помилка" in message


@pytest.mark.asyncio
async def test_invalid_security_config():
    """Тест неправильної конфігурації безпеки"""
    with patch("pathlib.Path.exists") as mock_exists:
        mock_exists.return_value = False
        success, errors = verify_security_config()
        assert not success
        assert len(errors) > 0
