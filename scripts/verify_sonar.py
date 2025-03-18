import os
import sys
import requests
from urllib.parse import urljoin


def verify_sonar():
    """Перевірка підключення до SonarQube"""
    try:
        # Перевіряємо наявність конфігурації
        config_file = os.path.expanduser("~/.sonar/sonar-scanner.properties")
        if not os.path.exists(config_file):
            print("❌ Не знайдено конфігурацію SonarQube")
            return False

        # Перевіряємо з'єднання
        host = "http://localhost:9000"
        token = "ae5fe5168d12c610c7b94cdb641b53e1c54c0654"

        response = requests.get(
            f"{host}/api/system/status", auth=(token, ""), timeout=10, verify=True
        )

        if response.status_code != 200:
            print(f"❌ Помилка підключення до SonarQube: {response.status_code}")
            return False

        # Перевіряємо наявність проекту
        project_key = "predator-analytics"
        project_response = requests.get(
            f"{host}/api/projects/search?projects={project_key}", auth=(token, ""), timeout=10
        )

        if project_response.status_code != 200:
            print("❌ Помилка перевірки проекту")
            return False

        projects = project_response.json().get("components", [])
        if not any(p["key"] == project_key for p in projects):
            print(f"❌ Проект {project_key} не знайдено")
            return False

        print("✅ Підключення до SonarQube успішне")
        return True

    except Exception as e:
        print(f"❌ Помилка: {str(e)}")
        return False


def create_project(host, token, project):
    """Створення проекту в SonarQube"""
    try:
        create_url = urljoin(host, "api/projects/create")
        response = requests.post(
            create_url, auth=(token, ""), params={"name": project, "project": project}
        )

        if response.status_code == 200:
            print(f"✅ Проект {project} створено")
            return True
        else:
            print(f"❌ Помилка створення проекту: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Помилка при створенні проекту: {str(e)}")
        return False


if __name__ == "__main__":
    if not verify_sonar():
        sys.exit(1)
