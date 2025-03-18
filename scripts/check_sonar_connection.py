import os
import sys
import requests
from urllib.parse import urljoin
import json


def check_sonar_connection():
    """Перевірка підключення до SonarQube"""
    host_url = os.getenv("SONAR_HOST_URL")
    token = os.getenv("SONAR_TOKEN")
    project_key = "predator-analytics"

    if not host_url or not token:
        print("❌ Не налаштовані SONAR_HOST_URL або SONAR_TOKEN")
        return False

    try:
        # Перевіряємо статус сервера
        status_response = requests.get(
            urljoin(host_url, "api/system/status"), auth=(token, ""), timeout=5
        )

        if status_response.status_code != 200:
            print(f"❌ Помилка підключення до сервера: {status_response.status_code}")
            return False

        status = status_response.json()
        print(f"✅ SonarQube сервер доступний (версія: {status.get('version', 'unknown')})")

        # Перевіряємо доступ до проекту
        project_response = requests.get(
            urljoin(host_url, f"api/projects/search?projects={project_key}"),
            auth=(token, ""),
            timeout=5,
        )

        if project_response.status_code == 200:
            projects = project_response.json().get("components", [])
            if any(p["key"] == project_key for p in projects):
                print(f"✅ Проект {project_key} знайдено")
            else:
                print(f"⚠️ Проект {project_key} не знайдено. Буде створено автоматично")
        else:
            print("❌ Помилка при перевірці проекту")
            return False

        # Перевіряємо Quality Gate
        qualitygate_response = requests.get(
            urljoin(host_url, "api/qualitygates/project_status"),
            params={"projectKey": project_key},
            auth=(token, ""),
            timeout=5,
        )

        if qualitygate_response.status_code == 200:
            print("✅ Quality Gate налаштовано")

        return True

    except Exception as e:
        print(f"❌ Помилка при підключенні: {str(e)}")
        return False


if __name__ == "__main__":
    if not check_sonar_connection():
        sys.exit(1)
