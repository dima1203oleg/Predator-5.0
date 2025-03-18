import os
import sys
import requests
import subprocess
from pathlib import Path


def setup_sonar_connection():
    """Налаштування підключення до SonarQube"""
    print("🔄 Налаштування підключення до SonarQube...")

    # Перевіряємо наявність змінних оточення
    host = os.getenv("SONAR_HOST_URL")
    token = os.getenv("SONAR_TOKEN")

    if not host:
        host = input("Введіть URL SonarQube сервера (наприклад, http://localhost:9000): ")
        os.environ["SONAR_HOST_URL"] = host

    if not token:
        token = input("Введіть токен доступу SonarQube: ")
        os.environ["SONAR_TOKEN"] = token

    try:
        # Тестуємо підключення
        response = requests.get(
            f"{host}/api/system/status", auth=(token, ""), timeout=10, verify=True
        )

        if response.status_code == 200:
            print("✅ Підключення до SonarQube успішне")

            # Зберігаємо налаштування
            save_config(host, token)

            # Налаштовуємо проект
            setup_project()
            return True
        else:
            print(f"❌ Помилка підключення: {response.status_code}")
            return False

    except Exception as e:
        print(f"❌ Помилка: {str(e)}")
        return False


def save_config(host: str, token: str):
    """Зберігання налаштувань"""
    config_dir = Path.home() / ".sonar"
    config_dir.mkdir(exist_ok=True)

    config_file = config_dir / "config"
    with open(config_file, "w") as f:
        f.write(f"sonar.host.url={host}\n")
        f.write(f"sonar.token={token}\n")

    print("✅ Налаштування збережено")


def setup_project():
    """Налаштування проекту"""
    try:
        # Створюємо файл налаштувань проекту якщо його немає
        if not Path("sonar-project.properties").exists():
            with open("sonar-project.properties", "w") as f:
                f.write(
                    """
sonar.projectKey=predator-analytics
sonar.projectName=Predator Analytics
sonar.sources=predator_analytics
sonar.tests=tests
sonar.python.coverage.reportPaths=coverage.xml
sonar.python.version=3.9
                """.strip()
                )

        # Запускаємо сканування
        result = subprocess.run(["sonar-scanner"], capture_output=True, text=True)

        if result.returncode == 0:
            print("✅ Проект успішно налаштовано")
        else:
            print(f"❌ Помилка при скануванні: {result.stderr}")

    except Exception as e:
        print(f"❌ Помилка при налаштуванні проекту: {str(e)}")


if __name__ == "__main__":
    setup_sonar_connection()
